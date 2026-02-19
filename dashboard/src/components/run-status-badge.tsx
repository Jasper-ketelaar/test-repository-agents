import { Badge } from "@/components/ui/badge"
import { cn } from "@/lib/cn"
import type { RunStatus } from "@/types"

const statusConfig: Record<RunStatus, { label: string; className: string }> = {
  queued: {
    label: "Queued",
    className: "bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-300",
  },
  running: {
    label: "Running",
    className: "bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300",
  },
  success: {
    label: "Success",
    className: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900 dark:text-emerald-300",
  },
  failed: {
    label: "Failed",
    className: "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300",
  },
}

export function RunStatusBadge({ status }: { status: RunStatus }) {
  const config = statusConfig[status]
  return (
    <Badge variant="outline" className={cn("border-0", config.className)}>
      {status === "running" && (
        <span className="mr-1.5 h-2 w-2 rounded-full bg-amber-500 animate-pulse" />
      )}
      {config.label}
    </Badge>
  )
}
