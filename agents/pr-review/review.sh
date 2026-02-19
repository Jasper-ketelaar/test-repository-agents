#!/bin/bash
set -euo pipefail

# PR Review Agent
# Usage: ./review.sh <pr-number> <repo-path>
# Example: ./review.sh 42 /Users/jasper/Projects/Silver-Key/factory

PR_NUMBER="${1:?Usage: review.sh <pr-number> <repo-path>}"
REPO_PATH="${2:?Usage: review.sh <pr-number> <repo-path>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_CLI="/Users/jasper/Library/Application Support/com.jean.desktop/claude-cli/claude"
GH_CLI="/Users/jasper/Library/Application Support/com.jean.desktop/gh-cli/gh"

# Validate inputs
if [ ! -d "$REPO_PATH/.git" ]; then
  echo "Error: $REPO_PATH is not a git repository" >&2
  exit 1
fi

# Resolve GitHub repo slug (owner/name)
REPO_SLUG=$(git -C "$REPO_PATH" remote get-url origin | sed -E 's#.*github\.com[:/](.+?)(\.git)?$#\1#')

echo "Reviewing PR #${PR_NUMBER} in ${REPO_SLUG}..."

# Fetch PR metadata
PR_META=$("$GH_CLI" pr view "$PR_NUMBER" --repo "$REPO_SLUG" --json title,body,baseRefName,headRefName)

# Fetch full PR diff
PR_DIFF=$("$GH_CLI" pr diff "$PR_NUMBER" --repo "$REPO_SLUG")

# Build the prompt
PROMPT="## PR #${PR_NUMBER}

### Metadata
${PR_META}

### Diff
\`\`\`diff
${PR_DIFF}
\`\`\`

Review this PR against the architecture standards. Start by reading architecture.md and skp_guidelines.md from the repository root."

# Invoke Claude CLI in print mode with read-only tools
SYSTEM_PROMPT=$(cat "$SCRIPT_DIR/system-prompt.md")

REVIEW_OUTPUT=$(echo "$PROMPT" | "$CLAUDE_CLI" \
  --system-prompt "$SYSTEM_PROMPT" \
  --add-dir "$REPO_PATH" \
  --add-dir "$AGENTS_ROOT" \
  --allowedTools "Read,Glob,Grep" \
  --model sonnet \
  --dangerously-skip-permissions \
  --max-budget-usd 1.00 \
  -p)

echo "Review generated. Posting to PR..."

# Post the review as a formal PR review
echo "$REVIEW_OUTPUT" | "$GH_CLI" pr review "$PR_NUMBER" \
  --repo "$REPO_SLUG" \
  --body-file - \
  --comment

echo "Review posted to PR #${PR_NUMBER}."
