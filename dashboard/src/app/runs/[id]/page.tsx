import { notFound } from "next/navigation"
import Link from "next/link"
import { fetchRun } from "@/actions/get-run"
import { RunStatusBadge } from "@/components/run-status-badge"
import { LiveLog } from "@/components/live-log"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent } from "@/components/ui/card"
import { formatDuration } from "@/lib/format"
import { ArrowLeft, ExternalLink } from "lucide-react"

export const dynamic = "force-dynamic"

export default async function RunDetailPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const run = await fetchRun(id)

  if (!run) notFound()

  return (
    <div className="space-y-6">
      <Link
        href="/"
        className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
      >
        <ArrowLeft className="h-4 w-4" />
        Back to runs
      </Link>

      <div className="flex items-start justify-between">
        <div className="space-y-1">
          <h1 className="text-2xl font-bold">
            #{run.issueNumber} {run.issueTitle}
          </h1>
          <p className="text-muted-foreground">{run.repo}</p>
        </div>
        <RunStatusBadge status={run.status} />
      </div>

      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <Card>
          <CardContent className="p-4">
            <p className="text-sm text-muted-foreground">Task type</p>
            <Badge variant="secondary" className="mt-1">
              {run.taskType}
            </Badge>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <p className="text-sm text-muted-foreground">Duration</p>
            <p className="mt-1 font-semibold tabular-nums">
              {formatDuration(run.startedAt, run.finishedAt)}
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <p className="text-sm text-muted-foreground">Branch</p>
            <p className="mt-1 font-mono text-sm">
              {run.branch || "—"}
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <p className="text-sm text-muted-foreground">Pull request</p>
            {run.prUrl ? (
              <a
                href={run.prUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="mt-1 inline-flex items-center gap-1 text-primary hover:underline"
              >
                #{run.prNumber}
                <ExternalLink className="h-3 w-3" />
              </a>
            ) : (
              <p className="mt-1 text-muted-foreground">—</p>
            )}
          </CardContent>
        </Card>
      </div>

      {run.error && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 dark:border-red-900 dark:bg-red-950">
          <p className="text-sm font-medium text-red-800 dark:text-red-200">Error</p>
          <p className="mt-1 text-sm text-red-700 dark:text-red-300">{run.error}</p>
        </div>
      )}

      <div className="space-y-2">
        <h2 className="text-lg font-semibold">Output</h2>
        <LiveLog runId={run.id} initialLog={run.log} status={run.status} />
      </div>
    </div>
  )
}
