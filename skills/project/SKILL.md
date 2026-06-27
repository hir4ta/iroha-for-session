---
name: project
description: Capture or update this project's architecture profile in iroha — language(s), frameworks / key libraries, dev tooling, CI, an architecture diagram, and setup steps — so juniors catch up fast and Claude can find how other projects (same language / same library) are built. Run manually when the stack is set up or materially changes. Triggers on "/iroha:project", "update the project profile", "save the architecture", "record the project stack".
argument-hint: ""
---

# iroha: project

Record the project's **current** tech profile as one row in the shared Projects DB.
This is iroha's "what the project IS now" layer — distinct from **Sessions** (what
happened each time) and **Decisions** (why it is the way it is). Updates are
**manual / engineer-judged**: run this when the stack is first established or changes
materially. Write Notion content in the user's conversation language.

## 1. Preconditions

```bash
L="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.ts"
bun "$L" get projects_ds_id      # empty -> tell the user to run /iroha:init, then stop
bun "$L" get container_page_id
bun "$L" get-state "$PWD"        # this project's State page id (link to it from the row, below)
```

## 2. Scan the repo and draft the profile (read the real stack, do not guess)

- **Languages / runtime** — file extensions, `package.json`, `go.mod`, `pyproject.toml`,
  `Cargo.toml`, `.tool-versions`, Dockerfiles.
- **Frameworks / key libraries** — the load-bearing dependencies from the manifest /
  lockfile (name the handful that matter, not the whole tree).
- **Dev tooling** — package manager, lint / format / test / typecheck (`biome.json`,
  eslint, ruff, `Makefile`, `package.json` scripts), pre-commit.
- **CI/CD** — `.github/workflows/*` or other CI config: the provider + what the pipeline
  actually does.
- **Architecture** — the component / data-flow shape, for a ```mermaid``` diagram.
- **Setup / onboarding** — the minimal "clone → run" steps.

## 3. Confirm with the engineer (manual gate)

Show the drafted profile and **ask the engineer to correct / approve** before writing.
This is intentionally not automatic — the human owns what counts as the canonical stack.

## 4. Write the row (create or replace — idempotent)

`notion-search` the Projects DB for this project's `Name`. If a row exists,
`notion-update-page` (`update_properties` + `replace_content`); else
`notion-create-pages` under `projects_ds_id`. Properties:
- `Name` = project name; `Languages` = a JSON array **string** (multi_select);
  `Frameworks` / `DevTools` / `CI` = plain rich_text; `Repo` = URL;
  `"date:Updated:start"` = today.

`content` = monochrome Notion-flavored Markdown (no emoji), like a Session page: a
header `<callout>` summary, a stack `<table>`, a ```mermaid``` architecture diagram, a
`## Setup` `<details>` toggle, and key conventions. **State _what_, not _why_** — for
the rationale, link to the Decisions DB; never re-explain decisions here. Icon
`https://www.notion.so/icons/cube_gray.svg`.

**Link to the project's current State** in the header callout — a localized "current state"
line linking the State page, e.g. `Current state: [State — <project>](<state_page_url>)` (write
the label in the user's conversation language; use the state page id from step 1; omit if none
yet). This is the
Projects↔State mutual link — Projects holds the *durable stack* and links to State's *live
status*, while State links back here for the stack. They stay **separate** pages on purpose
(this profile is manual / engineer-judged; State is rewritten every `/iroha:save-session`), so
do not merge them — just connect them.

**Wrap every file name / command / path in backticks — including inside `<table>` cells,
callouts, and the `CI` / `DevTools` / `Frameworks` properties** — so Notion does not
auto-linkify `.sh` / `.md` / `.json` names into bogus `http://…` URLs (a real defect found
while dogfooding: `selftest.sh` and `CLAUDE.md` rendered as `http://selftest.sh`). **Run the
composed content through `bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/link-lint.sh"` before
publishing and backtick anything it flags (it exits non-zero on a bare file/path token).** Reflect
the **current** stack read in step 2, not a remembered snapshot — re-running this skill is
how a stale field (e.g. a `CI` that now exists, a recall design that has since changed) gets
corrected, since `Updated` and the body are fully replaced on each write.

## 5. Report

The row URL, and note that cross-project recall (`/iroha:recall` over the Projects DB)
can now answer "other `<language>` projects?" / "projects using `<library>`?" — and gets
more useful as more projects are profiled.

## Notes

- This is the **cross-project layer**: `notion-search` over the Projects DB answers
  "how do our other Go projects do CI?" once several projects have a profile.
- Keep it current by re-running when the stack changes (a new lockfile / CI change is a
  good trigger). `/iroha:save-session` nudges you when it detects stack changes.
