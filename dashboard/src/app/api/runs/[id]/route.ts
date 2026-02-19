import { NextRequest, NextResponse } from "next/server"
import { getRun, updateRun, appendLog } from "@/lib/db"
import { broadcast } from "@/lib/ws"

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params
  const run = getRun(id)

  if (!run) {
    return NextResponse.json({ error: "Run not found" }, { status: 404 })
  }

  const body = await request.json()

  if (body.log) {
    appendLog(id, body.log)
    broadcast(id, { type: "log", line: body.log })
  }

  const updates: Record<string, unknown> = {}
  if (body.status) updates.status = body.status
  if (body.branch) updates.branch = body.branch
  if (body.prNumber) updates.prNumber = body.prNumber
  if (body.prUrl) updates.prUrl = body.prUrl
  if (body.error) updates.error = body.error
  if (body.startedAt) updates.startedAt = body.startedAt
  if (body.finishedAt) updates.finishedAt = body.finishedAt

  if (Object.keys(updates).length > 0) {
    updateRun(id, updates as Parameters<typeof updateRun>[1])
    if (body.status) {
      broadcast(id, { type: "status", status: body.status, ...updates })
    }
  }

  const updated = getRun(id)
  return NextResponse.json(updated)
}

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params
  const run = getRun(id)

  if (!run) {
    return NextResponse.json({ error: "Run not found" }, { status: 404 })
  }

  return NextResponse.json(run)
}
