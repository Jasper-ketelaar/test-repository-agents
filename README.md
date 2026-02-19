# factory-agents

A reusable GitHub Action that automatically implements GitHub issues using [OpenAI Codex CLI](https://github.com/openai/codex) and opens a pull request.

**Flow**: Issue labeled → Codex implements the code → PR opened → Issue commented with result.

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
    runs-on: [self-hosted, macOS]
    permissions:
      contents: write
      issues: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: silver-key-it-consultancy/factory-agents@main
        with:
          issue-number: ${{ github.event.inputs.issue_number || github.event.issue.number }}
          repo-token: ${{ secrets.GITHUB_TOKEN }}
```

Then apply the `codex` label to any issue — or trigger the workflow manually with an issue number.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `issue-number` | Yes | — | GitHub issue number to implement |
| `repo-token` | Yes | — | GitHub token (`GITHUB_TOKEN`) with write access to contents, issues, and pull-requests |
| `base-branch` | No | `main` | Branch to create the feature branch from |
| `extra-prompt` | No | `''` | Additional instructions appended to the Codex prompt |
| `pr-labels` | No | `codex-generated` | Comma-separated labels for the created PR |
| `timeout-minutes` | No | `30` | Timeout for Codex execution |

## Outputs

| Output | Description |
|--------|-------------|
| `pr-number` | The created pull request number |
| `pr-url` | The created pull request URL |

## How It Works

1. **Fetches the issue** title, body, and labels via `gh`
2. **Determines the task type** from issue labels:
   - `bug` label → bug fix prompt (minimal, root-cause focused)
   - `refactor` label → refactoring prompt (preserve behavior)
   - Anything else → feature prompt (default)
3. **Creates a branch** `codex/issue-{number}` from the base branch
4. **Runs `codex exec --full-auto`** with the composed prompt (base + task type + issue context + repo standards)
5. **Commits and pushes** the changes
6. **Opens a PR** linking back to the issue with `Closes #N`
7. **Comments on the issue** with the PR link or failure details

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
- uses: silver-key-it-consultancy/factory-agents@main
  with:
    issue-number: ${{ github.event.issue.number }}
    repo-token: ${{ secrets.GITHUB_TOKEN }}
    extra-prompt: 'Use TDD. Write tests before implementation.'
    pr-labels: 'codex-generated,needs-review'
```

### With a different base branch

```yaml
- uses: silver-key-it-consultancy/factory-agents@main
  with:
    issue-number: ${{ github.event.issue.number }}
    repo-token: ${{ secrets.GITHUB_TOKEN }}
    base-branch: develop
```

### Using outputs

```yaml
- uses: silver-key-it-consultancy/factory-agents@main
  id: codex
  with:
    issue-number: ${{ github.event.issue.number }}
    repo-token: ${{ secrets.GITHUB_TOKEN }}

- run: echo "PR created at ${{ steps.codex.outputs.pr-url }}"
```

## Error Handling

On failure the action will:
- Comment on the issue with the error and a link to the workflow run
- Clean up the remote branch if it was pushed
- Exit with a non-zero code

## Architecture Docs

- [architecture.md](./architecture.md) — Coding and architecture standards
- [skp_guidelines.md](./skp_guidelines.md) — Effort estimation guidelines (SKP)
