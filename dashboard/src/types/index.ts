export type RunStatus = "queued" | "running" | "success" | "failed"

export type TaskType = "feature" | "bugfix" | "refactor"

export type RunTrigger = "manual" | "github-action"

export interface RunConfig {
  baseBranch: string
  extraPrompt: string
  prLabels: string
  timeoutMinutes: number
}

export interface Run {
  id: string
  repo: string
  issueNumber: number
  issueTitle: string
  taskType: TaskType
  status: RunStatus
  branch: string | null
  prNumber: number | null
  prUrl: string | null
  error: string | null
  log: string | null
  config: RunConfig
  createdAt: string
  startedAt: string | null
  finishedAt: string | null
  trigger: RunTrigger
}

export interface CreateRunInput {
  repo: string
  issueNumber: number
  baseBranch?: string
  extraPrompt?: string
  prLabels?: string
  timeoutMinutes?: number
}

export interface RunStats {
  total: number
  running: number
  succeeded: number
  failed: number
}
