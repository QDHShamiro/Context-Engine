---
description: Force a Context Engine compression of the current session now
---

Call the `force_compress` tool of the `context-engine` MCP server (no arguments — it targets the most recent session of this project).

Report the outcome: message range compressed, estimated tokens saved, model used. If it was skipped (backlog too small, no API key, already running), state the reason.
