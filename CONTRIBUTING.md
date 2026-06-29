# Contributing

Thanks for your interest in iroha-for-memory. It's a small Claude Code plugin
(Bun + TypeScript) — easy to run locally.

## Dev setup

```bash
git clone https://github.com/hir4ta/iroha-for-memory
cd iroha-for-memory
bun install                                   # dev tools: biome, typescript, fast-check
pre-commit install && pre-commit install --hook-type pre-push
```

Everything runs on [Bun](https://bun.sh) — `bun X.ts` executes TypeScript directly, no
build step. No `jq` / `shellcheck` needed (the former bash scripts are gone).

## Tests & checks

`bun test` (`tests/*.test.ts`) is the **behavioral oracle**. If you change extraction or
hook behavior, update it.

```bash
bun test              # behavioral oracle (0 = all pass)
bunx tsc --noEmit     # types
bun run lint          # biome check .
```

Quality evals are separate (and slower): `bun tests/recall-eval.ts` (local BM25 recall) /
`bun tests/recall-scale.ts` (scale). Both run against a frozen fixture corpus
(`tests/fixtures/recall-corpus`), so a workspace re-save never drifts them. See
[`.claude/rules/testing.md`](.claude/rules/testing.md) for the full set.

CI runs the same checks on every push and PR.

## Conventions

- **Notion is the only integration** — go through the Notion MCP, never an API token
  (see [`.claude/rules/architecture.md`](.claude/rules/architecture.md) for the
  invariants).
- **Deterministic extraction is TypeScript; intelligence is Claude** (inside the skills).
  Do not call any model API from code.
- **Distributed files** (scripts, `SKILL.md`, manifests) are in **English**.
- **Commits**: [Conventional Commits](https://www.conventionalcommits.org/), one-line
  subject, imperative mood (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `test:`,
  `ci:`).
- Keep secrets out of the repo (`gitleaks` runs in pre-commit and CI).

## Releasing

Releases are tag-driven. Bump the version in `package.json` and
`.claude-plugin/plugin.json`, then push a `v*` tag:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

That triggers [`.github/workflows/release.yml`](.github/workflows/release.yml), which
creates the GitHub release with auto-generated notes.

## Reporting issues

Open a GitHub issue with steps to reproduce. For security, see [`SECURITY.md`](SECURITY.md).
