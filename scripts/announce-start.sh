#!/usr/bin/env bash
set -euo pipefail

log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') $*" >&2; }

if [[ -z "${FACTORY_API_URL:-}" || -z "${FACTORY_API_TOKEN:-}" ]]; then
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  log_warn "curl is not available; skipping Factory start announcement"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  log_warn "jq is not available; skipping Factory start announcement"
  exit 0
fi

run_id="${FACTORY_RUN_ID:-}"
if [[ -z "$run_id" && -n "${GITHUB_RUN_ID:-}" ]]; then
  run_id="gh-${GITHUB_RUN_ID}-${ISSUE_NUMBER:-0}"
fi

if [[ -z "$run_id" ]]; then
  log_warn "No FACTORY_RUN_ID and no GITHUB_RUN_ID; skipping Factory start announcement"
  exit 0
fi

issue_number=0
if [[ "${ISSUE_NUMBER:-}" =~ ^[0-9]+$ ]]; then
  issue_number="${ISSUE_NUMBER}"
fi

repo="${GITHUB_REPOSITORY:-unknown/unknown}"
workflow_url="${GITHUB_SERVER_URL:-https://github.com}/${repo}/actions/runs/${GITHUB_RUN_ID:-}"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

workflow_run_id_json="null"
if [[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ ]]; then
  workflow_run_id_json="${GITHUB_RUN_ID}"
fi

payload="$(jq -n \
  --arg repo "$repo" \
  --argjson issueNumber "$issue_number" \
  --arg issueTitle "Issue #${issue_number}" \
  --arg taskType "feature" \
  --arg trigger "workflow" \
  --arg status "queued" \
  --arg workflowUrl "$workflow_url" \
  --arg startedAt "$started_at" \
  --arg log "Workflow started" \
  --argjson workflowRunId "$workflow_run_id_json" \
  '{
    repo: $repo,
    issueNumber: $issueNumber,
    issueTitle: $issueTitle,
    taskType: $taskType,
    trigger: $trigger,
    status: $status,
    workflowRunId: $workflowRunId,
    workflowUrl: $workflowUrl,
    startedAt: $startedAt,
    log: $log
  }'
)"

curl -s -X PATCH \
  "${FACTORY_API_URL%/}/api/agent-runs/external/${run_id}" \
  -H "Content-Type: application/json" \
  -H "X-Factory-Agents-Token: ${FACTORY_API_TOKEN}" \
  -d "$payload" > /dev/null 2>&1 || true

log_info "Announced workflow start to Factory backend with run id ${run_id}"
