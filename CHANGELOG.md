# Changelog

All notable changes to iroha are documented here. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow SemVer.

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
