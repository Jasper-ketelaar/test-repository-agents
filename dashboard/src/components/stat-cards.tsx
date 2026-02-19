import { Card, CardContent } from "@/components/ui/card"
import type { RunStats } from "@/types"

function StatCard({ label, value }: { label: string; value: number }) {
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-sm text-muted-foreground">{label}</p>
        <p className="text-2xl font-bold">{value}</p>
      </CardContent>
    </Card>
  )
}

export function StatCards({ stats }: { stats: RunStats }) {
  return (
    <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
      <StatCard label="Total runs" value={stats.total} />
      <StatCard label="Running" value={stats.running} />
      <StatCard label="Succeeded" value={stats.succeeded} />
      <StatCard label="Failed" value={stats.failed} />
    </div>
  )
}
