---
name: init
description: One-time setup for iroha-for-session. Creates the Sessions and Decisions databases in the user's Notion via the connected Notion MCP, then records their ids locally. Run before the first /save-session, or to reconnect / join a teammate's existing iroha workspace. Triggers on "/iroha:init", "set up iroha", "initialize notion memory".
argument-hint: "[notion-parent-page-url]"
---

# iroha: init

Set up (or join) the Notion workspace iroha writes sessions to. Idempotent:
pointing it at a page that already has `Sessions` / `Decisions` / `Projects` databases
reuses them instead of creating duplicates. All ids are cached in
`$HOME/.iroha/config.json` (non-secret; override the dir with
`IROHA_CONFIG_DIR`). Auth is the user's **Notion MCP** OAuth connection — there is no
API token.

## Steps

1. **Check Notion MCP is connected.** Confirm tools like `notion-create-database`,
   `notion-create-pages`, `notion-fetch` are available. If not, ask the user to
   connect the hosted Notion MCP (OAuth) and stop.

2. **Check existing config:**

   ```bash
   bun "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.ts" get session_ds_id
   ```

   If it prints an id, iroha is already initialized — say so and stop unless the
   user explicitly asks to re-initialize.

3. **Resolve the root page (where iroha's memory will live).** If `$ARGUMENTS` is a Notion
   page URL/ID, use it as the root and skip the prompt. Otherwise **do not assume the user has
   pre-made a page** — ask with **`AskUserQuestion`** ("Where should iroha's memory live?"),
   two options:
   - **Create it for me (recommended)** — ask for a name (default `iroha`), then
     `notion-create-pages` with **no `parent`** (a top-level, workspace-level private page),
     `properties: {"title": "<name>"}`, icon `https://www.notion.so/icons/notebook_gray.svg`.
     This is the zero-setup path: the first-time user never has to know to pre-create a page.
   - **Use an existing page** — ask the user to paste the page URL (e.g. a blank page they
     already made), then `notion-fetch` it.
   Either way, `notion-fetch` the resolved page to confirm access, get the **bare page id
   (32-hex)**, and tell the user the title + that everything below will be created under it (so
   they know exactly where iroha lives). Localize the question/labels to the user's language.

4. **Reuse if present (team-join).** If the fetched page already contains `Sessions`,
   `Decisions`, and `Projects` databases, capture their data source ids (step 7), also
   capture the `States` / `Digests` grouping pages (create them per step 5 if this older
   workspace lacks them, moving any existing State / Digest pages under them), and stop —
   this is how a teammate joins a shared workspace without creating duplicates.

5. **Create the three databases** directly under that page with `notion-create-database`,
   which takes **SQL DDL** (`CREATE TABLE`). Do NOT use `RELATION` columns (the MCP
   relation write path is buggy); link records with a `URL` column instead. Replace
   `iroha-for-session` in the `Project` option with the current project name
   (basename of the user's cwd). **Note:** `notion-create-pages` does **not**
   auto-create a missing `SELECT` option — writing an unseeded `Project` value returns a
   400. Adding a *second* project later is handled by `save-session` (it ALTERs the
   option in on that project's first save — see save-session 5.0); the value seeded here
   is just the starting one.

   **Localize to the user's conversation language.** The DDL below is the canonical
   **English template**. When you actually issue it, translate the human-facing **`Type`**
   option labels into the user's conversation language (e.g. for a Japanese user, use the
   Japanese terms for Research / Design / Implementation / etc.). Keep everything
   **structural in English** so the schema is stable across languages and locales: all
   property *names*, the `Status` and `Languages` option values, and the `Project` value
   (the repo name). save-session then writes `Type` in that same language. (This mirrors
   the working convention: structural keys English, content categories in the user's
   language.)

   Sessions:

   ```
   parent: {"type":"page_id","page_id":"<PAGE_ID>"}   title: "Sessions"
   schema: CREATE TABLE ("Name" TITLE, "Date" DATE, "Project" SELECT('iroha-for-session':blue), "Branch" RICH_TEXT, "Author" RICH_TEXT, "Summary" RICH_TEXT, "Status" SELECT('Complete':green, 'WIP':yellow, 'Interrupted':red), "Type" MULTI_SELECT('Research':blue, 'Requirements':purple, 'Design':orange, 'Implementation':green, 'Fix':red, 'Refactor':brown, 'Review':gray))
   ```

   Decisions:

   ```
   parent: {"type":"page_id","page_id":"<PAGE_ID>"}   title: "Decisions"
   schema: CREATE TABLE ("Name" TITLE, "Project" SELECT('iroha-for-session':blue), "Topic" SELECT('general':gray), "Status" SELECT('Active':green, 'Superseded':gray), "Tags" MULTI_SELECT('architecture':blue, 'dependency':orange, 'process':gray), "Rationale" RICH_TEXT, "Alternatives" RICH_TEXT, "Session" URL, "Supersedes" URL, "Date" DATE)

   `Topic` is a first-class **SELECT** (the `<topic>` half of the `<topic>: <choice>` Name):
   it makes the decision's topic a real, filterable/groupable property instead of a string
   parsed out of the title, so supersede-grouping is robust and a teammate can browse decisions
   by topic. Like `Project` it does **not** auto-create options on write — `save-session`
   ALTERs a new topic's option in on first use (see save-session 5.0 / 6). `Supersedes` (URL) is
   the lineage edge to the decision this one replaced (relation-free, same URL-linking as
   `Session`); it is required for `/iroha:history` and the `integrity` lineage check.
   ```

   Projects (one row per project — the cross-project architecture layer for catch-up
   and "how do our other <language> projects do this?"):

   ```
   parent: {"type":"page_id","page_id":"<PAGE_ID>"}   title: "Projects"
   schema: CREATE TABLE ("Name" TITLE, "Languages" MULTI_SELECT('TypeScript':blue, 'JavaScript':yellow, 'Go':blue, 'Python':green, 'Rust':orange, 'Bash':gray), "Frameworks" RICH_TEXT, "DevTools" RICH_TEXT, "CI" RICH_TEXT, "Repo" URL, "Updated" DATE)
   ```
   Only `Languages` is multi_select (finite, filterable); Frameworks / DevTools / CI are
   rich_text (libraries are too many / too varied for select — let `notion-search` find
   them in the text).

   **Then create two grouping pages directly under the container — `States` and `Digests`.**
   These keep the container tidy as it grows: per-project State pages live under `States`,
   digest pages under `Digests`, so the container root stays just *guide + the 3 DBs + these 2
   folders* no matter how many projects join or digests run (without them, every project's State
   and every digest pile up as flat container children). Create each as a plain page with a
   short purpose callout and a folder-ish icon
   (`https://www.notion.so/icons/folder_gray.svg`); capture the two page ids. **On reuse /
   team-join (step 4), find the existing `States` / `Digests` pages by title instead of
   creating duplicates — and if an older workspace lacks them, create them now and move any
   existing State / Digest pages under them.**

6. **Read the data source ids from each result.** `notion-create-database` returns a
   `<data-source url="collection://<DS_ID>">` tag. Rows are created under the **data
   source id** (collection), NOT the database id — capture both.

7. **Save the ids:**

   ```bash
   L="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.ts"
   bun "$L" set container_page_id "<PAGE_ID>"
   bun "$L" set session_db_id   "<SESSIONS_DATABASE_ID>"
   bun "$L" set session_ds_id   "<SESSIONS_DATA_SOURCE_ID>"
   bun "$L" set decisions_db_id "<DECISIONS_DATABASE_ID>"
   bun "$L" set decisions_ds_id "<DECISIONS_DATA_SOURCE_ID>"
   bun "$L" set projects_db_id  "<PROJECTS_DATABASE_ID>"
   bun "$L" set projects_ds_id  "<PROJECTS_DATA_SOURCE_ID>"
   bun "$L" set states_folder_id  "<STATES_PAGE_ID>"     # grouping pages from step 5 — keep
   bun "$L" set digests_folder_id "<DIGESTS_PAGE_ID>"    # the container tidy as it grows
   bun "$L" set recall_enabled  true   # arm enforced JIT recall (the UserPromptSubmit hook
                                        # stays idle until this is true — so a fresh install
                                        # that never ran init costs nothing per prompt)
   ```

8. **Create views for fast team browsing.** On the **Sessions** database (uses its
   `database_id` + data source id from step 6):
   - `notion-create-view` type `table` named **`Recent`**, `SORT BY "Date" DESC` — make
     this the primary entry ("what did we do recently?" is the most common need, and a
     date-descending table beats Calendar/Board for it).
   - `notion-create-view` type `calendar`, `CALENDAR BY "Date"` (visual month navigation).
   - `notion-create-view` type `table` named **`By Month`**, `GROUP BY "Date" SORT BY "Date"
     DESC` — collapsible date groups so the list stays navigable as sessions accumulate (this is
     the scalable "browse by period" answer; a flat table never needs to become a page hierarchy,
     which would forfeit filter/sort/search). Notion groups a date by *relative* buckets by
     default; the user can switch the group granularity to **Month** in the view settings for
     literal calendar-month buckets (e.g. `2026-06`).
   - `notion-create-view` type `board`, `GROUP BY "Status" SORT BY "Date" ASC` (secondary).
   On the **Decisions** database:
   - `notion-create-view` type `table` named **`Active`**, `FILTER "Status" = "Active"`
     so superseded / reverted decisions do not clutter "what did we decide?". Make this the
     **primary** Decisions view (the entry-guide callout points here).
   - `notion-create-view` type `board` named **`By Topic`**, `GROUP BY "Topic" FILTER "Status"
     = "Active"` so a teammate can see the decision families at a glance and spot topic
     fragmentation (the dispersion that title-prefix parsing hid).
   (Filter values use **double quotes** in the view DSL — `= "Active"`, not `= 'Active'`; a
   single-quoted value is rejected with a DSL validation error.)
   On the **Projects** database:
   - `notion-create-view` type `board` named **`By Language`**, `GROUP BY "Languages"
     SORT BY "Updated" DESC` so a teammate can browse "all our Go / Python projects".

9. **Add the entry-point guide + dashboard to the root page — readable, never one run-on
   paragraph.** Use `notion-update-page` `insert_content`, and write content with **real
   newlines / tabs, NEVER the two-character `\n` / `\t` escapes** — they leak into Notion as
   literal `nt` / `n` (the same escape-leak the State publish step warns about; it also bites
   callouts and lists inserted via MCP). **`fetch` the page afterward to confirm no leak.** Also
   run the composed guide/caption text through
   `bun "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/link-lint.ts"` before publishing — it flags bare
   file/path tokens (`extract.ts` / `CLAUDE.md`) Notion would auto-linkify; backtick them until it
   exits 0.

   **(a) Navigation — a short bold lead line + a bulleted list** (insert at `{"type":"start"}`),
   so a teammate sees "where things are" at a glance (one bullet each; labels below are the
   English template — **localize** them):
   - **Current state** → link the project's **State page** if it exists; on a fresh init it does
     not yet (State is created on the first `/iroha:save-session`), so link the **`States`
     folder** and say State appears after the first save.
   - **Past decisions** → Decisions **`Active`** view (overview: **`By Topic`**).
   - **Each session** → Sessions **`Recent`** / **`By Month`**.
   - **Tech stack** → Projects **`By Language`**.

   **(b) A short one-block `<callout>`** for the meta: the only recurring command is
   `/iroha:save-session`; recall + State are injected **automatically**; naming conventions
   (sessions `YYYY-MM-DD — <topic>`, decisions `<topic>: <choice>`); this workspace is **generated
   by the iroha skills — don't hand-edit rows** (search with `/iroha:recall`, refresh stack with
   `/iroha:project`).

   **(c) Dashboard charts** — append a `## Visualization` heading (localized) then a few **linked
   chart views** so the top page visualizes the memory as it grows. `notion-create-view` with
   `parent_page_id` = the root page and `data_source_id` = the DB (charts append to the page end).
   They are **empty until data exists — that is expected**; they fill as sessions / decisions
   accumulate. Create:
   - Sessions activity — `GROUP BY "Date"; CHART column AGGREGATE count COLOR blue HEIGHT small`.
   - Sessions by Type — `GROUP BY "Type"; CHART donut AGGREGATE count COLOR colorful HEIGHT small`.
   - Decisions by Topic (Active) — `FILTER "Status" = "Active"; GROUP BY "Topic"; CHART bar AGGREGATE count HEIGHT small`.
   - Decisions by Status — `GROUP BY "Status"; CHART donut AGGREGATE count HEIGHT small`.
   (CHART DSL: `GROUP BY` sets the x-axis; `AGGREGATE` defaults to `count`; optional `COLOR` /
   `HEIGHT` / `CAPTION`. Filter values use **double quotes**.)

   Write all guide / caption prose in the user's conversation language (English here is the
   canonical template).

10. **Confirm — make the "now what?" crystal clear.** Give the user, in their language:
    - a one-line **link to the root page** (their new iroha home) and the key views to navigate
      by — Sessions `Recent` / `By Month`, Decisions `Active` / `By Topic`, Projects `By Language`.
    - **the whole loop in one breath**: "Setup is one-time. From now the only command you run is
      `/iroha:save-session` at the end of a working session — recall and your project State are
      injected **automatically** (no command needed). Look things up any time with
      `/iroha:recall <topic>`; refresh the stack with `/iroha:project` when it changes."
    - that **proactive recall is now armed**: each substantive prompt gets a bounded local recall
      of relevant past decisions (disable with `IROHA_RECALL_DISABLE=1`; check readiness with
      `bun "${CLAUDE_PLUGIN_ROOT}/hooks/recall-inject.ts" --selfcheck`). It is a dependency-free TS
      BM25 over the local index — zero deps, instant, offline. For deeper, semantic lookups the user
      runs `/iroha:recall <topic>` (Notion's own semantic search, free plan); no local models to install.

## Notes

- Databases are shared across projects; the `Project` property separates them.
- Teams: one person runs init, shares the page in Notion, teammates run init against
  the same page to join (step 4 reuses the existing databases).
