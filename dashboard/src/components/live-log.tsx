"use client"

import { useEffect, useRef, useState } from "react"
import type { RunStatus } from "@/types"

interface LiveLogProps {
  runId: string
  initialLog: string | null
  status: RunStatus
}

export function LiveLog({ runId, initialLog, status }: LiveLogProps) {
  const [lines, setLines] = useState<string[]>(
    initialLog ? initialLog.split("\n") : []
  )
  const [currentStatus, setCurrentStatus] = useState(status)
  const containerRef = useRef<HTMLDivElement>(null)
  const autoScroll = useRef(true)

  useEffect(() => {
    if (currentStatus !== "running" && currentStatus !== "queued") return

    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
    const ws = new WebSocket(`${protocol}//${window.location.host}/ws?runId=${runId}`)

    ws.onmessage = (event) => {
      const data = JSON.parse(event.data)
      if (data.type === "log") {
        setLines((prev) => [...prev, data.line])
      }
      if (data.type === "status") {
        setCurrentStatus(data.status)
      }
    }

    ws.onerror = () => ws.close()

    return () => ws.close()
  }, [runId, currentStatus])

  useEffect(() => {
    if (autoScroll.current && containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight
    }
  }, [lines])

  function handleScroll() {
    if (!containerRef.current) return
    const { scrollTop, scrollHeight, clientHeight } = containerRef.current
    autoScroll.current = scrollHeight - scrollTop - clientHeight < 50
  }

  return (
    <div
      ref={containerRef}
      onScroll={handleScroll}
      className="h-[600px] overflow-y-auto rounded-lg border border-border bg-slate-950 p-4 font-mono text-sm text-slate-200"
    >
      {lines.length === 0 && currentStatus === "queued" && (
        <span className="text-slate-500">Waiting for run to start...</span>
      )}
      {lines.map((line, i) => (
        <div key={i} className="whitespace-pre-wrap leading-relaxed">
          {line.startsWith("[ERROR]") || line.startsWith("ERROR:") ? (
            <span className="text-red-400">{line}</span>
          ) : line.startsWith("[WARN]") ? (
            <span className="text-amber-400">{line}</span>
          ) : line.startsWith("[stderr]") ? (
            <span className="text-orange-400">{line}</span>
          ) : (
            line
          )}
        </div>
      ))}
      {currentStatus === "running" && (
        <span className="inline-block h-4 w-2 animate-pulse bg-slate-400" />
      )}
    </div>
  )
}
