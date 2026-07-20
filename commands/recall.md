---
description: Load the compressed summary of earlier conversation into context
---

Call the `get_compressed_context` tool of the `context-engine` MCP server (no arguments — it returns the latest summary for this project).

If a summary exists, treat it as authoritative context about the earlier part of this work: briefly state the key points (task, decisions, open TODOs) and continue using it. Do not re-read files or re-derive decisions the summary already covers. If no summary exists, say so.
