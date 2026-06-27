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
L="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.ts"
bun "$L" get session_ds_id    # empty -> tell the user to run /iroha:init, then stop
bun "$L" get decisions_ds_id
bun "$L" get container_page_id
[ -e "$(bun "$L" saved-dir)/${CLAUDE_SESSION_ID}" ] && echo "ALREADY_SAVED"
```

**Re-save guard (idempotency).** If the last line prints `ALREADY_SAVED`, this session
was already saved. Do **not** create duplicate Session / Decision rows — tell the user
it is already saved and offer to *update* the existing rows instead; stop unless they
confirm. (Duplicate decisions are the one defect that rots the "living memory".)

**Probe Notion auth NOW, before any extraction.** A connected MCP can still be
*unauthenticated* (OAuth not completed) — and bash cannot detect that; you only find out
when the first write 400s mid-save, after the local extraction is already done. So make one
cheap read first: `notion-fetch <container_page_id>`. If it returns an auth/permission error,
the Notion MCP is not authenticated — tell the user to complete the OAuth flow (`/mcp` →
`notion`, or `claude mcp login notion`) and **stop**; resume the save once it succeeds. Doing
this up front means the user authenticates *before* the work, not in the middle of it.

## 2. Locate this session's transcript

Resolve it **deterministically** from the cwd — do **not** glob. (The old
`ls -t "$HOME/.claude/projects/"*"/<sid>.jsonl"` pattern globbed over every project dir and was
observed to return empty and then hang for ~2 min; `transcript-path` derives the exact path and
only falls back to a bounded `find` if the project root moved since launch.)

```bash
# Use ${CLAUDE_SESSION_ID} with braces — skill string substitution only fires on the
# ${...} form. The bare $CLAUDE_SESSION_ID is NOT an env var in the Bash tool, so it
# passes through unsubstituted and resolves to empty (transcript then "not found").
TX=$(bun "$L" transcript-path "$PWD" "${CLAUDE_SESSION_ID}")
echo "$TX"   # empty -> transcript not found; tell the user and stop
```

## 3. Deterministic extraction

```bash
E="${CLAUDE_PLUGIN_ROOT}/scripts/extract.sh"
# ONE call parses the (large) transcript once and returns every view as a JSON object:
#   .meta  {title, started, ended, cwd, gitBranch, model, sessionId}
#   .stats {userTurns, assistantTurns, toolCalls, filesEdited, bashCommands, durationMin, …}
#   .files / .commands / .prompts / .tools / .chat  — arrays of pre-formatted lines
#     (.prompts = the human's real messages = the You-side anchor for step 7;
#      .chat = cleaned full chat, per-turn capped, for the Full-chat child page in step 5b)
bash "$E" all "$TX"
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

**5.0 — Ensure the `Project` option exists (first save of a new project).** `Project`
is a **SELECT**, not a free string, and `notion-create-pages` does **not** auto-create
a missing option — an unseeded value is rejected with a 400 (`Value must be one of: …`).
So the *first* save of a new project (or a teammate joining a shared workspace) fails
unless the option is added first. Before creating any row:

- The current project is `basename "$PWD"`. `notion-fetch` the Sessions data source and
  read its `Project` options to see whether it is already there.
- If it is **missing**, this project is about to be added to a **shared** Notion
  workspace (Sessions/Decisions DBs are shared across projects). **Ask the user once**
  to confirm before mutating the shared schema (e.g. "Add `<project>` to the shared
  iroha workspace and save the session here?"). On confirmation, add the option to
  **both** data sources (they share the `Project` value):
  ```
  notion-update-data-source <session_ds_id>    statements: ALTER COLUMN "Project" SET SELECT(<existing options…>, '<project>':blue)
  notion-update-data-source <decisions_ds_id>  statements: ALTER COLUMN "Project" SET SELECT(<existing options…>, '<project>':blue)
  ```
  `ALTER … SET` **replaces** the whole option list, so include every option you just
  read **plus** the new one — never drop a teammate's project. If the option already
  exists, skip this entirely (never re-ALTER on a normal save).

`notion-create-pages` with `parent: {"type":"data_source_id","data_source_id":"<session_ds_id>"}`.
Property map uses SQLite values:
- `Name` (title) — **`YYYY-MM-DD — <topic>`** (start date + a ≤20-char noun-phrase
  topic; no project prefix, no Type — those are properties). Calendar / Board cards show
  only the Name, so the date prefix keeps them time-scannable. Good:
  `2026-06-24 — Notion integration design + Phase 1`. Bad: `iroha: design + impl` (no date) /
  `[Design/Impl] …` (Type duplicated).
- `Status`, `Branch`, `Author`, `Summary` — plain strings. `Project` is also written as
  a plain string here, but it is a **SELECT**: its option must already exist (see 5.0).
- `Type` — a JSON array **string**, in the user's conversation language to match the seeded
  options (the English names above are canonical); English-workspace form looks like
  `"[\"Design\", \"Implementation\"]"`.
- Date — expanded keys: `"date:Date:start"` = started ISO, `"date:Date:is_datetime"` = `1`
  **as a JSON number, not the string `"1"`** (a string is rejected with a 400).

**`content` = Notion-flavored Markdown, visual and monochrome (no emoji icons).**
Keep the **section headings in English canonical** (`## Metrics`, `## Decisions`, … — they
are structural, like property names, and `audit` / `state-lint` enumerate them by name);
render the **body prose** (summary, table cells, callout text, toggle labels) in the user's
conversation language. Read the spec once via `notion://docs/enhanced-markdown-spec`.
Emit **exactly these sections, in this order, on every save** — the structure must be
identical each time. The **only** optional sections are **Architecture**, **Rules
changed**, and **Failures** (include them only when they apply); never add, drop,
rename, or reorder anything else (the section headings below are English canonical — keep
them verbatim; localize only the body prose). Do **not** add an Overview / meta table — the page properties already
show Project / Status / Type / Date / Branch / Author at the top:
1. a header `<callout color="blue_bg">` with the one-line summary;
2. `## Metrics` — a `<callout color="gray_bg">` dashboard built **verbatim from `.stats`**
   (step 3's `all` output — never hand-count). One readable line, ` · `-separated, with a clear
   label on **every** number (no emoji — house rule) and **no cryptic `a↔b`** form. Use this
   shape: `Duration <durationMin> min · <userTurns> prompts → <assistantTurns> Claude replies ·
   <toolCalls> tool calls (<bashCommands> bash) · <filesEdited> files changed`, e.g.
   `Duration 67 min · 3 prompts → 74 Claude replies · 144 tool calls (46 bash) · 20 files changed`.
   Always included; one glance must tell the reader exactly what each number means;
3. `## Architecture` *(optional — only when the work has real structure worth a diagram)*:
   a **one-line caption first** saying *what the diagram shows and why it is here* (so a reader
   never has to ask "a diagram of what?"), then a ```mermaid``` diagram. Omit the whole section
   when there is nothing structural to show — never emit a diagram without its caption, and never
   force one onto a session that did not build a structure;
4. `## Decisions` as a `<table header-row="true">` with a `<tr color="blue_bg">` header
   (columns: Decision / Why / Rejected alternatives);
5. `## Progress` as a green_bg callout (Done) + an orange_bg callout (Unfinished, `- [ ]`);
6. `## Highlights` — 5-8 pivotal exchanges as alternating chat-style callouts
   (You = `blue_bg`, Claude = `gray_bg`), **wrapped in a `<details>` toggle so they are
   collapsed by default and expand on click** (the section is long — keep the page
   scannable). Give the `<summary>` the English canonical label `Highlights (N exchanges)`,
   and **tab-indent the callouts inside the toggle**. The
   **You** lines come from the `prompts` extract (real messages, never invented), Claude
   lines are paraphrased — **not** the full chat (see step 7);
7. `## Rules changed` *(optional — only when this session established or changed a rule)*
   as a `<callout color="gray_bg">`; omit the whole section when no rule changed;
8. `## Failures` *(optional — only when there were notable pitfalls)* as a
   `<details><summary>…</summary>` toggle. Write each as **symptom → root cause → fix**
   (Reflexion: a failure is first-class, recallable memory — phrase the symptom in the words
   a future search would use, so the next session surfaces it *before* repeating the
   dead-end). **For the proactive hook to actually surface it, the symptom must also reach the
   session's search snippet in step 9 — text living only in this page body is found only by
   explicit /iroha:recall.**
9. `## Details` with `<details><summary>…</summary>` toggles, in this order:
   **Changed files** (`.files`), **Commands** (`.commands`), **Tools** (`.tools` — the per-tool
   tally), all from step 3's `all` output. Render the `files` / `commands` / `tools` arrays as
   **bulleted lists** verbatim (they are already `- ` lines; never join entries with `·`).
   **Do NOT add a "Full chat" toggle here.** The full chat is a child page (step 5b), and Notion
   already lists that child page natively under the session — a toggle linking to it only makes
   the same "Full chat" appear twice. The child page's own title carries the turn count, so it is
   self-explanatory without a toggle.
Wrap every file name / command / path in backticks — **including inside callouts and
tables** — so Notion does not auto-linkify `.sh` / `.md` names as `http://…` URLs.
Indent callout / toggle / table children with **tabs**. Keep the returned page URL.

**Lint for auto-linkify BEFORE publishing — deterministic gate, not eyeballing.** Backticking
by hand recurs as a leak (it has turned `extract.sh` / `CLAUDE.md` in this very page into bogus
`http://…` links). So before the `notion-create-pages`, write the composed `content` to a temp
file and run `bun "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/link-lint.ts" <file>`; it lists every bare
file / command / path token sitting outside a backtick span / code fence / `[text](url)` link.
Wrap each flagged token in backticks and re-lint until it **exits 0** — never publish content
link-lint flags. Apply the same gate to **every prose surface** you publish here: the Session
`content`, the State mirror (step 8), decision page bodies (step 6), and any callout.

Set a clean monochrome page icon:
`icon: "https://www.notion.so/icons/notebook_gray.svg"`.

**Once the Session page exists, the remaining writes are independent — issue them in
parallel.** Steps 5b (the Full-chat child), 6 (the Decisions batch), and 8 (the State page)
each depend only on the Session page id / URL you now hold, **not on each other**. Do the cheap
local prep first (the dedup / supersede pass for 6; write + lint the State mirror for 8), then
send those Notion writes **in one turn (parallel tool calls)** rather than serially — the
network-bound phase becomes one round-trip deep instead of three. Collect the returned page ids
for the index upserts in step 9.

## 5b. Full chat as a child page (never fake it)

The cleaned full chat (the `.chat` array from step 3) is **paged out** of the Session page to
keep it scannable, but it must be **real** — never a placeholder. It is the *cleaned* chat,
not a raw dump: **every turn is present** (none dropped), but each turn is **capped per-turn**
(`extract.sh` truncates a long turn to ~600 chars with a `… (truncated)` marker — this is by
design, so do not claim it is "verbatim/unbounded"). After the Session page exists (step 5),
create a child page under it: `notion-create-pages` with
`parent: {"type":"page_id","page_id":"<session_page_id>"}`, title **`Full chat — N turns`**
(N = the number of `.chat` lines, its array length — putting the count in the title makes the
natively-listed child page self-explanatory, so no Details toggle is needed), icon
`https://www.notion.so/icons/chat_gray.svg`, and `content` = the `.chat` lines, **each line as
its own paragraph, exactly as emitted**. If `.chat` is large, split it across **multiple
`notion-create-pages` / append calls** (chunk on line boundaries, never mid-line) — the chat is
large by nature; do **not** drop turns to fit one call. Do **not** also add a "Full chat" toggle
under `## Details` (step 5, item 9): Notion already shows this child page under the session, so a
toggle would duplicate it.

**Anti-fabrication (hard rule).** Never write a sentence that *describes* the chat in place
of the chat (e.g. "the formatted full chat continues below…"), never claim a turn count you
did not embed, and never paste a 2-turn excerpt under a "full chat" heading. Either the real
content is in the child page, or the chat was genuinely empty and the child page says so with a
short `(no content)` note (in the user's language). The Full chat is the audit trail that
proves the curated Highlights were not
invented — a **fabricated audit trail is worse than none**, and contradicts the project's
core invariant that Claude never invents conversation.

## 6. Create the Decision rows

**What earns a Decision row.** Only **architecture / dependency / process** choices that
shape the project belong in the Decisions DB. Keep display / naming / wording tweaks in
the Session's Decisions table — do **not** promote them, so recall's signal-to-noise stays
high. A decision to NOT do something still counts.

Each decision is a row under `decisions_ds_id`. **Run the dedup / supersede pass (below)
for every candidate first, then create all the surviving *new* rows in ONE
`notion-create-pages` call** — they share the same parent (`decisions_ds_id`), and the tool
takes a `pages[]` array (≤100), so N decisions cost one round-trip, not N. (Supersede
*updates* to old rows stay separate `notion-update-page` calls — they target different pages.)

Each decision's `Name` = a short **`<topic>: <choice>`** title (≤24 chars, no parenthetical) —
e.g. `Notion: MCP only`, `Link: URL not relation`. Keep the *why* in `Rationale` and the
rejected options in `Alternatives`, never in the Name. Also set `Project`, `Status` = `Active`,
`Topic` (the `<topic>` half of the Name, as a **SELECT** — see below), `Tags` (JSON array string
from architecture / dependency / process), `Session` = the Session page URL from step 5,
`"date:Date:start"`. When this decision **replaces** an earlier one (see supersede, below), also
set `Supersedes` = the **Notion URL of the decision it replaced**
(`https://www.notion.so/<bare-old-id>`) — the lineage link `/iroha:history` walks.

**Ensure the `Topic` option exists (same as `Project`, 5.0).** `Topic` is a SELECT and does
**not** auto-create options on write — a new topic 400s unless added first. Reuse the topics you
already see in the local index (`bun "$IDX" find-topic` below lists them); if this decision's
`<topic>` is new, `notion-update-data-source <decisions_ds_id>` `ALTER COLUMN "Topic" SET
SELECT(<existing topics…>, '<topic>':color)` before creating the row (include existing options —
SET replaces the list). Prefer reusing an existing topic string over coining a near-synonym, so
the topic families stay consolidated rather than fragmenting (e.g. do not coin both
`recall-precision` and `recall` as separate topics for one concept).

**Dedup & supersede (use the local index for completeness).** A decision's `Name` is
`<topic>: <choice>`, so the **topic prefix is the dedup key.** The free plan cannot
enumerate the Decisions DB (`query-data-sources` is paid), so `notion-search` alone misses
rows that don't surface for your terms. **Consult the local index first** — it lists every
decision's `{topic, status, id}` exhaustively:

```bash
ROOT="$PWD"; IDX="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/index.ts"
bun "$IDX" find-topic "$ROOT" "<topic>"   # every existing row on this topic (any status)
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
  the new decision alongside it **with `Supersedes` = the old row's Notion URL** (this is the
  lineage edge `/iroha:history` follows), and **update the index for both** (below).
  Also give the new decision a **one-line page body** making the lineage human-readable in
  Notion (the `Supersedes` URL property renders as a bare link that hides *what* it replaced):
  `content` = `Supersedes [<old topic>: <old choice>](<old-url>) — <one-line why it changed>`.
  This is the only thing in the decision body; the *why* still lives in `Rationale`. Without it
  the lineage is visible only via the `/iroha:history` CLI, never to someone reading Notion.
- **Block granularity pollution at write time.** If the candidate is a display / naming /
  wording tweak rather than an architecture / dependency / process choice, do **not** create
  a Decisions row — keep it in the Session's Decisions table. This is the guard that keeps
  rows like `Changed files: bulleted` out of the canonical DB.

**Update the index after every Notion write** (this is what makes the next dedup complete
AND what makes proactive recall work). The 9th arg is a **search snippet** — a one-line
condensation of the decision's `Rationale` (≤160 chars, newlines collapsed to spaces; end on a
**word / phrase boundary, never mid-token** so the trailing CJK bigram the BM25 stage keys on
stays intact):

```bash
# after creating a Decision (capture its page id from notion-create-pages). The 10th arg is the
# bare id of the decision this one SUPERSEDES (empty for an original) — the lineage /iroha:history walks:
bun "$IDX" upsert "$ROOT" decision "<decision_page_id>" "<topic>" Active "<YYYY-MM-DD>" "<Name>" "<Project>" "<rationale snippet ≤160 chars>" "<old_page_id-if-superseding-else-empty>"
# after superseding an old one (keep its snippet so it stays searchable as history):
bun "$IDX" upsert "$ROOT" decision "<old_page_id>" "<topic>" Superseded "<old_date>" "<old_Name>" "<Project>" "<old rationale snippet>"
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
bun "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.ts" get-state "$PROJ"
MD="$(bun "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.ts" state-md-path "$PROJ")"
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
These four sections, in order, **every save** (the `##` section headings stay **English
canonical** — they are structural and `state-lint` / `audit` rely on them; the body lines are
in the user's conversation language):
1. a one-line **summary + date** — `**Latest (YYYY-MM-DD):** <one sentence>`. Write this opening
   sentence in **plain language a newcomer understands** — no `BM25 / rerank / veto / abstention /
   N=1`-style jargon in the first line (details can follow it). It is the first thing SessionStart
   injects and the first thing a teammate reads. Any number in it must be **point-in-time**
   (`Recall@3 86% as of <date>`), never a bare "current X%" that silently goes stale — the live
   metrics live here and in `architecture.md`, and a Decision must not carry a competing "current"
   figure (decisions are immutable history; quote a dated point-in-time value there);
2. `## Recent sessions` — the last few Session pages, newest first, as Markdown links:
   `- [YYYY-MM-DD — <topic>](<session_url>)`;
3. `## Unfinished / Next` — carried-over open items as a GFM checklist (`- [ ] …`);
4. `## Decisions` — one link to the Decisions DB (the **`Active` view**, where canonical "why"
   lives) and one link to this project's **Projects row** (its stack profile), so State and
   Projects are mutually reachable (the Projects row links back to State via `/iroha:project`).
   If no Projects row exists yet, omit that link and suggest the user run `/iroha:project`.

Write **real newlines / tabs**, never the two-character sequences `\n` / `\t` (they leak into
Notion as literal `nt`/`n`). Wrap any file/command/path in backticks so Notion does not
auto-linkify `.sh`/`.md` names as URLs.

**Triage the carry-over** every time (this keeps `Unfinished` from rotting into a
graveyard): for each item carried from the prior State, decide done / still-active /
stale-drop — keep only what is genuinely still pending, and mark anything carried for
**2+ sessions** with a `[carried Nx]` tag (translated to the user's language). State is
fully replaced each save, so this triage cannot drift.

**Carried 3+ times → force a keep/drop decision (signal hygiene).** SessionStart injects this
list every session, so a graveyard item (e.g. a low-value cosmetic chore that has ridden along
`[carried 7x]`) actively *dilutes* the one or two items that matter. For anything at 3x or more,
do not just bump the counter: either **drop it** (be honest that it is not going to happen — a
dropped item is not lost, the Session that raised it still records it), or, if it is genuinely
important but stalled, keep it but say in one clause *why it is still blocked*. The injected
Unfinished should read as "the few things that actually matter next", never as a backlog dump.

**Write it — mirror first, then Notion verbatim from the mirror:**
```bash
mkdir -p "$(dirname "$MD")"
cat > "$MD" <<'STATE'
<the composed State body — real newlines, all four sections above>
STATE
# Validate the mirror BEFORE publishing — this is the deterministic guard against the
# State-corruption class that degraded a past save (literal \n/\t escapes, sections dropped to a
# summary-only callout). If it prints any issue, FIX the body and rewrite "$MD" until it is clean;
# never publish a State that fails the lint. Because the mirror and Notion are byte-identical
# (single source), a clean mirror means a clean Notion page.
bun "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/state-lint.ts" "$MD"
# Same gate against Notion auto-linkify: a bare file/path in the State body becomes a bogus
# http://… link. link-lint must also exit 0 before publishing (backtick anything it lists).
bun "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/link-lint.ts" "$MD"
```
Then publish the **exact same text** (the file you just wrote) to Notion — same headings,
same links, same lines; do not re-summarize or re-format it:
- If get-state is empty: `notion-create-pages` under the **`States` folder**
  (`bun …/config.ts get states_folder_id`; fall back to `container_page_id` only if a
  pre-folder workspace returns empty) — title `State — <project>`, icon
  `https://www.notion.so/icons/target_gray.svg`, `content` = the mirror's content; then
  `bun …/config.ts set-state "$PROJ" "<page_id>"`. Keeping every project's State under the one
  `States` folder is what stops the container root from filling with one flat State page per
  project.
- Else: `notion-update-page` `replace_content` on that page id, `content` = the mirror's
  content.

The mirror is the single source; Notion is its rendering — they must match. **Remind the user
to commit `.iroha/state.md` and `.iroha/index.ndjson`** so the memory and the enumeration index
reach teammates. Notion remains the single source of truth for decision/session *content*
(recall reads it via `notion-search`); the repo holds only the State mirror (offline hook) and
the keys-only index (complete enumeration).

## 9. Mark saved + report

```bash
SAVED="$(bun "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.ts" saved-dir)"
mkdir -p "$SAVED" && : > "$SAVED/${CLAUDE_SESSION_ID}"
# index the Session row too, so audit/recall can enumerate sessions completely and the local
# BM25 recall can surface "we built something like this before" (9th arg = the Summary snippet).
# **Reflexion (make a failure recallable, not just stored).** If this session recorded a notable
# Failure (§ Failures) — a dead-end a future session should avoid repeating — fold its *symptom
# keywords* into this snippet, not only the wins. The snippet is the ONLY failure text the
# always-on local recall can match; a symptom written solely in the Session page body is
# reachable only by explicit /iroha:recall (semantic), so the proactive hook would never warn
# "you hit this before". This is what completes the Reflexion loop the § Failures wording promises.
bun "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/index.ts" upsert "$PWD" session \
  "<session_page_id>" "" "<Status>" "<YYYY-MM-DD>" "<Name>" "<Project>" "<Summary+failure-symptom snippet ≤160 chars>"
```

**Verify the index before declaring done (root-cause guard for index drift).** A forgotten
`index.ts upsert` silently drops a decision from the enumeration index — recall then can never
surface it and audit under-counts, with no error at save time (this is exactly how the index drifted
~22% short while dogfooding). So after the writes, confirm the substrate is consistent and that
**every decision page you created this session is in the index**:

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/integrity.ts" "$PWD"   # must exit 0 (no malformed/dup/State-dangling)
# for each decision page id you created above, confirm it is now indexed:
bun "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/index.ts" list "$PWD" decision | jq -r .id | grep -qF "<decision_page_id>" \
  || echo "MISSING FROM INDEX: <decision_page_id> — upsert it before finishing"
```

If anything is missing or `integrity.ts` prints an issue, fix it (upsert the row / correct the
mirror) and re-check until clean — do **not** finish on a drifted substrate.

Report the Session page URL, how many decisions were recorded, that the Project State was
updated, and that the index verified clean.

**Commit `.iroha/` — but on the *first* save, let the user choose committed vs ignored.**
The default is to **commit** `.iroha/state.md` and `.iroha/index.ndjson` in the same commit as
the code — that is how the State mirror and enumeration index reach teammates, and State must
only ever change through save-session (a hand-edit in an unrelated commit once left State ahead
of the saved sessions; integrity's State↔index check now flags the worst form of that). But on
the **first** save in a repo, `.iroha/` is freshly generated, **untracked, and not yet in
`.gitignore`** — a blanket `git add -A` would sweep this personal memory into history, which is
wrong for a public/OSS repo where the team may not want their working notes published. So if
`.iroha/` is untracked and not ignored, **ask once**: commit it (shared memory, the default) or
add `/.iroha/` to `.gitignore` (keep memory local to this machine). After that first choice the
reminder is simply "commit `.iroha/` with the code".

## Notes

- Do not write secrets to Notion; if the transcript surfaced any, omit them.
- Highlights come from your memory of the session, not a transcript dump; the full cleaned
  chat is paged out to a child page (step 5b), while the raw transcript is never stored.
- If the stack changed materially this session (new lockfile / framework / CI), suggest
  the user run `/iroha:project` to refresh the project's architecture profile.
