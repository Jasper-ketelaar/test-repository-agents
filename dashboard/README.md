# Factory Agents Dashboard

A Next.js dashboard for monitoring and managing Codex automated issue implementations.

## Features

- **Run history** — table of all runs with status, duration, PR links
- **Live output** — WebSocket-streamed Codex output in a terminal viewer
- **Manual trigger** — start a run from the dashboard with repo, issue number, and config
- **Stat cards** — at-a-glance totals, running, succeeded, failed
- **Dark mode** — matches the Silver-Key factory design system

## Prerequisites

- Node.js >= 20
- [Codex CLI](https://github.com/openai/codex) installed and authenticated (`codex login`)
- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated

## Getting Started

```bash
npm install
npm run dev
```

Opens on [http://localhost:3888](http://localhost:3888).

## Architecture

- **Next.js 15** App Router with server actions
- **SQLite** via `better-sqlite3` for run history (stored in `data/agents.db`)
- **WebSocket** on the same port for live log streaming
- **Custom server** (`server.ts`) — combines Next.js + WebSocket on port 3888

## Pages

| Route | Description |
|-------|-------------|
| `/` | Dashboard — stat cards + run history table |
| `/runs/[id]` | Run detail — metadata + live log viewer |
| `/new` | Manual trigger form |

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/runs/[id]` | `GET` | Get run details |
| `/api/runs/[id]` | `PATCH` | Update run status (used by GitHub Action) |
| `ws://localhost:3888/ws?runId=xxx` | WebSocket | Live log stream |
