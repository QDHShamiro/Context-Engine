---
description: Show how much has already been compressed (rate + tokens)
---

Call the `get_savings` tool of the `context-engine` MCP server (no arguments — it targets the most recent session of this project).

Present it compactly and **bold the compression rate**: compressed-from → compressed-to tokens, tokens saved with the percentage, number of compressions, and the current uncompressed backlog. If nothing has been compressed yet, say so plainly and report the backlog size (how close it is to triggering).
