---
name: save-session
description: Save the current Claude Code session to Notion as structured, visual, queryable memory — decisions (with rationale and rejected alternatives), dev rules, work-state (done / unfinished), changed files, key commands, and chat-style highlights of the key exchanges. Use at the end of a working session, or when the user says "save this session" / "セッションを保存" / "まとめて保存". Requires a connected Notion MCP and a prior /iroha:init.
argument-hint: "[Complete|WIP|Interrupted]"
---

# iroha: save-session

Persist this session to Notion so humans and future Claude sessions can recall what
was decided, what is unfinished, and why. You produce the intelligence (summary,
decisions, rules, classification, chat highlights); `scripts/extract.sh` produces the
deterministic parts (files, commands, metadata). All Notion writes go through the
connected Notion MCP. Write Notion content in the **user's conversation language**.

## 1. Preconditions

Confirm Notion MCP is connected, then load the cached ids:

```bash
L="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh"
bash "$L" get session_ds_id    # empty -> tell the user to run /iroha:init, then stop
bash "$L" get decisions_ds_id
bash "$L" get container_page_id
[ -e "$(bash "$L" saved-dir)/${CLAUDE_SESSION_ID}" ] && echo "ALREADY_SAVED"
```

**Re-save guard (idempotency).** If the last line prints `ALREADY_SAVED`, this session
was already saved. Do **not** create duplicate Session / Decision rows — tell the user
it is already saved and offer to *update* the existing rows instead; stop unless they
confirm. (Duplicate decisions are the one defect that rots the "living memory".)

## 2. Locate this session's transcript

```bash
TX=$(ls -t "$HOME/.claude/projects/"*"/${CLAUDE_SESSION_ID}.jsonl" 2>/dev/null | head -1)
echo "$TX"
```

## 3. Deterministic extraction

```bash
E="${CLAUDE_PLUGIN_ROOT}/scripts/extract.sh"
bash "$E" meta     "$TX"   # JSON: title, started, ended, cwd, gitBranch, model
bash "$E" files    "$TX"
bash "$E" commands "$TX"
git config user.name 2>/dev/null || echo "unknown"   # Author
```

(The full transcript is large and is **not** stored; you compose curated chat
highlights from memory — see step 7.)

## 4. Compose the content (from your memory of the session + the extracted data)

- **Summary** — 1-3 sentences (the `Summary` property + search snippet).
- **Decisions** — each: the decision, *why*, and *rejected alternatives*. A decision
  to NOT do something counts.
- **Rules changed** — only rules/conventions **newly established or changed this
  session** (CLAUDE.md / memory promotion candidates). Do **not** re-list unchanged
  project rules — those live in CLAUDE.md / the Decisions DB, not in every session.
- **Done** / **Unfinished / Next** — work-state, for the Project State carry-over.
- **Failures** — error -> root cause -> fix.
- **Highlights** — 5-8 pivotal You<->Claude exchanges, paraphrased, to render
  chat-style (NOT the full transcript).
- **Type** — any of 調査 / 要件定義 / 設計 / 実装 / 修正 / リファクタ / レビュー
  (infer from the transcript).
- **Status** — `$ARGUMENTS` if given, else infer Complete / WIP / Interrupted.

## 5. Create the Session row

`notion-create-pages` with `parent: {"type":"data_source_id","data_source_id":"<session_ds_id>"}`.
Property map uses SQLite values:
- `Name` (title) — **`YYYY-MM-DD — <topic>`** (start date + a ≤20-char noun-phrase
  topic; no project prefix, no Type — those are properties). Calendar / Board cards show
  only the Name, so the date prefix keeps them time-scannable. Good:
  `2026-06-24 — Notion 連携の設計と Phase 1 実装`. Bad: `iroha: 設計・実装` (no date) /
  `[設計/実装] …` (Type duplicated).
- `Project`, `Status`, `Branch`, `Author`, `Summary` — plain strings.
- `Type` — a JSON array **string**, e.g. `"[\"設計\", \"実装\"]"`.
- Date — expanded keys: `"date:Date:start"` = started ISO, `"date:Date:is_datetime"` = 1.

**`content` = Notion-flavored Markdown, visual and monochrome (no emoji icons).**
Render **all headings and labels in the user's conversation language, defaulting to
English** when unsure. Read the spec once via `notion://docs/enhanced-markdown-spec`.
Emit **exactly these sections, in this order, on every save** — the structure must be
identical each time. The **only** optional sections are **Architecture**, **Rules
changed**, and **Failures** (include them only when they apply); never add, drop,
rename, or reorder anything else (English canonical names shown — translate them to the
user's language). Do **not** add an Overview / meta table — the page properties already
show Project / Status / Type / Date / Branch / Author at the top:
1. a header `<callout color="blue_bg">` with the one-line summary;
2. `## Architecture` *(optional — only when the work has structure)* with a ```mermaid``` diagram;
3. `## Decisions` as a `<table header-row="true">` with a `<tr color="blue_bg">` header
   (columns: Decision / Why / Rejected alternatives);
4. `## Progress` as a green_bg callout (Done) + an orange_bg callout (Unfinished, `- [ ]`);
5. `## Highlights` — 5-8 pivotal exchanges as alternating chat-style callouts
   (You = `blue_bg`, Claude = `gray_bg`), paraphrased and concise — **not** the full
   chat (see step 7);
6. `## Rules changed` *(optional — only when this session established or changed a rule)*
   as a `<callout color="gray_bg">`; omit the whole section when no rule changed;
7. `## Failures` *(optional — only when there were notable pitfalls)* as a
   `<details><summary>…</summary>` toggle (pitfall -> fix);
8. `## Details` with `<details><summary>…</summary>` toggles for **Changed files** and
   **Commands** — render these as **bulleted lists**: the `extract.sh files` and
   `commands` outputs are already `- ` lists, so use them verbatim (never join entries
   with `·` or other separators).
Wrap every file name / command / path in backticks — **including inside callouts and
tables** — so Notion does not auto-linkify `.sh` / `.md` names as `http://…` URLs.
Indent callout / toggle / table children with **tabs**. Keep the returned page URL.

Set a clean monochrome page icon:
`icon: "https://www.notion.so/icons/notebook_gray.svg"`.

## 6. Create the Decision rows

For each decision, `notion-create-pages` under `decisions_ds_id`. `Name` = a short
**`<topic>: <choice>`** title (≤24 chars, no parenthetical) — e.g. `Notion 連携: MCP 一本`,
`連結: relation でなく URL`. Keep the *why* in `Rationale` and the rejected options in
`Alternatives`, never in the Name. Also set `Project`, `Status` = `Active`, `Tags` (JSON
array string from architecture / dependency / process), `Session` = the Session page URL
from step 5, `"date:Date:start"`.

**Dedup & supersede.** Before inserting, check the local decision log (and
`notion-search`) for the same topic. If it already exists unchanged, do **not** insert
a duplicate — only record decisions actually made this session. If this session
**reverses or changes** a prior decision, set the old row's `Status` = `Superseded`
with `notion-update-page` (do **not** overwrite it — the change of mind is itself
memory worth recalling) and create the new decision alongside it.

Also append each decision to the **local decision log** so `/iroha:recall`
can search it for free (offline; the Notion MCP query tools need a paid plan):

```bash
DEC="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh" decisions-md-path "$PWD")"
mkdir -p "$(dirname "$DEC")"
printf '## %s\n- Date: %s\n- Why: %s\n- Rejected: %s\n- Session: %s\n\n' \
  "<decision>" "<date>" "<rationale>" "<alternatives>" "<session-url>" >>"$DEC"
```

## 7. Chat highlights — curated, not the full transcript

The full chat is **not** stored: it is too large to append through the MCP in one
session (the content would pass through the model's context twice). Instead, from
**your memory of this session**, pick the **5-8 pivotal You<->Claude exchanges** that
show how the key decisions were reached, and render them as the `## Highlights`
section (step 5): alternating chat-style callouts, You = `blue_bg`, Claude =
`gray_bg`, paraphrased and concise so it reads like a short chat. Do **not** dump the
whole transcript, and do **not** flatten the highlights into prose.

## 8. Update the Project State page (continuity core)

```bash
PROJ="$PWD"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh" get-state "$PROJ"
```

State is the SessionStart hook's stable, human-readable anchor — keep it **slim** and
**do not** re-transcribe decisions or rules (those live in the Decisions DB / CLAUDE.md;
re-listing them here only duplicates the latest Session row). State body (monochrome):
latest summary + date, a **Recent sessions** list (newest first, links to the last few
Session pages), the carried-over **Unfinished / Next** list, and a link to the Decisions
DB.
- If get-state is empty: `notion-create-pages` under `container_page_id`
  (title `State — <project>`, icon `https://www.notion.so/icons/target_gray.svg`),
  then `bash …/config.sh set-state "$PROJ" "<page_id>"`.
- Else: `notion-update-page` `replace_content` on that page id.
- **Also mirror the State body into the repo** so a teammate's SessionStart hook can
  inject it offline (it lives at `<repo>/.iroha/state.md`):
  `MD="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh" state-md-path "$PWD")"; mkdir -p "$(dirname "$MD")"; printf '%s' "<state body>" > "$MD"`.
  This file and the decision log (step 6) both live under `.iroha/` in the repo —
  **remind the user to commit `.iroha/`** so the memory reaches teammates (Notion stays
  the rich source of truth; the repo mirror is what the offline hook + grep read).

## 9. Mark saved + report

```bash
SAVED="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh" saved-dir)"
mkdir -p "$SAVED" && : > "$SAVED/${CLAUDE_SESSION_ID}"
```

Report the Session page URL, how many decisions were recorded, and that the Project
State was updated.

## Notes

- Do not write secrets to Notion; if the transcript surfaced any, omit them.
- Highlights come from your memory of the session, not a transcript dump; the full
  chat is intentionally not stored (too large to append per session).
