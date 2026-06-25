# Security Policy

## Security model

iroha is designed to hold **no secrets**:

- Notion authentication is the **Notion MCP's OAuth** connection — there is **no API
  token** stored or required.
- The only state cached locally is **non-secret ids** (Notion page / database ids) in
  `config.json`, plus a small State mirror committed to your repo (`.iroha/state.md`).
- `gitleaks` runs in pre-commit and in CI to keep credentials out of the repository.
- The plugin never executes a remote model API from code; all intelligence happens
  inside Claude Code skills.

When iroha writes a session to Notion, it omits anything that looks like a secret. Still,
treat your Notion workspace as the source of truth and review what you save.

## Reporting a vulnerability

Please report security issues privately via GitHub's
**[Security Advisories](https://github.com/hir4ta/iroha-for-notion/security/advisories/new)**
rather than a public issue. We'll acknowledge and respond as quickly as we can.

## Supported versions

This project is pre-1.0; only the latest `main` is supported.
