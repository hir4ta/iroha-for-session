---
name: recall
description: Search this project's iroha memory — past decisions ("did we decide against X? why?") and similar past work ("have we built something like this before?"). Uses Notion semantic search (works on the free plan) over the Sessions and Decisions databases. Triggers on "/iroha:recall", and naturally when the user asks "過去に〜決めた?", "なぜ〜にした?", "似た実装ある?", "did we / why / have we done this before".
argument-hint: "<query>"
---

# iroha: recall

Pull relevant memory from iroha so you reuse past decisions and prior work instead of
re-deciding or re-building from scratch — the core of a living, **growing team
memory**. Notion is the **single source of truth**, and `notion-search` works on the
**free** plan (`workspace_search`), so recall reads canonical, always-current team data
directly — there is no local copy to drift.

## 1. Load the data source ids

```bash
L="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh"
bash "$L" get decisions_ds_id
bash "$L" get session_ds_id
```

## 2. Search Notion

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
  list the **files it changed** and the decisions it set — "we've done this before;
  here's the reference and what to reuse." This is what makes iroha pay off more the
  more the team uses it.
- De-duplicate near-identical hits; report the current decision, not superseded copies.
- **Stale Session summaries.** A Session's `Summary` is a snapshot from its date and may
  describe a since-changed state (an old session may say "2 DB" when the project now has
  3). Sessions are immutable history (no supersede), so treat the **newest Session, the
  State page, and `Active` Decisions** as current — never echo a stale Session summary as
  today's fact.

## Notes

- Recall needs the Notion MCP (online). There is **no offline mirror** — Notion is the
  one source of truth, which keeps recall always current (no local copy to go stale).
  The SessionStart hook separately injects the project's State from the repo
  `.iroha/state.md` mirror; recall itself goes straight to Notion.
