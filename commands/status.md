---
description: Show Context Engine status (tokens, backlog, compressions, daemon)
---

Call the `get_status` tool of the `context-engine` MCP server.

Present the result compactly: for each active session show context tokens, uncompressed backlog (tokens + messages), last compression (when, tokens saved), total tokens saved, and whether the daemon is running. Mention the configured thresholds. If the daemon is not running or the last compression errored, point it out clearly.
