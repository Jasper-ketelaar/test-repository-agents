import { fetchRuns } from "@/actions/get-runs"
import { StatCards } from "@/components/stat-cards"
import { RunTable } from "@/components/run-table"

export const dynamic = "force-dynamic"

export default async function DashboardPage() {
  const { runs, stats } = await fetchRuns()

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Runs</h1>
      <StatCards stats={stats} />
      <RunTable runs={runs} />
    </div>
  )
}
