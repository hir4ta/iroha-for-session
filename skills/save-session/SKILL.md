---
name: save-session
description: Save the current Claude Code session to Notion as structured, visual, queryable memory — decisions (with rationale and rejected alternatives), dev rules, work-state (done / unfinished), changed files, key commands, and chat-style highlights of the key exchanges. Use at the end of a working session, or when the user says "save this session". Requires a connected Notion MCP and a prior /iroha:init.
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
bash "$E" prompts  "$TX"   # the human's real messages — the You-side anchor (step 7)
bash "$E" stats    "$TX"   # JSON metrics: turns, toolCalls, filesEdited, bash, durationMin
bash "$E" tools    "$TX"   # per-tool tally for the Details / Tools toggle
bash "$E" chat     "$TX"   # cleaned full chat (per-turn capped) for the Full-chat toggle
git config user.name 2>/dev/null || echo "unknown"   # Author
```

(The full transcript is large and is **not** stored. The chat highlights (step 7) come
from your memory of the session, but the **You** side is anchored to the deterministic
`prompts` output above — never invented.)

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
- **Type** — any of Research / Requirements / Design / Implementation / Fix / Refactor / Review
  (infer from the transcript). These English names are the **canonical template**; write the
  value in the user's conversation language to match the options init seeded for this
  workspace (a Japanese workspace stores the Japanese equivalents).
- **Status** — `$ARGUMENTS` if given, else infer Complete / WIP / Interrupted.

**Honesty (applies to every field, not only Highlights).** Report what *actually*
happened — keep dead-ends, corrections, and abandoned approaches at the same weight as the
wins. Do **not** inflate success in the Summary, Progress, or Decisions; an over-rosy memory
misleads the next session as surely as a wrong one. Any metric you state (tests passed,
commits, files) must come from `extract.sh stats` or a real command's output — never
estimated or rounded up. If you are unsure something happened, leave it out rather than
assert it.

## 5. Create the Session row

`notion-create-pages` with `parent: {"type":"data_source_id","data_source_id":"<session_ds_id>"}`.
Property map uses SQLite values:
- `Name` (title) — **`YYYY-MM-DD — <topic>`** (start date + a ≤20-char noun-phrase
  topic; no project prefix, no Type — those are properties). Calendar / Board cards show
  only the Name, so the date prefix keeps them time-scannable. Good:
  `2026-06-24 — Notion integration design + Phase 1`. Bad: `iroha: design + impl` (no date) /
  `[Design/Impl] …` (Type duplicated).
- `Project`, `Status`, `Branch`, `Author`, `Summary` — plain strings.
- `Type` — a JSON array **string**, in the user's conversation language to match the seeded
  options (the English names above are canonical); English-workspace form looks like
  `"[\"Design\", \"Implementation\"]"`.
- Date — expanded keys: `"date:Date:start"` = started ISO, `"date:Date:is_datetime"` = `1`
  **as a JSON number, not the string `"1"`** (a string is rejected with a 400).

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
2. `## Metrics` — a `<callout color="gray_bg">` dashboard built **verbatim from
   `extract.sh stats`** (never hand-count). One line, ` · `-separated, e.g.
   `⏱ 79 min · 🗣 4↔38 turns · 🔧 72 tool calls · ✎ 5 files · ⌘ 12 bash` — but **no emoji**
   (house rule): use text labels instead — `Duration 79 min · Turns 4↔38 · Tool calls 72
   · Files 5 · Bash 12`. Always included; it makes each session scannable at a glance;
3. `## Architecture` *(optional — only when the work has structure)* with a ```mermaid``` diagram;
4. `## Decisions` as a `<table header-row="true">` with a `<tr color="blue_bg">` header
   (columns: Decision / Why / Rejected alternatives);
5. `## Progress` as a green_bg callout (Done) + an orange_bg callout (Unfinished, `- [ ]`);
6. `## Highlights` — 5-8 pivotal exchanges as alternating chat-style callouts
   (You = `blue_bg`, Claude = `gray_bg`), **wrapped in a `<details>` toggle so they are
   collapsed by default and expand on click** (the section is long — keep the page
   scannable). Give the `<summary>` a label in the user's language (English canonical e.g.
   `Highlights (N exchanges)`), and **tab-indent the callouts inside the toggle**. The
   **You** lines come from the `prompts` extract (real messages, never invented), Claude
   lines are paraphrased — **not** the full chat (see step 7);
7. `## Rules changed` *(optional — only when this session established or changed a rule)*
   as a `<callout color="gray_bg">`; omit the whole section when no rule changed;
8. `## Failures` *(optional — only when there were notable pitfalls)* as a
   `<details><summary>…</summary>` toggle. Write each as **symptom → root cause → fix**
   (Reflexion: a failure is first-class, recallable memory — phrase the symptom in the words
   a future search would use, so the next session surfaces it *before* repeating the
   dead-end);
9. `## Details` with `<details><summary>…</summary>` toggles, in this order:
   **Changed files** (`extract.sh files`), **Commands** (`extract.sh commands`),
   **Tools** (`extract.sh tools` — the per-tool tally). Render the `files` / `commands` /
   `tools` outputs as **bulleted lists** verbatim (they are already `- ` lists; never
   join entries with `·`). The full chat does **not** go inline — it is paged out to a
   **child page** (step 5b) and the **Full chat** toggle holds only a link to it.
Wrap every file name / command / path in backticks — **including inside callouts and
tables** — so Notion does not auto-linkify `.sh` / `.md` names as `http://…` URLs.
Indent callout / toggle / table children with **tabs**. Keep the returned page URL.

Set a clean monochrome page icon:
`icon: "https://www.notion.so/icons/notebook_gray.svg"`.

## 5b. Full chat as a child page (never fake it)

The cleaned full chat (`extract.sh chat`) is **paged out** of the Session page to keep it
scannable, but it must be **real and complete** — never a placeholder. After the Session
page exists (step 5), create a child page under it: `notion-create-pages` with
`parent: {"type":"page_id","page_id":"<session_page_id>"}`, title `Full chat`, icon
`https://www.notion.so/icons/chat_gray.svg`, and `content` = the `extract.sh chat` output
with **each line as its own paragraph, verbatim**. If the output is large, split it across
**multiple `notion-create-pages` / append calls** (chunk on line boundaries, never
mid-line) — the chat is large by nature; do **not** truncate it to fit one call. Then put a
single link in the Session page's **Full chat** Details toggle:
`- [Full chat (N turns)](<child_page_url>)`, where N = the line count of
`extract.sh chat` (`bash "$E" chat "$TX" | wc -l`).

**Anti-fabrication (hard rule).** Never write a sentence that *describes* the chat in place
of the chat (e.g. "the formatted full chat continues below…"), never claim a turn count you
did not embed, and never paste a 2-turn excerpt under a "full chat" heading. Either the real
content is in the child page, or the chat was genuinely empty and the toggle says so with a
short `(no content)` note (in the user's language). The Full chat is the audit trail that
proves the curated Highlights were not
invented — a **fabricated audit trail is worse than none**, and contradicts the project's
core invariant that Claude never invents conversation.

## 6. Create the Decision rows

**What earns a Decision row.** Only **architecture / dependency / process** choices that
shape the project belong in the Decisions DB. Keep display / naming / wording tweaks in
the Session's Decisions table — do **not** promote them, so recall's signal-to-noise stays
high. A decision to NOT do something still counts.

For each decision, `notion-create-pages` under `decisions_ds_id`. `Name` = a short
**`<topic>: <choice>`** title (≤24 chars, no parenthetical) — e.g. `Notion: MCP only`,
`Link: URL not relation`. Keep the *why* in `Rationale` and the rejected options in
`Alternatives`, never in the Name. Also set `Project`, `Status` = `Active`, `Tags` (JSON
array string from architecture / dependency / process), `Session` = the Session page URL
from step 5, `"date:Date:start"`.

**Dedup & supersede (use the local index for completeness).** A decision's `Name` is
`<topic>: <choice>`, so the **topic prefix is the dedup key.** The free plan cannot
enumerate the Decisions DB (`query-data-sources` is paid), so `notion-search` alone misses
rows that don't surface for your terms. **Consult the local index first** — it lists every
decision's `{topic, status, id}` exhaustively:

```bash
ROOT="$PWD"; IDX="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/index.sh"
bash "$IDX" find-topic "$ROOT" "<topic>"   # every existing row on this topic (any status)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/search.sh" "$ROOT" "<this decision's topic + choice>" decision 5
```

The second line is a **near-duplicate check beyond the exact topic prefix** (mem0-style
consolidation): the local BM25 search surfaces a decision that means the same thing under a
*different* topic string, which `find-topic` would miss. If it returns a clearly-equivalent
`Active` row, supersede/merge instead of adding a parallel one.

- If an `Active` row with the same `<topic>` already exists and is **unchanged**, do **not**
  insert a duplicate.
- If this session **reverses or changes** it, set the old row's `Status` = `Superseded`
  via `notion-update-page` (never overwrite — the change of mind is itself memory), create
  the new decision alongside it, and **update the index for both** (below).
- **Block granularity pollution at write time.** If the candidate is a display / naming /
  wording tweak rather than an architecture / dependency / process choice, do **not** create
  a Decisions row — keep it in the Session's Decisions table. This is the guard that keeps
  rows like `Changed files: bulleted` out of the canonical DB.

**Update the index after every Notion write** (this is what makes the next dedup complete
AND what makes proactive recall work). The 9th arg is a **search snippet** — a one-line
condensation of the decision's `Rationale` (≤160 chars, newlines collapsed to spaces):

```bash
# after creating a Decision (capture its page id from notion-create-pages):
bash "$IDX" upsert "$ROOT" decision "<decision_page_id>" "<topic>" Active "<YYYY-MM-DD>" "<Name>" "<Project>" "<rationale snippet ≤160 chars>"
# after superseding an old one (keep its snippet so it stays searchable as history):
bash "$IDX" upsert "$ROOT" decision "<old_page_id>" "<topic>" Superseded "<old_date>" "<old_Name>" "<Project>" "<old rationale snippet>"
```

The index holds **keys + a derived search snippet** (topic / status / id / a short rationale
condensation) — NOT the canonical content: Notion stays the single source of truth, and recall
fetches the full `Rationale` / `Alternatives` from there. The snippet is regenerated on every
save (like an embedding would be), so it cannot drift into a second truth. It exists so (a)
dedup / supersede / audit can enumerate the **complete** set free-plan search cannot, and (b)
the local BM25 recall (`search.sh`, the cheap always-on first stage in the UserPromptSubmit
hook) can match a prompt against the *reason* a decision was made — not just its title (matching
the title alone misses "do we need an API token?" → "Notion: MCP only", whose reason is the
token, not the title).

## 7. Chat highlights — curated, anchored to real messages

The full cleaned chat is **paged out to a child page** (step 5b), not re-dumped here.
Build the `## Highlights` section as a curated subset, **anchored to the deterministic
`prompts` output from step 3 — those are the human's actual words.**

- **You callouts** — use the real messages from `prompts`, condensed but **never
  invented**. Do not write a "You" line the human did not actually say, and do not turn
  your own analysis into a question they "asked". Pick the 5-8 that drove the key
  decisions.
- **Claude callouts** — paraphrase your replies concisely, and report what *actually*
  happened: **do not inflate success.** Keep the dead-ends, the corrections, and the
  things you decided NOT to do at the same weight as the wins — a highlight reel that
  shows only the clean path is a misleading memory.
- Render as alternating chat-style callouts (You = `blue_bg`, Claude = `gray_bg`); do
  **not** dump the whole transcript or flatten it into prose.

## 8. Update the Project State page (continuity core)

```bash
PROJ="$PWD"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh" get-state "$PROJ"
MD="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh" state-md-path "$PROJ")"
```

State is the SessionStart hook's stable, human-readable anchor — keep it **slim** and
**do not** re-transcribe decisions or rules (those live in the Decisions DB / CLAUDE.md;
re-listing them here only duplicates the latest Session row).

**Single source — compose the State body ONCE, write that *identical* text to both the repo
mirror and Notion.** The mirror (`<repo>/.iroha/state.md`, what the offline SessionStart hook
injects) and the Notion State page (what humans open) are the **same artifact**; authoring it
twice is what lets them drift. (A past save composed them separately and the Notion page ended
up degraded — only a summary callout, with literal `\n`/`\t` escapes leaking in as `nt…n`,
while the mirror was fine. The rule below makes that impossible.)

**State body = plain Notion Markdown** (monochrome, no emoji, **no nested callouts** — plain
`##` headings + `-` lists render cleanly in Notion *and* stay byte-identical to the mirror).
These four sections, in order, **every save** (headings shown in English canonical — translate
them to the user's conversation language):
1. a one-line **summary + date** — `**Latest (YYYY-MM-DD):** <one sentence>`;
2. `## Recent sessions` — the last few Session pages, newest first, as Markdown links:
   `- [YYYY-MM-DD — <topic>](<session_url>)`;
3. `## Unfinished / Next` — carried-over open items as a GFM checklist (`- [ ] …`);
4. `## Decisions` — one link to the Decisions DB (canonical "why" lives there).

Write **real newlines / tabs**, never the two-character sequences `\n` / `\t` (they leak into
Notion as literal `nt`/`n`). Wrap any file/command/path in backticks so Notion does not
auto-linkify `.sh`/`.md` names as URLs.

**Triage the carry-over** every time (this keeps `Unfinished` from rotting into a
graveyard): for each item carried from the prior State, decide done / still-active /
stale-drop — keep only what is genuinely still pending, and mark anything carried for
**2+ sessions** with a `[carried Nx]` tag (translated to the user's language). State is
fully replaced each save, so this triage cannot drift.

**Write it — mirror first, then Notion verbatim from the mirror:**
```bash
mkdir -p "$(dirname "$MD")"
cat > "$MD" <<'STATE'
<the composed State body — real newlines, all four sections above>
STATE
```
Then publish the **exact same text** (the file you just wrote) to Notion — same headings,
same links, same lines; do not re-summarize or re-format it:
- If get-state is empty: `notion-create-pages` under `container_page_id`
  (title `State — <project>`, icon `https://www.notion.so/icons/target_gray.svg`),
  `content` = the mirror's content; then `bash …/config.sh set-state "$PROJ" "<page_id>"`.
- Else: `notion-update-page` `replace_content` on that page id, `content` = the mirror's
  content.

The mirror is the single source; Notion is its rendering — they must match. **Remind the user
to commit `.iroha/state.md` and `.iroha/index.ndjson`** so the memory and the enumeration index
reach teammates. Notion remains the single source of truth for decision/session *content*
(recall reads it via `notion-search`); the repo holds only the State mirror (offline hook) and
the keys-only index (complete enumeration).

## 9. Mark saved + report

```bash
SAVED="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh" saved-dir)"
mkdir -p "$SAVED" && : > "$SAVED/${CLAUDE_SESSION_ID}"
# index the Session row too, so audit/recall can enumerate sessions completely and the local
# BM25 recall can surface "we built something like this before" (9th arg = the Summary snippet):
bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/index.sh" upsert "$PWD" session \
  "<session_page_id>" "" "<Status>" "<YYYY-MM-DD>" "<Name>" "<Project>" "<Summary snippet ≤160 chars>"
```

Report the Session page URL, how many decisions were recorded, and that the Project
State was updated.

## Notes

- Do not write secrets to Notion; if the transcript surfaced any, omit them.
- Highlights come from your memory of the session, not a transcript dump; the full cleaned
  chat is paged out to a child page (step 5b), while the raw transcript is never stored.
- If the stack changed materially this session (new lockfile / framework / CI), suggest
  the user run `/iroha:project` to refresh the project's architecture profile.
