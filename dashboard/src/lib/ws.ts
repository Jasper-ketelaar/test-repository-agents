import { WebSocketServer, WebSocket } from "ws"
import type { IncomingMessage } from "http"
import type { Server } from "http"

const clients = new Map<string, Set<WebSocket>>()

let wss: WebSocketServer | null = null

export function initWebSocketServer(server: Server) {
  wss = new WebSocketServer({ server, path: "/ws" })

  wss.on("connection", (ws: WebSocket, req: IncomingMessage) => {
    const url = new URL(req.url || "/", `http://${req.headers.host}`)
    const runId = url.searchParams.get("runId")

    if (!runId) {
      ws.close(1008, "Missing runId parameter")
      return
    }

    if (!clients.has(runId)) {
      clients.set(runId, new Set())
    }
    clients.get(runId)!.add(ws)

    ws.on("close", () => {
      const set = clients.get(runId)
      if (set) {
        set.delete(ws)
        if (set.size === 0) clients.delete(runId)
      }
    })
  })
}

export function broadcast(runId: string, data: Record<string, unknown>) {
  const set = clients.get(runId)
  if (!set) return

  const message = JSON.stringify(data)
  set.forEach((ws) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(message)
    }
  })
}
