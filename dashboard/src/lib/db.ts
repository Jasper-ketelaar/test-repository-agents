import Database from "better-sqlite3"
import { mkdirSync } from "fs"
import path from "path"
import type { Run, RunConfig, RunStats, RunStatus } from "@/types"

const DATA_DIR = path.join(process.cwd(), "data")
const DB_PATH = path.join(DATA_DIR, "agents.db")

let db: Database.Database | null = null

function getDb(): Database.Database {
  if (!db) {
    mkdirSync(DATA_DIR, { recursive: true })
    db = new Database(DB_PATH)
    db.pragma("journal_mode = WAL")
    db.pragma("foreign_keys = ON")
    db.exec(`
      CREATE TABLE IF NOT EXISTS runs (
        id            TEXT PRIMARY KEY,
        repo          TEXT NOT NULL,
        issue_number  INTEGER NOT NULL,
        issue_title   TEXT NOT NULL,
        task_type     TEXT NOT NULL,
        status        TEXT NOT NULL DEFAULT 'queued',
        branch        TEXT,
        pr_number     INTEGER,
        pr_url        TEXT,
        error         TEXT,
        log           TEXT,
        config        TEXT NOT NULL,
        created_at    TEXT NOT NULL,
        started_at    TEXT,
        finished_at   TEXT,
        trigger       TEXT NOT NULL DEFAULT 'manual'
      )
    `)
  }
  return db
}

interface RunRow {
  id: string
  repo: string
  issue_number: number
  issue_title: string
  task_type: string
  status: string
  branch: string | null
  pr_number: number | null
  pr_url: string | null
  error: string | null
  log: string | null
  config: string
  created_at: string
  started_at: string | null
  finished_at: string | null
  trigger: string
}

function rowToRun(row: RunRow): Run {
  return {
    id: row.id,
    repo: row.repo,
    issueNumber: row.issue_number,
    issueTitle: row.issue_title,
    taskType: row.task_type as Run["taskType"],
    status: row.status as Run["status"],
    branch: row.branch,
    prNumber: row.pr_number,
    prUrl: row.pr_url,
    error: row.error,
    log: row.log,
    config: JSON.parse(row.config) as RunConfig,
    createdAt: row.created_at,
    startedAt: row.started_at,
    finishedAt: row.finished_at,
    trigger: row.trigger as Run["trigger"],
  }
}

export function listRuns(
  limit = 50,
  offset = 0,
  status?: RunStatus
): Run[] {
  const d = getDb()
  if (status) {
    const rows = d
      .prepare(
        "SELECT * FROM runs WHERE status = ? ORDER BY created_at DESC LIMIT ? OFFSET ?"
      )
      .all(status, limit, offset) as RunRow[]
    return rows.map(rowToRun)
  }
  const rows = d
    .prepare("SELECT * FROM runs ORDER BY created_at DESC LIMIT ? OFFSET ?")
    .all(limit, offset) as RunRow[]
  return rows.map(rowToRun)
}

export function getRun(id: string): Run | null {
  const d = getDb()
  const row = d.prepare("SELECT * FROM runs WHERE id = ?").get(id) as
    | RunRow
    | undefined
  return row ? rowToRun(row) : null
}

export function createRun(run: {
  id: string
  repo: string
  issueNumber: number
  issueTitle: string
  taskType: string
  config: RunConfig
  trigger: string
}): Run {
  const d = getDb()
  const now = new Date().toISOString()
  d.prepare(
    `INSERT INTO runs (id, repo, issue_number, issue_title, task_type, status, config, created_at, trigger)
     VALUES (?, ?, ?, ?, ?, 'queued', ?, ?, ?)`
  ).run(
    run.id,
    run.repo,
    run.issueNumber,
    run.issueTitle,
    run.taskType,
    JSON.stringify(run.config),
    now,
    run.trigger
  )
  return getRun(run.id)!
}

export function updateRun(
  id: string,
  updates: Partial<{
    status: string
    branch: string
    prNumber: number
    prUrl: string
    error: string
    startedAt: string
    finishedAt: string
  }>
): Run | null {
  const d = getDb()
  const sets: string[] = []
  const values: unknown[] = []

  if (updates.status !== undefined) {
    sets.push("status = ?")
    values.push(updates.status)
  }
  if (updates.branch !== undefined) {
    sets.push("branch = ?")
    values.push(updates.branch)
  }
  if (updates.prNumber !== undefined) {
    sets.push("pr_number = ?")
    values.push(updates.prNumber)
  }
  if (updates.prUrl !== undefined) {
    sets.push("pr_url = ?")
    values.push(updates.prUrl)
  }
  if (updates.error !== undefined) {
    sets.push("error = ?")
    values.push(updates.error)
  }
  if (updates.startedAt !== undefined) {
    sets.push("started_at = ?")
    values.push(updates.startedAt)
  }
  if (updates.finishedAt !== undefined) {
    sets.push("finished_at = ?")
    values.push(updates.finishedAt)
  }

  if (sets.length === 0) return getRun(id)

  values.push(id)
  d.prepare(`UPDATE runs SET ${sets.join(", ")} WHERE id = ?`).run(...values)
  return getRun(id)
}

export function appendLog(id: string, line: string): void {
  const d = getDb()
  d.prepare(
    `UPDATE runs SET log = COALESCE(log, '') || ? WHERE id = ?`
  ).run(line + "\n", id)
}

export function getStats(): RunStats {
  const d = getDb()
  const total = (
    d.prepare("SELECT COUNT(*) as count FROM runs").get() as { count: number }
  ).count
  const running = (
    d
      .prepare("SELECT COUNT(*) as count FROM runs WHERE status = 'running'")
      .get() as { count: number }
  ).count
  const succeeded = (
    d
      .prepare("SELECT COUNT(*) as count FROM runs WHERE status = 'success'")
      .get() as { count: number }
  ).count
  const failed = (
    d
      .prepare("SELECT COUNT(*) as count FROM runs WHERE status = 'failed'")
      .get() as { count: number }
  ).count
  return { total, running, succeeded, failed }
}

export function getRecentRepos(): string[] {
  const d = getDb()
  const rows = d
    .prepare(
      "SELECT DISTINCT repo FROM runs ORDER BY created_at DESC LIMIT 10"
    )
    .all() as { repo: string }[]
  return rows.map((r) => r.repo)
}
