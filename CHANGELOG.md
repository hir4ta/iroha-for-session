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
- **Proactive local recall** (`hooks/recall-inject.sh`, a `UserPromptSubmit` hook +
  `scripts/_lib/search.sh`): on every substantive prompt, a *cheap, always-on* pure-`jq`
  **BM25** search over the keys-only index surfaces the most relevant past decisions — **no
  LLM, no network, offline, instant**. Deep semantic recall stays in the explicit
  `/iroha:recall` (Adaptive-RAG two-stage routing: cheap local first, escalate only when
  needed). The search tokenizer is **CJK-aware** (Japanese runs are split into 2-grams, so
  lexical matching works on non-space-delimited text) and weights decisions over sessions /
  Active over Superseded. Fully fail-safe — opt-out (`IROHA_RECALL_DISABLE=1`), consent gate
  (`recall_enabled`, armed by `/iroha:init`, off by default so a fresh install costs nothing),
  prompt gate (short / slash / system pseudo-prompts), per-prompt cache, and abstain-to-nothing
  below the relevance floor (`IROHA_RECALL_MINSCORE`, default 1.2). Verify with
  `recall-inject.sh --selfcheck`.
  - *Replaces* the earlier (unreleased) per-prompt headless `claude -p` recall — an
    anti-pattern (no SOTA agent-memory system runs a generative LLM per query): it cost
    latency + tokens + rate contention on every prompt, depended on `claude` + a `timeout`
    binary (macOS coreutils), and was observed firing on non-user turns. The local stage
    removes all of that.
- **Index search snippet**: the local index now carries a short, derived `text` field
  (rationale / summary condensed to ≤160 chars) so BM25 can match a prompt against the *reason*
  a decision was made, not just its title. It is regenerated on every save (like an embedding),
  so Notion stays the single source of truth and it cannot drift.
- **Recall quality eval harness** (`tests/recall-eval.sh`, `npm run test:recall`, in CI): a
  golden set of realistic prompts → expected decision, scoring **Recall@k / MRR / abstention**
  on the real index — so "does the memory get more useful as it grows?" is a measured curve and
  recall regressions are caught (currently Recall@3 = 100%, MRR = 0.94, abstention = 100%).
- **Write-time dedup guard** in `save-session`: consults the index before creating a Decision,
  blocks granularity pollution at the source, and supersedes/merges near-dups — now also via a
  local BM25 near-duplicate check that catches an equivalent decision under a *different* topic
  string (mem0-style consolidation), which exact topic-prefix matching misses.
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
