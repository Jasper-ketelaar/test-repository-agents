#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-}"
if [[ -z "$PHASE" ]]; then
  echo "Usage: implement-issue.sh <research|plan|implement|review>" >&2
  exit 1
fi

case "$PHASE" in
  research|plan|implement|review) ;;
  *)
    echo "Invalid phase '$PHASE'. Use: research|plan|implement|review" >&2
    exit 1
    ;;
esac

log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') $*" >&2; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; }

FACTORY_API_URL="${FACTORY_API_URL:-${DASHBOARD_URL:-}}"
FACTORY_RUN_ID="${FACTORY_RUN_ID:-${DASHBOARD_RUN_ID:-}}"
if [[ -z "${FACTORY_RUN_ID:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
  FACTORY_RUN_ID="gh-${GITHUB_RUN_ID}-${ISSUE_NUMBER:-0}"
fi

STATE_DIR="${RUNNER_TEMP:-/tmp}/factory-agents/${GITHUB_RUN_ID:-local}-${ISSUE_NUMBER:-0}"
STATE_FILE="$STATE_DIR/state.json"
ISSUE_FILE="$STATE_DIR/issue.json"
RESEARCH_FILE="$STATE_DIR/research.md"
PLAN_FILE="$STATE_DIR/plan.md"
REVIEW_FILE="$STATE_DIR/review.md"

mkdir -p "$STATE_DIR"

json_escape() {
  local value="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -Rn --arg v "$value" '$v'
    return
  fi
  local escaped="${value//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  printf '"%s"' "$escaped"
}

state_get() {
  local expr="$1"
  if [[ ! -f "$STATE_FILE" ]]; then
    echo ""
    return 0
  fi
  jq -r "$expr // empty" "$STATE_FILE" 2>/dev/null || true
}

state_set_string() {
  local key="$1"
  local value="$2"
  local tmp_file
  tmp_file=$(mktemp)
  if [[ -f "$STATE_FILE" ]]; then
    jq --arg k "$key" --arg v "$value" '.[$k]=$v' "$STATE_FILE" > "$tmp_file"
  else
    jq -n --arg k "$key" --arg v "$value" '{($k):$v}' > "$tmp_file"
  fi
  mv "$tmp_file" "$STATE_FILE"
}

state_set_bool() {
  local key="$1"
  local value="$2"
  local tmp_file
  tmp_file=$(mktemp)
  if [[ -f "$STATE_FILE" ]]; then
    jq --arg k "$key" --argjson v "$value" '.[$k]=$v' "$STATE_FILE" > "$tmp_file"
  else
    jq -n --arg k "$key" --argjson v "$value" '{($k):$v}' > "$tmp_file"
  fi
  mv "$tmp_file" "$STATE_FILE"
}

build_factory_metadata() {
  local issue_number="0"
  if [[ "${ISSUE_NUMBER:-}" =~ ^[0-9]+$ ]]; then
    issue_number="${ISSUE_NUMBER}"
  fi

  local state_issue_number
  state_issue_number=$(state_get '.issueNumber')
  if [[ "$state_issue_number" =~ ^[0-9]+$ ]]; then
    issue_number="$state_issue_number"
  fi

  local workflow_run_id="null"
  if [[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ ]]; then
    workflow_run_id="${GITHUB_RUN_ID}"
  fi

  local issue_title task_type
  issue_title=$(state_get '.issueTitle')
  task_type=$(state_get '.taskType')
  [[ -z "$issue_title" ]] && issue_title="Issue #${issue_number}"
  [[ -z "$task_type" ]] && task_type="feature"

  local repo_json issue_title_json task_type_json trigger_json workflow_url_json
  repo_json=$(json_escape "${GITHUB_REPOSITORY:-unknown/unknown}")
  issue_title_json=$(json_escape "$issue_title")
  task_type_json=$(json_escape "$task_type")
  trigger_json=$(json_escape "workflow")
  workflow_url_json=$(json_escape "${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown/unknown}/actions/runs/${GITHUB_RUN_ID:-}")

  printf '"repo":%s,"issueNumber":%s,"issueTitle":%s,"taskType":%s,"trigger":%s,"workflowRunId":%s,"workflowUrl":%s' \
    "$repo_json" "$issue_number" "$issue_title_json" "$task_type_json" "$trigger_json" "$workflow_run_id" "$workflow_url_json"
}

factory_update() {
  if [[ -z "${FACTORY_API_URL:-}" || -z "${FACTORY_RUN_ID:-}" || -z "${FACTORY_API_TOKEN:-}" ]]; then
    return 0
  fi
  local json="$1"
  curl -s -X PATCH \
    "${FACTORY_API_URL%/}/api/agent-runs/external/${FACTORY_RUN_ID}" \
    -H "Content-Type: application/json" \
    -H "X-Factory-Agents-Token: ${FACTORY_API_TOKEN}" \
    -d "$json" > /dev/null 2>&1 || true
}

cleanup_on_error() {
  local msg="${1:-Unexpected error}"
  log_error "$msg"

  local escaped_msg
  escaped_msg=$(json_escape "$msg")
  factory_update "{$(build_factory_metadata),\"status\":\"failed\",\"error\":${escaped_msg},\"finishedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

  if command -v gh >/dev/null 2>&1 && [[ "${ISSUE_NUMBER:-}" =~ ^[0-9]+$ ]]; then
    gh issue comment "$ISSUE_NUMBER" --body "$(cat <<MSG
❌ **Codex auto-implementation failed**

Phase: $PHASE
**Error**: $msg

See workflow run for details: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID
MSG
)" || true
  fi

  local pushed branch_name pr_number
  pushed=$(state_get '.pushed')
  branch_name=$(state_get '.branchName')
  pr_number=$(state_get '.prNumber')

  if [[ "$pushed" == "true" && -n "$branch_name" && -z "$pr_number" ]]; then
    log_warn "Cleaning up remote branch $branch_name"
    git push origin --delete "$branch_name" > /dev/null 2>&1 || true
  fi

  exit 1
}

trap 'cleanup_on_error' ERR

ensure_prerequisites() {
  for cmd in gh git codex jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      cleanup_on_error "$cmd is not installed or not on PATH"
    fi
  done

  for var in GITHUB_TOKEN ISSUE_NUMBER BASE_BRANCH ACTION_PATH; do
    if [[ -z "${!var:-}" ]]; then
      cleanup_on_error "Required env var $var is not set"
    fi
  done
}

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

run_codex_phase() {
  local phase_name="$1"
  local prompt="$2"
  local output_file="${3:-}"
  local timeout_seconds=$(( ${TIMEOUT_MINUTES:-30} * 60 ))

  local prompt_file
  prompt_file=$(mktemp)
  printf '%s' "$prompt" > "$prompt_file"

  local -a cmd
  cmd=(codex exec --full-auto)

  if [[ "$phase_name" != "implement" ]]; then
    cmd+=(--sandbox read-only)
  fi

  if [[ -n "$output_file" ]]; then
    cmd+=(--output-last-message "$output_file")
  fi

  cmd+=("-")

  log_info "Running Codex phase '$phase_name' (timeout: ${TIMEOUT_MINUTES:-30}m)"

  "${cmd[@]}" < "$prompt_file" &
  local codex_pid=$!
  local elapsed=0

  while kill -0 "$codex_pid" 2>/dev/null; do
    if (( elapsed >= timeout_seconds )); then
      kill "$codex_pid" 2>/dev/null || true
      wait "$codex_pid" 2>/dev/null || true
      rm -f "$prompt_file"
      cleanup_on_error "Codex phase '$phase_name' timed out after ${TIMEOUT_MINUTES:-30} minutes"
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  set +e
  wait "$codex_pid"
  local codex_exit=$?
  set -e

  rm -f "$prompt_file"

  if [[ $codex_exit -ne 0 ]]; then
    cleanup_on_error "Codex phase '$phase_name' exited with code $codex_exit"
  fi

  log_info "Codex phase '$phase_name' completed"
}

phase_research() {
  log_info "Phase 1/4: Research"

  if [[ ! "${ISSUE_NUMBER}" =~ ^[0-9]+$ ]]; then
    cleanup_on_error "ISSUE_NUMBER must be numeric"
  fi

  log_info "Fetching issue #$ISSUE_NUMBER"
  local issue_json issue_title issue_body issue_labels task_type
  issue_json=$(gh issue view "$ISSUE_NUMBER" --json title,body,labels)
  issue_title=$(echo "$issue_json" | jq -r '.title')
  issue_body=$(echo "$issue_json" | jq -r '.body // ""')
  issue_labels=$(echo "$issue_json" | jq -r '[.labels[].name] | map(ascii_downcase) | join(",")')
  echo "$issue_json" > "$ISSUE_FILE"

  if echo "$issue_labels" | grep -q "bug"; then
    task_type="bugfix"
  elif echo "$issue_labels" | grep -q "refactor"; then
    task_type="refactor"
  else
    task_type="feature"
  fi

  resolve_base_branch

  jq -n \
    --argjson issueNumber "$ISSUE_NUMBER" \
    --arg issueTitle "$issue_title" \
    --arg issueBody "$issue_body" \
    --arg issueLabels "$issue_labels" \
    --arg taskType "$task_type" \
    --arg baseBranch "$BASE_BRANCH" \
    --arg stateDir "$STATE_DIR" \
    --arg researchFile "$RESEARCH_FILE" \
    --arg planFile "$PLAN_FILE" \
    --arg reviewFile "$REVIEW_FILE" \
    '{
      issueNumber: $issueNumber,
      issueTitle: $issueTitle,
      issueBody: $issueBody,
      issueLabels: $issueLabels,
      taskType: $taskType,
      baseBranch: $baseBranch,
      branchName: "",
      pushed: false,
      prNumber: "",
      prUrl: "",
      stateDir: $stateDir,
      researchFile: $researchFile,
      planFile: $planFile,
      reviewFile: $reviewFile
    }' > "$STATE_FILE"

  factory_update "{$(build_factory_metadata),\"status\":\"queued\",\"phase\":\"research\"}"

  local prompt=""
  if [[ -f "$ACTION_PATH/prompts/research.md" ]]; then
    prompt=$(cat "$ACTION_PATH/prompts/research.md")
  fi

  prompt="$prompt"$'\n\n'"## Issue #${ISSUE_NUMBER}: ${issue_title}"$'\n\n'"${issue_body}"
  prompt="$prompt"$'\n\n'"## Labels"$'\n\n'"${issue_labels:-none}"
  prompt="$prompt"$'\n\n'"## Task Type"$'\n\n'"${task_type}"

  if [[ -f "CLAUDE.md" ]]; then
    prompt="$prompt"$'\n\n'"## Repository Coding Standards"$'\n\n'"$(cat CLAUDE.md)"
  fi

  if [[ -n "${EXTRA_PROMPT:-}" ]]; then
    prompt="$prompt"$'\n\n'"## Additional Instructions"$'\n\n'"$EXTRA_PROMPT"
  fi

  prompt="$prompt"$'\n\n'"Return only Markdown for the required sections."

  run_codex_phase "research" "$prompt" "$RESEARCH_FILE"

  if [[ ! -s "$RESEARCH_FILE" ]]; then
    cleanup_on_error "Research phase did not produce output"
  fi

  log_info "Research written to $RESEARCH_FILE"
}

phase_plan() {
  log_info "Phase 2/4: Plan"

  if [[ ! -f "$STATE_FILE" ]]; then
    cleanup_on_error "State file not found. Run research phase first."
  fi

  local research_path issue_title issue_body issue_labels task_type
  research_path=$(state_get '.researchFile')
  [[ -z "$research_path" ]] && research_path="$RESEARCH_FILE"

  if [[ ! -s "$research_path" ]]; then
    cleanup_on_error "Research artifact not found. Run research phase first."
  fi

  issue_title=$(state_get '.issueTitle')
  issue_body=$(state_get '.issueBody')
  issue_labels=$(state_get '.issueLabels')
  task_type=$(state_get '.taskType')

  local prompt=""
  if [[ -f "$ACTION_PATH/prompts/plan.md" ]]; then
    prompt=$(cat "$ACTION_PATH/prompts/plan.md")
  fi

  prompt="$prompt"$'\n\n'"## Issue #${ISSUE_NUMBER}: ${issue_title}"$'\n\n'"${issue_body}"
  prompt="$prompt"$'\n\n'"## Labels"$'\n\n'"${issue_labels:-none}"
  prompt="$prompt"$'\n\n'"## Task Type"$'\n\n'"${task_type}"
  prompt="$prompt"$'\n\n'"## Research Findings"$'\n\n'"$(cat "$research_path")"

  if [[ -n "${EXTRA_PROMPT:-}" ]]; then
    prompt="$prompt"$'\n\n'"## Additional Instructions"$'\n\n'"$EXTRA_PROMPT"
  fi

  prompt="$prompt"$'\n\n'"Return only Markdown for the required sections."

  run_codex_phase "plan" "$prompt" "$PLAN_FILE"

  if [[ ! -s "$PLAN_FILE" ]]; then
    cleanup_on_error "Plan phase did not produce output"
  fi

  log_info "Plan written to $PLAN_FILE"
}

phase_implement() {
  log_info "Phase 3/4: Implement"

  if [[ ! -f "$STATE_FILE" ]]; then
    cleanup_on_error "State file not found. Run research and plan phases first."
  fi

  local issue_title issue_body issue_labels task_type planned_base_branch
  issue_title=$(state_get '.issueTitle')
  issue_body=$(state_get '.issueBody')
  issue_labels=$(state_get '.issueLabels')
  task_type=$(state_get '.taskType')
  planned_base_branch=$(state_get '.baseBranch')

  if [[ -z "$issue_title" || -z "$task_type" ]]; then
    cleanup_on_error "State is incomplete. Run research phase first."
  fi

  if [[ -n "$planned_base_branch" ]]; then
    BASE_BRANCH="$planned_base_branch"
  fi

  if [[ ! -s "$RESEARCH_FILE" || ! -s "$PLAN_FILE" ]]; then
    cleanup_on_error "Research/plan artifacts are missing. Run research and plan phases first."
  fi

  resolve_base_branch

  local branch_name="codex/issue-${ISSUE_NUMBER}"
  git fetch origin "$BASE_BRANCH"

  if git show-ref --verify --quiet "refs/heads/${branch_name}" || git ls-remote --heads origin "$branch_name" | grep -q "$branch_name"; then
    branch_name="codex/issue-${ISSUE_NUMBER}-$(date +%s)"
    log_warn "Branch already exists, using $branch_name"
  fi

  git checkout -b "$branch_name" "origin/$BASE_BRANCH"
  git config --local user.name "Codex Bot"
  git config --local user.email "codex-bot@silver-key.nl"

  state_set_string "branchName" "$branch_name"
  state_set_bool "pushed" false
  state_set_string "prNumber" ""
  state_set_string "prUrl" ""

  local branch_json
  branch_json=$(json_escape "$branch_name")
  factory_update "{$(build_factory_metadata),\"status\":\"running\",\"phase\":\"implement\",\"branch\":${branch_json},\"startedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

  local prompt=""
  if [[ -f "$ACTION_PATH/prompts/base.md" ]]; then
    prompt=$(cat "$ACTION_PATH/prompts/base.md")
  fi

  local task_prompt_file="$ACTION_PATH/prompts/${task_type}.md"
  if [[ -f "$task_prompt_file" ]]; then
    prompt="$prompt"$'\n\n'"$(cat "$task_prompt_file")"
  fi

  prompt="$prompt"$'\n\n'"## Issue #${ISSUE_NUMBER}: ${issue_title}"$'\n\n'"${issue_body}"
  prompt="$prompt"$'\n\n'"## Labels"$'\n\n'"${issue_labels:-none}"
  prompt="$prompt"$'\n\n'"## Research Findings"$'\n\n'"$(cat "$RESEARCH_FILE")"
  prompt="$prompt"$'\n\n'"## Approved Plan"$'\n\n'"$(cat "$PLAN_FILE")"
  prompt="$prompt"$'\n\n'"## Implementation Requirements"$'\n\n'"- Implement the issue according to the approved plan."$'\n'"- Keep scope aligned to the issue."$'\n'"- Do not modify research/plan artifacts."

  if [[ -f "CLAUDE.md" ]]; then
    prompt="$prompt"$'\n\n'"## Repository Coding Standards"$'\n\n'"$(cat CLAUDE.md)"
  fi

  if [[ -n "${EXTRA_PROMPT:-}" ]]; then
    prompt="$prompt"$'\n\n'"## Additional Instructions"$'\n\n'"$EXTRA_PROMPT"
  fi

  run_codex_phase "implement" "$prompt"

  if git diff --quiet && git diff --cached --quiet; then
    cleanup_on_error "Codex completed but made no changes to the codebase"
  fi

  local changed_files file_count
  changed_files=$( (git diff --name-only; git diff --cached --name-only) | sort -u )
  file_count=$(echo "$changed_files" | sed '/^$/d' | wc -l | tr -d ' ')

  log_info "Changed files ($file_count):"
  echo "$changed_files"

  git add -A

  local commit_prefix="Implement"
  [[ "$task_type" == "bugfix" ]] && commit_prefix="Fix"
  [[ "$task_type" == "refactor" ]] && commit_prefix="Refactor"

  git commit -m "$commit_prefix #${ISSUE_NUMBER}: ${issue_title}

Generated by Codex CLI"

  git push -u origin "$branch_name"
  state_set_bool "pushed" true

  log_info "Pushed branch $branch_name"

  local pr_title pr_body pr_url pr_number
  pr_title="${commit_prefix} #${ISSUE_NUMBER}: ${issue_title}"

  pr_body="$(cat <<BODY
## Automated Implementation

This PR was generated by Codex CLI to address issue #${ISSUE_NUMBER}.

### Task type
\`${task_type}\`

### Files changed
\`\`\`
$(git diff --stat "origin/${BASE_BRANCH}..HEAD")
\`\`\`

Closes #${ISSUE_NUMBER}

---
Generated by [Codex CLI](https://github.com/openai/codex) via factory-agents
BODY
)"

  pr_url=$(gh pr create \
    --base "$BASE_BRANCH" \
    --head "$branch_name" \
    --title "$pr_title" \
    --body "$pr_body")

  pr_number=$(echo "$pr_url" | grep -o '[0-9]*$')
  if [[ -z "$pr_number" ]]; then
    cleanup_on_error "Failed to parse PR number from URL: $pr_url"
  fi

  log_info "Created PR #$pr_number: $pr_url"

  local label
  IFS=',' read -ra labels <<< "${PR_LABELS:-}"
  for label in "${labels[@]}"; do
    label=$(echo "$label" | xargs)
    [[ -z "$label" ]] && continue

    if ! gh label create "$label" --description "Auto-generated by factory-agents" --color "0E8A16" --force >/dev/null 2>&1; then
      log_warn "Could not create or update label '$label'; continuing without failing"
    fi

    if ! gh pr edit "$pr_number" --add-label "$label" >/dev/null 2>&1; then
      log_warn "Could not add label '$label' to PR #$pr_number"
    fi
  done

  state_set_string "prNumber" "$pr_number"
  state_set_string "prUrl" "$pr_url"

  local pr_url_json pr_number_json
  pr_url_json=$(json_escape "$pr_url")
  pr_number_json="null"
  if [[ "$pr_number" =~ ^[0-9]+$ ]]; then
    pr_number_json="$pr_number"
  fi

  factory_update "{$(build_factory_metadata),\"status\":\"success\",\"phase\":\"implement\",\"prNumber\":${pr_number_json},\"prUrl\":${pr_url_json},\"finishedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

  gh issue comment "$ISSUE_NUMBER" --body "$(cat <<MSG
✅ **Codex auto-implementation complete**

Pull request: $pr_url
Branch: $branch_name
Task type: $task_type
Files changed: $file_count

A review comment will be posted to the PR in the next step.
MSG
)"

  echo "pr-url=$pr_url" >> "$GITHUB_OUTPUT"
  echo "pr-number=$pr_number" >> "$GITHUB_OUTPUT"
}

phase_review() {
  log_info "Phase 4/4: Review"

  if [[ ! -f "$STATE_FILE" ]]; then
    cleanup_on_error "State file not found. Run previous phases first."
  fi

  local pr_number issue_title issue_body task_type
  pr_number=$(state_get '.prNumber')
  issue_title=$(state_get '.issueTitle')
  issue_body=$(state_get '.issueBody')
  task_type=$(state_get '.taskType')

  if [[ -z "$pr_number" ]]; then
    cleanup_on_error "PR number not found in state. Run implement phase first."
  fi

  local pr_meta pr_diff
  pr_meta=$(gh pr view "$pr_number" --json title,body,baseRefName,headRefName,additions,deletions)
  pr_diff=$(gh pr diff "$pr_number")

  local max_chars=120000
  if (( ${#pr_diff} > max_chars )); then
    pr_diff="${pr_diff:0:max_chars}"
    pr_diff="$pr_diff"$'\n\n[Diff truncated for review context.]'
  fi

  local prompt=""
  if [[ -f "$ACTION_PATH/prompts/review.md" ]]; then
    prompt=$(cat "$ACTION_PATH/prompts/review.md")
  fi

  prompt="$prompt"$'\n\n'"## Issue #${ISSUE_NUMBER}: ${issue_title}"$'\n\n'"${issue_body}"
  prompt="$prompt"$'\n\n'"## Task Type"$'\n\n'"${task_type}"

  if [[ -s "$RESEARCH_FILE" ]]; then
    prompt="$prompt"$'\n\n'"## Research Findings"$'\n\n'"$(cat "$RESEARCH_FILE")"
  fi

  if [[ -s "$PLAN_FILE" ]]; then
    prompt="$prompt"$'\n\n'"## Approved Plan"$'\n\n'"$(cat "$PLAN_FILE")"
  fi

  prompt="$prompt"$'\n\n'"## PR Metadata (JSON)"$'\n\n'"$pr_meta"
  prompt="$prompt"$'\n\n'"## PR Diff"$'\n\n'"\`\`\`diff"$'\n'"$pr_diff"$'\n'"\`\`\`"
  prompt="$prompt"$'\n\n'"Return only Markdown suitable for posting directly as a PR comment."

  run_codex_phase "review" "$prompt" "$REVIEW_FILE"

  if [[ ! -s "$REVIEW_FILE" ]]; then
    cleanup_on_error "Review phase did not produce output"
  fi

  gh pr comment "$pr_number" --body-file "$REVIEW_FILE"

  log_info "Posted review comment to PR #$pr_number"
}

ensure_prerequisites
log_info "Codex version: $(codex --version 2>&1 || echo 'unknown')"

case "$PHASE" in
  research)
    phase_research
    ;;
  plan)
    phase_plan
    ;;
  implement)
    phase_implement
    ;;
  review)
    phase_review
    ;;
esac

log_info "Phase '$PHASE' done"
