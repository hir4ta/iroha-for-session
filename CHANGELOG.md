# Changelog

All notable changes to iroha are documented here. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow SemVer.

## [Unreleased]

### Added

- **Local enumeration index** (`scripts/_lib/index.sh`, repo-committed `.iroha/index.ndjson`):
  a keys-only record (id / topic / status / date — no content) of every decision and
  session. On the Notion free plan `query-data-sources` is paid, so the DBs cannot be
  enumerated; this index lets dedup, supersede, and audit reason over the *complete* set
  instead of `notion-search`'s top-N. Notion stays the single source of truth for content.
- **Enforced just-in-time recall** (`hooks/recall-inject.sh`, a `UserPromptSubmit` hook):
  spawns one bounded, read-only headless `claude -p` that searches the project's memory for
  decisions relevant to the prompt and injects the top hits. Fully fail-safe — recursion
  guard, prompt gate, per-prompt cache, hard timeout, and degrade-to-nothing on any failure
  (no CLI / no `timeout` / not initialized / error). **Off by default** for distribution
  safety — it stays idle until `/iroha:init` sets `recall_enabled` (so a fresh install pays
  no per-prompt cost; consent is bound to actually setting iroha up). Force-disable any time
  with `IROHA_RECALL_DISABLE=1`; tune with `IROHA_RECALL_TIMEOUT` (default 20s). Verify the
  headless path with `recall-inject.sh --selfcheck` (offline) or `--selfcheck --live` (one
  real claude + Notion MCP round-trip).
- **Write-time dedup guard** in `save-session`: consults the index before creating a
  Decision, blocks granularity pollution at the source, and supersedes/merges near-dups.
- Full chat is now stored as a **child page** of the Session (paged out, real and complete)
  — never an inline placeholder.

### Changed

- `recall` is now **hybrid + ranked**: it merges `notion-search` (content relevance) with
  the complete local index (every row, instantly current), ranks by relevance + recency +
  importance, leads with the load-bearing hit, and abstains honestly when neither has a
  relevant entry. The index cross-check also surfaces decisions saved moments ago that
  `notion-search` has not indexed yet (Notion search has write-lag).
- `audit` enumeration is now **complete** via the index (duplicate-Active and orphan checks
  are exhaustive, not heuristic).
- Failures are recorded as first-class, recallable entries (symptom → cause → fix) so a
  future session surfaces a dead-end before repeating it.
- **Language boundary tightened**: all distribution code/templates are English; `init`
  localizes the materialized `Type` option labels and the entry-point guide to the user's
  conversation language, while structural keys (property names, `Status`, `Project`,
  `Languages`) stay English.

### Fixed

- A Session's `Full chat` toggle could hold a fabricated placeholder ("…full chat
  continues…") instead of the real chat; now structurally prevented, and the one affected
  page was repaired with its real 103-turn chat.
- Demoted a granularity-polluting decision (a display tweak) out of the canonical Decisions
  DB to `Status = Superseded`.

## [0.2.0] — 2026-06-25

### Added

- `extract.sh` gains four deterministic views: `prompts` (the human's real messages),
  `stats` (turns / tool calls / files / duration), `tools` (per-tool tally), and `chat`
  (a cleaned, per-turn-capped full transcript).
- Session pages now carry a `## Metrics` dashboard, plus `Tools` and `Full chat` audit
  toggles under `## Details`.
- `/iroha:digest` — roll a period (week / month / explicit range) into one digest page:
  aggregate metrics, the decisions made, a session list, still-open items, and a timeline.
- `/iroha:audit` — health-check the memory (duplicate Active decisions, State drift,
  stale carry-overs, orphaned decisions, structure drift) and optionally apply safe,
  reversible fixes with `--fix`.
- SessionStart hook surfaces a carried-over open-item count banner.
- SessionStart hook re-injects the **current session's conversation** (your prompts +
  a capped recent tail, read from the on-disk transcript) after `/compact` or
  auto-compact (`source=compact`), so the thread survives compaction. Line-based caps
  keep multibyte text from being split mid-character.

### Changed

- Chat highlights now **anchor their *You* lines to the deterministic `prompts`
  output** — the model no longer reconstructs (and can no longer fabricate) what you
  said, and is instructed not to inflate success.
- SessionStart hook wrapper text is now English (it is distribution code); the injected
  State body stays in the user's conversation language.
- `save-session` documents the exact property-map types (`is_datetime` is a JSON number;
  a string returns a 400) and a Decision-promotion bar (architecture / dependency /
  process only — display/naming tweaks stay in the Session table).
- `recall` guards against stale Session summaries (trust the newest Session / State /
  Active Decisions, never echo an outdated summary as current).
- Docs realigned to the 3-DB model and to MCP-only writes (the testing rule no longer
  references a non-existent HTTP-builder function).

### Fixed

- `architecture.md` and assorted docs still described a 2-DB model; corrected to 3 DBs.

## [0.1.0]

### Added

- Initial release: `/iroha:init`, `/iroha:save-session`, `/iroha:recall`,
  `/iroha:project`; pure-bash deterministic extraction; SessionStart State injection;
  Notion MCP (OAuth) integration with no API token; pure-bash behavioral selftest.
