# Contributing

Thanks for your interest in iroha for Notion. It's a small, pure-bash Claude Code
plugin — easy to run locally.

## Dev setup

```bash
git clone https://github.com/hir4ta/iroha-for-notion
cd iroha-for-notion
npm install                                   # biome (JSON lint/format)
pre-commit install && pre-commit install --hook-type pre-push
```

You'll also want `jq` and `shellcheck` on your PATH (the bash scripts and tests use them).

## Tests & checks

`tests/selftest.sh` is the **behavioral oracle** — pure bash, no bats. If you change
extraction or hook behavior, update it.

```bash
npm run test:bash     # bash tests/selftest.sh  (0 = all pass)
npm run lint          # biome check .
shellcheck scripts/**/*.sh hooks/*.sh tests/*.sh
```

CI runs the same checks on every push and PR.

## Conventions

- **Notion is the only integration** — go through the Notion MCP, never an API token
  (see [`.claude/rules/architecture.md`](.claude/rules/architecture.md) for the
  invariants).
- **Deterministic extraction is bash; intelligence is Claude** (inside the skills). Do
  not call any model API from code.
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
