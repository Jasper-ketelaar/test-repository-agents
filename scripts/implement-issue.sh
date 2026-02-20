#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# implement-issue.sh
#
# Orchestrates: fetch issue → pick prompt → branch → codex exec → commit → PR
# Expected env vars (set by action.yml):
#   GITHUB_TOKEN, ISSUE_NUMBER, BASE_BRANCH, EXTRA_PROMPT,
#   PR_LABELS, TIMEOUT_MINUTES, ACTION_PATH
# Optional:
#   DASHBOARD_URL - URL of the factory-agents dashboard (e.g. http://localhost:3888)
#   DASHBOARD_RUN_ID - Run ID to report to (created by dashboard)
# ---------------------------------------------------------------------------

log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') $*" >&2; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; }

dashboard_update() {
  if [[ -z "${DASHBOARD_URL:-}" || -z "${DASHBOARD_RUN_ID:-}" ]]; then
    return 0
  fi
  local json="$1"
  curl -s -X PATCH \
    "${DASHBOARD_URL}/api/runs/${DASHBOARD_RUN_ID}" \
    -H "Content-Type: application/json" \
    -d "$json" > /dev/null 2>&1 || true
}

BRANCH_NAME=""
PUSHED=false

cleanup_on_error() {
  local msg="${1:-Unexpected error}"
  log_error "$msg"

  dashboard_update "{\"status\":\"failed\",\"error\":$(echo "$msg" | jq -Rs .),\"finishedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

  gh issue comment "$ISSUE_NUMBER" --body "$(cat <<EOF
❌ **Codex auto-implementation failed**

**Error**: $msg

See workflow run for details: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID
EOF
)" || true

  if [[ "$PUSHED" == true && -n "$BRANCH_NAME" ]]; then
    log_warn "Cleaning up remote branch $BRANCH_NAME"
    git push origin --delete "$BRANCH_NAME" 2>/dev/null || true
  fi

  exit 1
}

trap 'cleanup_on_error' ERR

# ── 1. Validate prerequisites ──────────────────────────────────────────────

for cmd in gh git codex jq; do
  if ! command -v "$cmd" &>/dev/null; then
    cleanup_on_error "$cmd is not installed or not on PATH"
  fi
done

for var in GITHUB_TOKEN ISSUE_NUMBER BASE_BRANCH ACTION_PATH; do
  if [[ -z "${!var:-}" ]]; then
    cleanup_on_error "Required env var $var is not set"
  fi
done

log_info "Codex version: $(codex --version 2>&1 || echo 'unknown')"

# ── 2. Fetch issue details ─────────────────────────────────────────────────

log_info "Fetching issue #$ISSUE_NUMBER"

ISSUE_JSON=$(gh issue view "$ISSUE_NUMBER" --json title,body,labels)
ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
ISSUE_BODY=$(echo "$ISSUE_JSON"  | jq -r '.body // ""')
ISSUE_LABELS=$(echo "$ISSUE_JSON" | jq -r '[.labels[].name] | map(ascii_downcase) | join(",")')

log_info "Issue: $ISSUE_TITLE"
log_info "Labels: ${ISSUE_LABELS:-none}"

# ── 3. Determine task type from labels ─────────────────────────────────────

if echo "$ISSUE_LABELS" | grep -q "bug"; then
  TASK_TYPE="bugfix"
elif echo "$ISSUE_LABELS" | grep -q "refactor"; then
  TASK_TYPE="refactor"
else
  TASK_TYPE="feature"
fi

log_info "Task type: $TASK_TYPE"

# ── 4. Build prompt ────────────────────────────────────────────────────────

PROMPT=""

if [[ -f "$ACTION_PATH/prompts/base.md" ]]; then
  PROMPT=$(cat "$ACTION_PATH/prompts/base.md")
fi

TASK_PROMPT_FILE="$ACTION_PATH/prompts/${TASK_TYPE}.md"
if [[ -f "$TASK_PROMPT_FILE" ]]; then
  PROMPT="$PROMPT"$'\n\n'"$(cat "$TASK_PROMPT_FILE")"
fi

PROMPT="$PROMPT"$'\n\n'"## Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}"$'\n\n'"${ISSUE_BODY}"

if [[ -f "CLAUDE.md" ]]; then
  log_info "Found CLAUDE.md — appending repo coding standards"
  PROMPT="$PROMPT"$'\n\n'"## Repository Coding Standards"$'\n\n'"$(cat CLAUDE.md)"
fi

if [[ -n "${EXTRA_PROMPT:-}" ]]; then
  PROMPT="$PROMPT"$'\n\n'"## Additional Instructions"$'\n\n'"$EXTRA_PROMPT"
fi

# ── 5. Create branch ──────────────────────────────────────────────────────

resolve_base_branch() {
  local requested="${BASE_BRANCH:-}"
  local resolved=""

  if [[ -n "$requested" ]] && git ls-remote --exit-code --heads origin "$requested" >/dev/null 2>&1; then
    resolved="$requested"
  fi

  if [[ -z "$resolved" ]]; then
    if [[ -n "$requested" ]]; then
      log_warn "Requested base branch '$requested' not found on origin; attempting auto-detection"
    fi

    resolved=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)

    if [[ -z "$resolved" ]]; then
      resolved=$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' | head -n1)
    fi

    if [[ -z "$resolved" ]]; then
      resolved=$(git ls-remote --heads origin main >/dev/null 2>&1 && echo "main" || true)
    fi

    if [[ -z "$resolved" ]]; then
      resolved=$(git ls-remote --heads origin master >/dev/null 2>&1 && echo "master" || true)
    fi
  fi

  if [[ -z "$resolved" ]]; then
    cleanup_on_error "Unable to determine a valid base branch on origin"
  fi

  BASE_BRANCH="$resolved"
  log_info "Using base branch: $BASE_BRANCH"
}

resolve_base_branch

BRANCH_NAME="codex/issue-${ISSUE_NUMBER}"

git fetch origin "$BASE_BRANCH"

if git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
  BRANCH_NAME="codex/issue-${ISSUE_NUMBER}-$(date +%s)"
  log_warn "Branch already exists, using $BRANCH_NAME"
fi

git checkout -b "$BRANCH_NAME" "origin/$BASE_BRANCH"
git config --local user.name "Codex Bot"
git config --local user.email "codex-bot@silver-key.nl"

log_info "Created branch $BRANCH_NAME"

dashboard_update "{\"status\":\"running\",\"branch\":\"$BRANCH_NAME\",\"startedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

# ── 6. Run Codex ──────────────────────────────────────────────────────────

TIMEOUT_SECONDS=$(( ${TIMEOUT_MINUTES:-30} * 60 ))

log_info "Running Codex (timeout: ${TIMEOUT_MINUTES:-30}m)"

# codex-cli 0.104.0+ accepts prompt as a positional argument for `exec`.
codex exec --full-auto "$PROMPT" &
CODEX_PID=$!

ELAPSED=0
while kill -0 "$CODEX_PID" 2>/dev/null; do
  if (( ELAPSED >= TIMEOUT_SECONDS )); then
    kill "$CODEX_PID" 2>/dev/null || true
    wait "$CODEX_PID" 2>/dev/null || true
    cleanup_on_error "Codex timed out after ${TIMEOUT_MINUTES:-30} minutes"
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

set +e
wait "$CODEX_PID"
CODEX_EXIT=$?
set -e

if [[ $CODEX_EXIT -ne 0 ]]; then
  cleanup_on_error "Codex exited with code $CODEX_EXIT"
fi

log_info "Codex finished successfully"

# ── 7. Check for changes ──────────────────────────────────────────────────

if git diff --quiet && git diff --cached --quiet; then
  cleanup_on_error "Codex completed but made no changes to the codebase"
fi

CHANGED_FILES=$( (git diff --name-only; git diff --cached --name-only) | sort -u )
FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')

log_info "Changed files ($FILE_COUNT):"
echo "$CHANGED_FILES"

# ── 8. Commit and push ───────────────────────────────────────────────────

git add -A

COMMIT_PREFIX="Implement"
[[ "$TASK_TYPE" == "bugfix" ]] && COMMIT_PREFIX="Fix"
[[ "$TASK_TYPE" == "refactor" ]] && COMMIT_PREFIX="Refactor"

git commit -m "$COMMIT_PREFIX #${ISSUE_NUMBER}: ${ISSUE_TITLE}

Generated by Codex CLI"

git push -u origin "$BRANCH_NAME"
PUSHED=true

log_info "Pushed branch $BRANCH_NAME"

# ── 9. Create PR ─────────────────────────────────────────────────────────

PR_TITLE="${COMMIT_PREFIX} #${ISSUE_NUMBER}: ${ISSUE_TITLE}"

PR_BODY="$(cat <<EOF
## Automated Implementation

This PR was generated by Codex CLI to address issue #${ISSUE_NUMBER}.

### Task type
\`${TASK_TYPE}\`

### Files changed
\`\`\`
$(git diff --stat "origin/${BASE_BRANCH}..HEAD")
\`\`\`

Closes #${ISSUE_NUMBER}

---
🤖 Generated by [Codex CLI](https://github.com/openai/codex) via factory-agents
EOF
)"

LABEL_ARGS=""
IFS=',' read -ra LABELS <<< "${PR_LABELS:-}"
for label in "${LABELS[@]}"; do
  label=$(echo "$label" | xargs)
  [[ -n "$label" ]] && LABEL_ARGS="$LABEL_ARGS --label $label"
done

PR_URL=$(gh pr create \
  --base "$BASE_BRANCH" \
  --head "$BRANCH_NAME" \
  --title "$PR_TITLE" \
  --body "$PR_BODY" \
  $LABEL_ARGS)

PR_NUMBER=$(echo "$PR_URL" | grep -o '[0-9]*$')

log_info "Created PR #$PR_NUMBER: $PR_URL"

dashboard_update "{\"status\":\"success\",\"prNumber\":$PR_NUMBER,\"prUrl\":\"$PR_URL\",\"finishedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

# ── 10. Comment on issue ─────────────────────────────────────────────────

gh issue comment "$ISSUE_NUMBER" --body "$(cat <<EOF
✅ **Codex auto-implementation complete**

Pull request: $PR_URL
Branch: \`$BRANCH_NAME\`
Task type: \`$TASK_TYPE\`
Files changed: $FILE_COUNT

Please review and merge if satisfactory.
EOF
)"

# ── 11. Set outputs ──────────────────────────────────────────────────────

echo "pr-url=$PR_URL" >> "$GITHUB_OUTPUT"
echo "pr-number=$PR_NUMBER" >> "$GITHUB_OUTPUT"

log_info "Done"
