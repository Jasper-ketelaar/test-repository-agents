"use client"

import { useState, useEffect } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Label } from "@/components/ui/label"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { startRun } from "@/actions/create-run"
import { fetchRecentRepos } from "@/actions/get-runs"
import { Loader2 } from "lucide-react"

export function NewRunForm() {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [recentRepos, setRecentRepos] = useState<string[]>([])

  const [repo, setRepo] = useState("")
  const [issueNumber, setIssueNumber] = useState("")
  const [baseBranch, setBaseBranch] = useState("main")
  const [extraPrompt, setExtraPrompt] = useState("")
  const [prLabels, setPrLabels] = useState("codex-generated")
  const [timeoutMinutes, setTimeoutMinutes] = useState("30")

  useEffect(() => {
    fetchRecentRepos().then(setRecentRepos)
  }, [])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setLoading(true)

    try {
      const run = await startRun({
        repo,
        issueNumber: parseInt(issueNumber, 10),
        baseBranch,
        extraPrompt,
        prLabels,
        timeoutMinutes: parseInt(timeoutMinutes, 10),
      })
      router.push(`/runs/${run.id}`)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to start run")
      setLoading(false)
    }
  }

  return (
    <Card className="max-w-2xl">
      <CardHeader>
        <CardTitle>Start a new Codex run</CardTitle>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit} className="space-y-5">
          <div className="space-y-2">
            <Label htmlFor="repo">Repository</Label>
            <Input
              id="repo"
              placeholder="owner/repo"
              value={repo}
              onChange={(e) => setRepo(e.target.value)}
              required
              list="recent-repos"
            />
            {recentRepos.length > 0 && (
              <datalist id="recent-repos">
                {recentRepos.map((r) => (
                  <option key={r} value={r} />
                ))}
              </datalist>
            )}
          </div>

          <div className="space-y-2">
            <Label htmlFor="issue">Issue number</Label>
            <Input
              id="issue"
              type="number"
              min={1}
              placeholder="42"
              value={issueNumber}
              onChange={(e) => setIssueNumber(e.target.value)}
              required
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="branch">Base branch</Label>
            <Input
              id="branch"
              placeholder="main"
              value={baseBranch}
              onChange={(e) => setBaseBranch(e.target.value)}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="extra">Extra prompt (optional)</Label>
            <Textarea
              id="extra"
              placeholder="Additional instructions for Codex..."
              value={extraPrompt}
              onChange={(e) => setExtraPrompt(e.target.value)}
              rows={3}
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="labels">PR labels</Label>
              <Input
                id="labels"
                placeholder="codex-generated"
                value={prLabels}
                onChange={(e) => setPrLabels(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="timeout">Timeout (minutes)</Label>
              <Input
                id="timeout"
                type="number"
                min={1}
                max={120}
                value={timeoutMinutes}
                onChange={(e) => setTimeoutMinutes(e.target.value)}
              />
            </div>
          </div>

          {error && (
            <p className="text-sm text-destructive">{error}</p>
          )}

          <Button type="submit" disabled={loading} className="w-full">
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            {loading ? "Starting run..." : "Start run"}
          </Button>
        </form>
      </CardContent>
    </Card>
  )
}
