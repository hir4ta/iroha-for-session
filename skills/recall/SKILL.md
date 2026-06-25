---
name: recall
description: Search this project's iroha memory — past decisions ("did we decide against X? why?") and similar past work ("have we built something like this before?"). Uses Notion semantic search (works on the free plan) over the Sessions and Decisions databases, with a local offline grep fallback. Triggers on "/iroha:recall", and naturally when the user asks "過去に〜決めた?", "なぜ〜にした?", "似た実装ある?", "did we / why / have we done this before".
argument-hint: "<query>"
---

# iroha: recall

Pull relevant memory from iroha so you reuse past decisions and prior work instead of
re-deciding or re-building from scratch — the core of a living, **growing team
memory**. Notion is the shared source of truth, and `notion-search` works on the
**free** plan (`workspace_search` backend), so recall reads canonical team data — not
just whatever one machine happened to save.

## 1. Load the data source ids

```bash
L="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh"
bash "$L" get decisions_ds_id
bash "$L" get session_ds_id
```

## 2. Search Notion (primary)

Run `notion-search` once per database, passing the user's query (`$ARGUMENTS`) and
`data_source_url: "collection://<id>"`. Keep `page_size` ~5 and
`max_highlight_length` ~160.

- **Decisions** (`decisions_ds_id`) — for "did we decide X / why / what did we
  reject?". The `Rationale` appears in the highlight; `notion-fetch` the top hit for
  the full `Rationale` / `Alternatives`.
- **Sessions** (`session_ds_id`) — for "have we built something like this before?".
  `notion-fetch` a promising hit to read its summary, its `Decisions`, and the
  **Changed files** toggle, so you can point at the actual prior implementation.

## 3. Synthesize a reusable answer (in the user's language)

- **Decision query**: the decision, *why*, the rejected alternatives, the date, and
  the Session link. Treat a `Status = Superseded` hit as outdated — prefer the current
  decision and mention what replaced it.
- **"Similar past work"**: name the prior session ("we did <X> on <date>"), link it,
  list the **files it changed** and the decisions it set — i.e. "we've done this
  before; here's the reference and what to reuse." This is what makes iroha pay off
  more the more the team uses it.
- De-duplicate near-identical hits (same topic, different version); don't report the
  same decision twice.

## 4. Offline fallback

If Notion is unavailable (no MCP / offline), grep the local mirror instead:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/recall.sh" "$PWD" "$ARGUMENTS"
```

The local mirror only covers what was saved on the current machine (and, once it is
committed to the repo, whatever teammates have pulled); Notion search covers the
whole team's history.
