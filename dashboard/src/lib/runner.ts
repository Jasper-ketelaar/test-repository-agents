import { spawn, execFileSync } from "child_process"
import { mkdtempSync, existsSync, readFileSync, rmSync } from "fs"
import path from "path"
import os from "os"
import { updateRun, appendLog, getRun } from "./db"
import { broadcast } from "./ws"
import type { TaskType } from "@/types"

const VALID_TASK_TYPES: TaskType[] = ["feature", "bugfix", "refactor"]

function log(runId: string, line: string) {
  appendLog(runId, line)
  broadcast(runId, { type: "log", line })
}

function updateStatus(
  runId: string,
  status: string,
  extra?: Partial<Parameters<typeof updateRun>[1]>
) {
  const updates = { status, ...extra } as Parameters<typeof updateRun>[1]
  updateRun(runId, updates)
  broadcast(runId, { type: "status", status, ...extra })
}

function git(args: string[], cwd: string): string {
  return execFileSync("git", args, { cwd, encoding: "utf-8", timeout: 30000 }).trim()
}

function gh(args: string[], cwd: string): string {
  return execFileSync("gh", args, { cwd, encoding: "utf-8", timeout: 60000 }).trim()
}

function detectTaskType(labels: string[]): TaskType {
  if (labels.includes("bug")) return "bugfix"
  if (labels.includes("refactor")) return "refactor"
  return "feature"
}

export async function executeRun(runId: string): Promise<void> {
  const run = getRun(runId)
  if (!run) return

  const { repo, issueNumber, config } = run
  const { baseBranch, extraPrompt, prLabels, timeoutMinutes } = config

  const tmpDir = mkdtempSync(path.join(os.tmpdir(), "codex-run-"))

  try {
    updateStatus(runId, "running", { startedAt: new Date().toISOString() })
    log(runId, `Starting run for ${repo}#${issueNumber}`)

    log(runId, `Cloning ${repo}...`)
    gh(["repo", "clone", repo, ".", "--", "--depth=50"], tmpDir)

    log(runId, `Fetching issue #${issueNumber}...`)
    const issueJson = gh(
      ["issue", "view", String(issueNumber), "--repo", repo, "--json", "title,body,labels"],
      tmpDir
    )
    const issue = JSON.parse(issueJson)
    const issueTitle: string = issue.title ?? `Issue #${issueNumber}`
    const issueBody: string = issue.body ?? ""
    const labels: string[] = (issue.labels ?? []).map(
      (l: { name: string }) => l.name.toLowerCase()
    )

    updateRun(runId, { status: "running" })

    const taskType = detectTaskType(labels)
    log(runId, `Task type: ${taskType}`)

    const promptsDir = path.join(process.cwd(), "..", "prompts")
    let prompt = ""
    const basePromptPath = path.join(promptsDir, "base.md")
    if (existsSync(basePromptPath)) {
      prompt = readFileSync(basePromptPath, "utf-8")
    }

    if (VALID_TASK_TYPES.includes(taskType)) {
      const taskPromptPath = path.join(promptsDir, `${taskType}.md`)
      if (existsSync(taskPromptPath)) {
        prompt += "\n\n" + readFileSync(taskPromptPath, "utf-8")
      }
    }

    prompt += `\n\n## Issue #${issueNumber}: ${issueTitle}\n\n${issueBody}`

    const claudeMdPath = path.join(tmpDir, "CLAUDE.md")
    if (existsSync(claudeMdPath)) {
      log(runId, "Found CLAUDE.md — appending repo coding standards")
      prompt += "\n\n## Repository Coding Standards\n\n" + readFileSync(claudeMdPath, "utf-8")
    }

    if (extraPrompt) {
      prompt += `\n\n## Additional Instructions\n\n${extraPrompt}`
    }

    let branchName = `codex/issue-${issueNumber}`
    git(["fetch", "origin", baseBranch], tmpDir)

    const remoteBranches = git(["ls-remote", "--heads", "origin"], tmpDir)
    if (remoteBranches.includes(branchName)) {
      branchName = `codex/issue-${issueNumber}-${Math.floor(Date.now() / 1000)}`
      log(runId, `Branch already exists, using ${branchName}`)
    }

    git(["checkout", "-b", branchName, `origin/${baseBranch}`], tmpDir)
    git(["config", "user.name", "Codex Bot"], tmpDir)
    git(["config", "user.email", "codex-bot@silver-key.nl"], tmpDir)
    updateStatus(runId, "running", { branch: branchName })
    log(runId, `Created branch ${branchName}`)

    log(runId, "Running Codex...")
    const codexExitCode = await new Promise<number>((resolve) => {
      const child = spawn("codex", ["exec", "--full-auto", "-q", prompt], {
        cwd: tmpDir,
        stdio: ["ignore", "pipe", "pipe"],
      })

      const timeout = setTimeout(() => {
        child.kill("SIGTERM")
        log(runId, `Codex timed out after ${timeoutMinutes} minutes`)
        resolve(124)
      }, timeoutMinutes * 60 * 1000)

      child.stdout.on("data", (data: Buffer) => {
        for (const line of data.toString().split("\n")) {
          if (line.trim()) log(runId, line)
        }
      })

      child.stderr.on("data", (data: Buffer) => {
        for (const line of data.toString().split("\n")) {
          if (line.trim()) log(runId, `[stderr] ${line}`)
        }
      })

      child.on("close", (code) => {
        clearTimeout(timeout)
        resolve(code ?? 1)
      })
    })

    if (codexExitCode !== 0) {
      throw new Error(`Codex exited with code ${codexExitCode}`)
    }

    log(runId, "Codex finished")

    const diff = git(["status", "--porcelain"], tmpDir)
    if (!diff) {
      throw new Error("Codex completed but made no changes to the codebase")
    }

    const changedFiles = diff.split("\n").map((l) => l.trim()).filter(Boolean)
    log(runId, `Changed files (${changedFiles.length}):`)
    for (const f of changedFiles) log(runId, `  ${f}`)

    const commitPrefix =
      taskType === "bugfix" ? "Fix"
      : taskType === "refactor" ? "Refactor"
      : "Implement"

    git(["add", "-A"], tmpDir)
    git(["commit", "-m", `${commitPrefix} #${issueNumber}: ${issueTitle}\n\nGenerated by Codex CLI`], tmpDir)
    git(["push", "-u", "origin", branchName], tmpDir)
    log(runId, `Pushed branch ${branchName}`)

    const prTitle = `${commitPrefix} #${issueNumber}: ${issueTitle}`
    const prBody = [
      "## Automated Implementation",
      "",
      `This PR was generated by Codex CLI to address issue #${issueNumber}.`,
      "",
      "### Task type",
      `\`${taskType}\``,
      "",
      `Closes #${issueNumber}`,
      "",
      "---",
      "🤖 Generated by [Codex CLI](https://github.com/openai/codex) via factory-agents",
    ].join("\n")

    const prArgs = [
      "pr", "create",
      "--repo", repo,
      "--base", baseBranch,
      "--head", branchName,
      "--title", prTitle,
      "--body", prBody,
    ]
    if (prLabels) {
      for (const label of prLabels.split(",")) {
        const trimmed = label.trim()
        if (trimmed) prArgs.push("--label", trimmed)
      }
    }

    const prUrl = gh(prArgs, tmpDir)
    const prNumber = parseInt(prUrl.match(/\/(\d+)$/)?.[1] ?? "0", 10)
    log(runId, `Created PR #${prNumber}: ${prUrl}`)

    gh([
      "issue", "comment", String(issueNumber),
      "--repo", repo,
      "--body", `✅ **Codex auto-implementation complete**\n\nPull request: ${prUrl}\nBranch: \`${branchName}\`\nTask type: \`${taskType}\``,
    ], tmpDir)

    updateStatus(runId, "success", {
      prNumber,
      prUrl,
      finishedAt: new Date().toISOString(),
    })
    log(runId, "Done")
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    log(runId, `ERROR: ${message}`)
    updateStatus(runId, "failed", {
      error: message,
      finishedAt: new Date().toISOString(),
    })

    try {
      gh([
        "issue", "comment", String(issueNumber),
        "--repo", repo,
        "--body", `❌ **Codex auto-implementation failed**\n\n**Error**: ${message}`,
      ], tmpDir)
    } catch {
      // ignore comment failure
    }
  } finally {
    try {
      rmSync(tmpDir, { recursive: true, force: true })
    } catch {
      // ignore cleanup failure
    }
  }
}
