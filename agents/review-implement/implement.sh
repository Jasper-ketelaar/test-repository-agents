#!/bin/bash
set -euo pipefail

# Review Implementation Agent
# Usage: ./implement.sh <pr-number> <repo-path>
# Example: ./implement.sh 42 /Users/jasper/Projects/Silver-Key/factory

PR_NUMBER="${1:?Usage: implement.sh <pr-number> <repo-path>}"
REPO_PATH="${2:?Usage: implement.sh <pr-number> <repo-path>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_CLI="/Users/jasper/Library/Application Support/com.jean.desktop/claude-cli/claude"
GH_CLI="/Users/jasper/Library/Application Support/com.jean.desktop/gh-cli/gh"

# Validate inputs
if [ ! -d "$REPO_PATH/.git" ]; then
  echo "Error: $REPO_PATH is not a git repository" >&2
  exit 1
fi

# Check for dirty working tree
if [ -n "$(git -C "$REPO_PATH" status --porcelain)" ]; then
  echo "Error: Working tree at $REPO_PATH has uncommitted changes. Please commit or stash first." >&2
  exit 1
fi

# Resolve GitHub repo slug (owner/name)
REPO_SLUG=$(git -C "$REPO_PATH" remote get-url origin | sed -E 's#.*github\.com[:/](.+?)(\.git)?$#\1#')

echo "Implementing review feedback for PR #${PR_NUMBER} in ${REPO_SLUG}..."

# Fetch PR metadata and extract head branch
PR_META=$("$GH_CLI" pr view "$PR_NUMBER" --repo "$REPO_SLUG" --json title,body,baseRefName,headRefName)
HEAD_BRANCH=$("$GH_CLI" pr view "$PR_NUMBER" --repo "$REPO_SLUG" --json headRefName --jq '.headRefName')

# Checkout the PR branch and pull latest
echo "Checking out branch: ${HEAD_BRANCH}"
git -C "$REPO_PATH" checkout "$HEAD_BRANCH"
git -C "$REPO_PATH" pull origin "$HEAD_BRANCH"

# Fetch all review comments
PR_REVIEWS=$("$GH_CLI" api "repos/${REPO_SLUG}/pulls/${PR_NUMBER}/reviews" 2>/dev/null || echo "[]")
PR_COMMENTS=$("$GH_CLI" api "repos/${REPO_SLUG}/pulls/${PR_NUMBER}/comments" 2>/dev/null || echo "[]")

# Fetch the current diff for context
PR_DIFF=$("$GH_CLI" pr diff "$PR_NUMBER" --repo "$REPO_SLUG")

# Build the prompt
PROMPT="## PR #${PR_NUMBER} — Review Implementation Task

### PR Metadata
${PR_META}

### Review Bodies
${PR_REVIEWS}

### Inline Review Comments
${PR_COMMENTS}

### Current Diff
\`\`\`diff
${PR_DIFF}
\`\`\`

Read the review comments above, triage them, and implement the necessary changes. Start by reading architecture.md and skp_guidelines.md from the repository root."

# Invoke Claude CLI with full edit tools, working directory is the target repo
SYSTEM_PROMPT=$(cat "$SCRIPT_DIR/system-prompt.md")

IMPL_OUTPUT=$(echo "$PROMPT" | "$CLAUDE_CLI" \
  --system-prompt "$SYSTEM_PROMPT" \
  --add-dir "$REPO_PATH" \
  --add-dir "$AGENTS_ROOT" \
  --allowedTools "Read,Glob,Grep,Bash,Edit,Write" \
  --model sonnet \
  --dangerously-skip-permissions \
  --max-budget-usd 2.00 \
  -p \
  2>&1) || true

echo "$IMPL_OUTPUT"

# Stage, commit, and push if there are changes
if [ -n "$(git -C "$REPO_PATH" status --porcelain)" ]; then
  echo ""
  echo "Committing and pushing changes..."
  git -C "$REPO_PATH" add -A
  git -C "$REPO_PATH" commit -m "$(cat <<EOF
Address review feedback for PR #${PR_NUMBER}

Implemented necessary changes from code review.
Skipped optional suggestions and nitpicks.

Co-Authored-By: Claude Agent <noreply@anthropic.com>
EOF
)"
  git -C "$REPO_PATH" push origin "$HEAD_BRANCH"
  echo "Changes pushed to ${HEAD_BRANCH}."
else
  echo ""
  echo "No changes needed — all review comments were optional or already addressed."
fi
