"use server"

import { v4 as uuid } from "uuid"
import { createRun as dbCreateRun } from "@/lib/db"
import { executeRun } from "@/lib/runner"
import type { CreateRunInput, Run } from "@/types"

export async function startRun(input: CreateRunInput): Promise<Run> {
  const id = uuid()

  const run = dbCreateRun({
    id,
    repo: input.repo,
    issueNumber: input.issueNumber,
    issueTitle: `Issue #${input.issueNumber}`,
    taskType: "feature",
    config: {
      baseBranch: input.baseBranch || "main",
      extraPrompt: input.extraPrompt || "",
      prLabels: input.prLabels || "codex-generated",
      timeoutMinutes: input.timeoutMinutes || 30,
    },
    trigger: "manual",
  })

  // Fire and forget — don't await
  executeRun(id).catch((err) => {
    console.error(`Run ${id} failed:`, err)
  })

  return run
}
