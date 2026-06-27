---
name: digest
description: Roll up a period of iroha memory (this week / month / an explicit date range) into one digest — the decisions made, the sessions and what they shipped, aggregate metrics, and what is still open — so a team gets a scannable "what happened lately" without opening every session. Produces a visual Digest page in Notion and reports its URL. Triggers on "/iroha:digest", "summarize the last week / month". Not for saving one session (use /iroha:save-session) or looking up a single past decision (use /iroha:recall).
argument-hint: "[week|month|YYYY-MM-DD..YYYY-MM-DD]"
---

# iroha: digest

Synthesize a **period rollup** across many sessions so the team can see "what did we
decide and ship lately?" in one page instead of opening every Session. iroha is a
*growing* memory; digest is how that growth becomes legible. Notion is the single source
of truth; everything here is read via `notion-search` (free plan) and written via the
Notion MCP. Write Notion content in the **user's conversation language**.

## 1. Preconditions

```bash
L="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh"
bash "$L" get session_ds_id      # empty -> tell the user to run /iroha:init, then stop
bash "$L" get decisions_ds_id
bash "$L" get container_page_id
bash "$L" get digests_folder_id  # the Digests grouping page (fall back to container if empty)
```

## 2. Resolve the period

Parse `$ARGUMENTS` and compute an inclusive `[START, END]` date window (ISO `YYYY-MM-DD`):

```bash
case "${ARGS:-week}" in
  week|"")  START=$(date -v-7d +%F 2>/dev/null || date -d '7 days ago' +%F);  END=$(date +%F) ;;
  month)    START=$(date -v-30d +%F 2>/dev/null || date -d '30 days ago' +%F); END=$(date +%F) ;;
  *..*)     START="${ARGS%%..*}"; END="${ARGS##*..}" ;;            # explicit YYYY-MM-DD..YYYY-MM-DD
  *)        START="$ARGS"; END=$(date +%F) ;;                       # single date -> through today
esac
echo "$START -> $END"
```

(`date -v` is BSD/macOS, `date -d` is GNU — the fallback covers both.)

## 3. Gather the period's memory — complete & current via the local index, content via Notion

The committed local index (`.iroha/index.ndjson`) is the **complete** enumeration of saved
sessions and decisions — the completeness layer `notion-search` lacks on the free plan (search
returns only a semantic top-N and lags writes by minutes, and `query-data-sources` is paid).
Enumerate the window from the index so the digest's counts and lists are exhaustive and include
work saved moments ago, then `notion-fetch` each id for its body.

```bash
IDX="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/index.sh"
# Complete window enumeration, newest first (ISO YYYY-MM-DD dates compare lexicographically).
bash "$IDX" list "$PWD" session \
  | jq -s -c --arg s "$START" --arg e "$END" \
      'map(select(.date>=$s and .date<=$e)) | sort_by(.date) | reverse | .[]'
bash "$IDX" list "$PWD" decision \
  | jq -s -c --arg s "$START" --arg e "$END" \
      'map(select(.date>=$s and .date<=$e and .status=="Active")) | sort_by(.date) | reverse | .[]'
```

- **Sessions** — the index lines give the complete `id` / `title` / `date` / `status`. For each,
  `notion-fetch` to read its `Summary`, `Type`, `Status`, the `## Metrics` line, and the
  decisions it made. If the window is large you may cap the *fetches* (newest ~15) — but the
  **session count** comes from the full index enumeration above, so the totals stay honest. If
  you cap, say so in the digest (never silently drop).
- **Decisions** — the enumeration above already keeps only `Status = Active` (mention a
  superseded one only if it was superseded *within* the period). `notion-fetch` each for Why/Date.
- **Still-open** — `notion-fetch` the project `State` page (`bash "$L" get-state "$PWD"`)
  and read its **Unfinished / Next** list.
- **Empty/stale index fallback** — a workspace created before the index existed lists nothing.
  Then fall back to `notion-search` over `session_ds_id` / `decisions_ds_id` with
  `filters.created_date_range = {start_date: START, end_date: END}` (`page_size` ~25) and **note
  in the digest that the rollup may be incomplete** (search returns only a top-N).

## 4. Compose the digest content (monochrome Notion-flavored Markdown, no emoji)

Sections, in this order:
1. a header `<callout color="blue_bg">`: the window + a one-line rollup
   (`N sessions, M decisions; themes: …`).
2. `## Metrics` — a `<callout color="gray_bg">` aggregate dashboard: total sessions,
   total decisions, files touched (sum of each session's `Files`), and a **by-Type**
   tally (`Implementation ×3 · Fix ×2 · Research ×1`). The **total sessions / total decisions**
   are the **count of the index enumeration** in step 3 (complete). Files touched and the
   by-Type tally are summed from the `## Metrics` line of each **fetched** session — do not
   invent numbers; if you capped the fetches, label them "across the N fetched of M sessions"
   so a partial aggregate is never shown as complete.
3. `## Decisions made` — a `<table header-row="true">` (`<tr color="blue_bg">` header):
   Decision / Why / Date. One row per Active decision in the window. Wrap code in backticks.
4. `## Sessions` — newest first, one bullet each:
   `- [YYYY-MM-DD — title](url) — Status · <one-line summary>`.
5. `## Still open` — an `orange_bg` callout with the State's carried-over `- [ ]` items.
6. `## Timeline` — a **one-line caption first** ("How the period progressed:" or similar, so
   the diagram is never a context-free "what is this?"), then a ```mermaid``` diagram (a simple
   top-down or left-right timeline of the sessions in the window, labeled by date + short topic)
   so the arc of the period is visual.

Wrap every file / command / path in backticks, and run the composed content through
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/link-lint.sh"` before publishing (it flags bare
file/path tokens Notion would auto-linkify to `http://…`; backtick them until it exits 0).
Indent callout / table / toggle children
with **tabs**.

## 5. Write the Digest page

`notion-create-pages` under the **`Digests` folder** (`digests_folder_id` from step 1; fall
back to `container_page_id` only if a pre-folder workspace returns empty):
- `properties`: `{ "title": "Digest START..END" }`
- `icon`: `https://www.notion.so/icons/calendar_gray.svg`
- `content`: the markdown from step 4.

Digests are disposable rollups, not a source of truth — they link back to the canonical
Sessions / Decisions. Do not create a database for them; a page under the `Digests` folder is
enough (grouping them there keeps the container root from filling with one flat digest page per
run). If a digest for the exact same window already exists, `notion-update-page`
`replace_content` it instead of making a duplicate.

## 6. Report

Give the Digest page URL, the counts (sessions / decisions in the window), and the top
2-3 themes. Note that `/iroha:recall <topic>` can drill into any session or decision the
digest references.

## Notes

- Read-only over the canonical DBs except for the one Digest page it writes.
- If the window has zero sessions, say so plainly and suggest a wider range — do not
  fabricate a digest.
