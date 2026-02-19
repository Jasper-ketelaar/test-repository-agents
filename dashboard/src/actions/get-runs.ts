"use server"

import { listRuns, getStats, getRecentRepos } from "@/lib/db"
import type { Run, RunStats, RunStatus } from "@/types"

export async function fetchRuns(
  status?: RunStatus
): Promise<{ runs: Run[]; stats: RunStats }> {
  const runs = listRuns(50, 0, status)
  const stats = getStats()
  return { runs, stats }
}

export async function fetchRecentRepos(): Promise<string[]> {
  return getRecentRepos()
}
