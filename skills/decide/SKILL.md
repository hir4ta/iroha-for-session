---
name: decide
description: Record ONE architecture / dependency / process decision to iroha's Decisions DB the moment you make it — its rationale and the rejected alternatives — without waiting for a full /iroha:save-session. This is the lightweight capture path that keeps the decision ledger (iroha's core, team-shared value) growing continuously instead of only at end-of-session. Triggers on "/iroha:decide", and naturally when the user says "record this decision", "log that we decided X", "save this to the decision log", or right after a load-bearing choice is settled.
argument-hint: "<topic>: <choice>"
---

# iroha: decide

Capture a **single** decision into the shared Decisions DB right now, cheaply. The full
`/iroha:save-session` is the end-of-session record (chat, metrics, highlights); this is the
**decision-moment** record — one row, one round-trip — so the ledger (rationale + rejected
alternatives + supersede lineage, iroha's unique value over per-machine memory) grows while the
reasoning is fresh, not weeks later when it is forgotten or never saved. Write Notion content in
the user's conversation language.

**What earns a row (same bar as save-session §6).** Only **architecture / dependency / process**
choices that shape the project. A decision to NOT do something counts. Keep display / naming /
wording tweaks OUT — they belong in a Session's Decisions table, not the canonical DB, so recall's
signal-to-noise stays high. If the user asks to record a non-structural tweak, say so and decline.

## 1. Preconditions

```bash
L="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.ts"
bun "$L" get decisions_ds_id      # empty -> tell the user to run /iroha:init, then stop
bun "$L" get container_page_id
```

**Probe Notion auth before writing.** A connected MCP can still be unauthenticated. Make one cheap
read first: `notion-fetch <container_page_id>`. On an auth/permission error, tell the user to
complete the OAuth (`/mcp` → `notion`, or `claude mcp login notion`) and **stop**.

## 2. Compose the decision

From `$ARGUMENTS` and the conversation:
- **`<topic>: <choice>`** — the headline (the `Name`, ≤24 chars, no parenthetical), e.g.
  `Recall: corpus-size gate`, `Notion: MCP only`. If `$ARGUMENTS` already has this shape, use it;
  otherwise draft it from the decision under discussion.
- **Rationale** — *why*, in 1-3 sentences.
- **Alternatives** — the option(s) rejected and why (this is what makes the ledger worth more than
  a commit message). A decision with no real alternative considered is usually too small for a row.
- **Tags** — one or more of `architecture` / `dependency` / `process`.

**Confirm with the user before writing** (this mutates shared memory): show the drafted
`Name` / Rationale / Alternatives and let them correct it. Report only what was actually decided —
do not inflate or invent a rationale the conversation does not support.

## 3. Ensure the `Topic` and `Project` SELECT options exist

`Topic` and `Project` are **SELECT** properties; `notion-create-pages` does **not** auto-create a
missing option (an unseeded value 400s with `Value must be one of: …`). Reuse existing options
rather than coining near-synonyms (keep topic families consolidated).

```bash
ROOT="$PWD"; IDX="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/index.ts"
bun "$IDX" find-topic "$ROOT" "<topic>"   # existing rows on this topic (and shows the topic spelling)
```

`notion-fetch` the Decisions data source to read the current `Topic` / `Project` option lists. If
this decision's `<topic>` (or the current project = `basename "$PWD"`) is missing, add it — `ALTER
… SET` **replaces** the whole list, so include every existing option **plus** the new one:

```
notion-update-data-source <decisions_ds_id>  statements: ALTER COLUMN "Topic" SET SELECT(<existing topics…>, '<topic>':color)
```

Adding a brand-new `Project` to the **shared** workspace: ask the user once to confirm (as
save-session §5.0 does), and add it to **both** the Sessions and Decisions data sources so they
stay in sync.

## 4. Dedup & supersede (use the local index — it is complete; free-plan search is not)

The topic prefix is the dedup key.

```bash
bun "$IDX" find-topic "$ROOT" "<topic>"                                   # exact-topic rows, any status
bun "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/search.ts" "$ROOT" "<topic + choice>" decision 5   # near-dup under a different topic
```

- An **Active** row with the same `<topic>` that is **unchanged** → do **not** insert a duplicate;
  tell the user it already exists and stop.
- This decision **reverses / changes** an existing one → set the old row's `Status` = `Superseded`
  via `notion-update-page` (never overwrite — the change of mind is itself memory), create the new
  row **with `Supersedes` = the old row's Notion URL** (`https://www.notion.so/<bare-old-id>` — the
  lineage edge `/iroha:history` walks), and give the new row a one-line body making the lineage
  human-readable: `content` = `Supersedes [<old topic>: <old choice>](<old-url>) — <one-line why>`
  (backtick any file/path token — Notion auto-linkifies a bare `foo.ts` to `http://…`). Run that
  body through `bun "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/link-lint.ts" <file>` before publishing.

## 5. Create the row

One `notion-create-pages` with `parent: {"type":"data_source_id","data_source_id":"<decisions_ds_id>"}`.
Properties (SQLite values):
- `Name` = `<topic>: <choice>`; `Status` = `Active`; `Topic` = the `<topic>` (plain string, option
  ensured in §3); `Project` = `basename "$PWD"` (plain string, SELECT option ensured in §3).
- `Rationale`, `Alternatives` = plain rich_text.
- `Tags` = a JSON array **string**, e.g. `"[\"architecture\"]"`.
- `"date:Date:start"` = today (`date +%F`).
- `Supersedes` = old row URL only when superseding (§4).
- Leave `Session` empty — this decision is not tied to a saved Session row (recall and history do
  not need it). Icon `https://www.notion.so/icons/bookmark_gray.svg`. Keep the returned page id/URL.

## 6. Update the local index (this is what makes it instantly recallable)

The 9th arg is the BM25 **search snippet** — the `Rationale` condensed to ≤160 chars, newlines
collapsed to spaces, ending on a word boundary (never mid-token, so the trailing CJK bigram stays
intact). The 10th arg is the id of the decision this one supersedes (empty for an original) — the
dashed page id or the bare 32-hex form both work, the index normalizes dashes before matching:

```bash
bun "$IDX" upsert "$ROOT" decision "<new_page_id>" "<topic>" Active "$(date +%F)" "<Name>" "$(basename "$PWD")" "<rationale snippet ≤160>" "<old_page_id-if-superseding-else-empty>"
# when superseding, also flip the old row in the index so it stays searchable as history:
bun "$IDX" upsert "$ROOT" decision "<old_page_id>" "<topic>" Superseded "<old_date>" "<old_Name>" "$(basename "$PWD")" "<old rationale snippet>"
```

The index holds **keys + a derived snippet only** — Notion stays the single source of truth; the
snippet is regenerated, so it cannot become a second truth. It exists so dedup/supersede/audit can
enumerate the complete set free-plan search cannot, and so the always-on local BM25 recall can match
a prompt against the decision's *reason*.

## 7. Report

Give the row URL and a one-line confirmation. Note that the decision is now in the proactive recall
index and the shared Decisions DB — the next session (yours or a teammate's) will surface it.

## Notes

- **This is the lightweight half of capture.** `/iroha:save-session` still records the full session
  (chat, metrics, highlights, State carry-over); `/iroha:decide` just lets the **ledger** grow
  continuously between saves instead of only at the end — so iroha's memory actually grows even when
  a full save never happens. When you settle a structural decision mid-session, offer to record it
  here rather than waiting.
- It deliberately does **not** touch the Project State page or create a Session row — it is one
  decision, one write. The full continuity record stays in `/iroha:save-session`.
