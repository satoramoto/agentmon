# Changelog

## Unreleased

## 0.1.0

First release.

- `agentmon`: a live dashboard of AI coding agent sessions (Claude, Codex and their desktop apps) on macOS, opening on the dense layout; `--layout classic` and `--layout visual` for the others. Enter drills into a session, Escape comes back.
- Per session and per process: CPU, real memory (footprint), resident size, disk read/write rates, network in/out and connections (from `nettop`), memory growth and page-ins.
- Memory: Activity Monitor's breakdown, memory pressure and the sessions driving it.
- Processes: scopes (Agents, All, Busy, Heavy, Writing, Waiting), grouping, search, a detail drawer, and terminate/kill with confirmation.
- Commands: `top`, `sessions`, `tree`, `memory`, `footprint`, `record`, `report`, plus `completion` and `--version`. Off a terminal every view prints plain text.
- History of sessions and memory as JSON lines under `~/.local/state/agentmon`, summarised by `agentmon report`.
