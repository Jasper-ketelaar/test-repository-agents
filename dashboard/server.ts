import { createServer } from "http"
import next from "next"
import { initWebSocketServer } from "./src/lib/ws"

const dev = process.env.NODE_ENV !== "production"
const port = parseInt(process.env.PORT || "3888", 10)

const app = next({ dev })
const handle = app.getRequestHandler()

app.prepare().then(() => {
  const server = createServer((req, res) => {
    handle(req, res)
  })

  initWebSocketServer(server)

  server.listen(port, () => {
    console.log(`> Dashboard ready on http://localhost:${port}`)
  })
})
