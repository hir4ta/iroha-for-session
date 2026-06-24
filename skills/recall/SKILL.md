---
name: recall
description: Search this project's past decisions recorded by iroha — answers "did we decide against X before?", "why did we choose Y?". Works offline and free (greps the local decision mirror; no Notion access needed). Triggers on "/iroha:recall", and naturally when the user asks "過去に〜決めた?", "なぜ〜にした?", "did we decide / why did we".
argument-hint: "<query>"
---

# iroha: recall

Answer "have we decided this before / why" from iroha's local decision mirror —
free and offline. (The Notion MCP query/search tools require a paid Business plan +
Notion AI, so recall does not depend on them.)

## Steps

1. Search the local mirror with the user's query (`$ARGUMENTS`):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/recall.sh" "$PWD" "$ARGUMENTS"
   ```

2. Present the matching decision blocks to the user in their language — the
   decision, why, the rejected alternatives, and the Session link. If nothing
   matched, say so. On a paid Notion plan you may additionally search Notion
   directly via the Notion MCP (`notion-search` / `notion-query-data-sources`).
