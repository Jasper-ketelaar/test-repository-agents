"use client"

import Link from "next/link"
import { RunStatusBadge } from "./run-status-badge"
import { Badge } from "@/components/ui/badge"
import { formatDuration, formatTime } from "@/lib/format"
import type { Run } from "@/types"

export function RunTable({ runs }: { runs: Run[] }) {
  if (runs.length === 0) {
    return (
      <div className="rounded-lg border border-border bg-card p-12 text-center text-muted-foreground">
        No runs yet. Start one from the <Link href="/new" className="text-primary hover:underline">New Run</Link> page.
      </div>
    )
  }

  return (
    <div className="rounded-lg border border-border bg-card overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-border bg-muted/50">
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">Status</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">Issue</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">Repo</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">Type</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">Duration</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">PR</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">Started</th>
          </tr>
        </thead>
        <tbody>
          {runs.map((run) => (
            <tr key={run.id} className="border-b border-border last:border-0 hover:bg-muted/30 transition-colors">
              <td className="px-4 py-3">
                <RunStatusBadge status={run.status} />
              </td>
              <td className="px-4 py-3">
                <Link
                  href={`/runs/${run.id}`}
                  className="font-medium text-foreground hover:text-primary transition-colors"
                >
                  #{run.issueNumber}
                  <span className="ml-2 text-muted-foreground font-normal">
                    {run.issueTitle}
                  </span>
                </Link>
              </td>
              <td className="px-4 py-3 text-muted-foreground">
                {run.repo.split("/").pop()}
              </td>
              <td className="px-4 py-3">
                <Badge variant="secondary" className="text-xs">
                  {run.taskType}
                </Badge>
              </td>
              <td className="px-4 py-3 text-muted-foreground tabular-nums">
                {formatDuration(run.startedAt, run.finishedAt)}
              </td>
              <td className="px-4 py-3">
                {run.prUrl ? (
                  <a
                    href={run.prUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-primary hover:underline"
                  >
                    #{run.prNumber}
                  </a>
                ) : (
                  <span className="text-muted-foreground">—</span>
                )}
              </td>
              <td className="px-4 py-3 text-muted-foreground tabular-nums">
                {formatTime(run.createdAt)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
