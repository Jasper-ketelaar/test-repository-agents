# factory-agents

A reusable GitHub workflow that automatically implements GitHub issues using [OpenAI Codex CLI](https://github.com/openai/codex) and opens a pull request.

**Flow**: Issue labeled → Research → Plan → Implement → Review → PR opened and commented.

## Prerequisites

Your self-hosted macOS runner must have:

1. **Codex CLI** installed and on `PATH` (`npm i -g @openai/codex`)
2. **Codex authenticated** via `codex login` (subscription-based, persists in `~/.codex/`)
3. **GitHub CLI** (`gh`) installed and on `PATH`
4. **Git** configured

## Quick Start

Create `.github/workflows/codex-implement.yml` in your repository:

```yaml
name: Codex Auto-Implement

on:
  issues:
    types: [labeled]
  workflow_dispatch:
    inputs:
      issue_number:
        description: Issue number to implement
        required: true
        type: number

jobs:
  implement:
    if: >-
      github.event_name == 'workflow_dispatch' ||
      github.event.label.name == 'codex'
    uses: silver-key-it-consultancy/factory-agents/.github/workflows/codex-auto-implement.yml@main
    with:
      issue-number: ${{ github.event.inputs.issue_number || github.event.issue.number }}
      factory-api-url: ${{ vars.FACTORY_API_URL }}
      factory-run-id: ${{ github.run_id }}-${{ github.event.inputs.issue_number || github.event.issue.number }}
    secrets:
      repo-token: ${{ secrets.GITHUB_TOKEN }}
      factory-api-token: ${{ secrets.FACTORY_AGENTS_UPDATE_TOKEN }}
```

Then apply the `codex` label to any issue — or trigger the workflow manually with an issue number.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `issue-number` | Yes | — | GitHub issue number to implement |
| `base-branch` | No | `main` | Branch to create the feature branch from |
| `extra-prompt` | No | `''` | Additional instructions appended to the Codex prompt |
| `pr-labels` | No | `codex-generated` | Comma-separated labels for the created PR (missing labels are auto-created) |
| `timeout-minutes` | No | `30` | Timeout for Codex execution |
| `factory-api-url` | No | `''` | Factory backend base URL for run tracking updates |
| `factory-run-id` | No | `''` | Run identifier used in Factory backend (defaults to `gh-{run_id}-{issue}`) |
| `dashboard-url` | No | `''` | Deprecated legacy alias for `factory-api-url` |
| `dashboard-run-id` | No | `''` | Deprecated legacy alias for `factory-run-id` |

## Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `repo-token` | Yes | GitHub token (`GITHUB_TOKEN`) with write access to contents, issues, and pull-requests |
| `factory-api-token` | No | Shared token for `PATCH /api/agent-runs/external/{id}` |

## Outputs

| Output | Description |
|--------|-------------|
| `pr-number` | The created pull request number |
| `pr-url` | The created pull request URL |

## How It Works

1. **Research step**: fetches issue details and analyzes codebase fit
2. **Plan step**: writes a comprehensive implementation plan
3. **Determines the task type** from issue labels:
   - `bug` label → bug fix prompt (minimal, root-cause focused)
   - `refactor` label → refactoring prompt (preserve behavior)
   - Anything else → feature prompt (default)
4. **Implement step**: creates branch `codex/issue-{number}`, applies code changes, commits, pushes, and opens the PR
5. **Review step**: reviews the produced PR diff and posts a PR comment
6. **Comments on the issue** with status and PR link (or failure details)

If `factory-api-url` and `factory-api-token` are set, the action also reports run lifecycle updates to the Factory backend.

## Task Type Prompts

The action selects a prompt strategy based on issue labels:

| Label | Prompt | Focus |
|-------|--------|-------|
| `bug` | `prompts/bugfix.md` | Smallest fix, root cause, no refactoring |
| `refactor` | `prompts/refactor.md` | Restructure without behavior change |
| _(default)_ | `prompts/feature.md` | Full implementation following existing patterns |

All prompts include `prompts/base.md` which enforces shared constraints (no git ops, no CI changes, minimal focused changes).

## Repo-Specific Standards

If your repository contains a `CLAUDE.md` file in the root, its contents are automatically appended to the Codex prompt as coding standards. This is the recommended way to provide project-specific guidelines.

## Examples

### With extra instructions

```yaml
jobs:
  implement:
    uses: silver-key-it-consultancy/factory-agents/.github/workflows/codex-auto-implement.yml@main
    with:
      issue-number: ${{ github.event.issue.number }}
      extra-prompt: 'Use TDD. Write tests before implementation.'
      pr-labels: 'codex-generated,needs-review'
    secrets:
      repo-token: ${{ secrets.GITHUB_TOKEN }}
```

### With a different base branch

```yaml
jobs:
  implement:
    uses: silver-key-it-consultancy/factory-agents/.github/workflows/codex-auto-implement.yml@main
    with:
      issue-number: ${{ github.event.issue.number }}
      base-branch: develop
    secrets:
      repo-token: ${{ secrets.GITHUB_TOKEN }}
```

### Using outputs

```yaml
jobs:
  codex:
    uses: silver-key-it-consultancy/factory-agents/.github/workflows/codex-auto-implement.yml@main
    with:
      issue-number: ${{ github.event.issue.number }}
    secrets:
      repo-token: ${{ secrets.GITHUB_TOKEN }}

  notify:
    runs-on: ubuntu-latest
    needs: codex
    steps:
      - run: echo "PR created at ${{ needs.codex.outputs.pr-url }}"
```

## Error Handling

On failure the action will:
- Comment on the issue with the error and a link to the workflow run
- Clean up the remote branch if it was pushed
- Exit with a non-zero code

## Architecture Docs

- [architecture.md](./architecture.md) — Coding and architecture standards
- [skp_guidelines.md](./skp_guidelines.md) — Effort estimation guidelines (SKP)
