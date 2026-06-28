// gh.ts — bounded, FAIL-SOFT GitHub PR lookup for the Session↔PR URL link (save-session).
//
// iroha records each session's PR so a Session row links to the PR that shipped its work (URL
// property, not a relation — same invariant as Session↔Decision). This is the ONLY network-touching
// extraction helper, kept OUT of extract.ts on purpose: extract.ts is read-only and pure-local (no
// network, must never hang or fail a save), so the one `gh` call lives here, isolated and bounded.
//
// Discipline (CI-discipline rule): a SINGLE `gh pr list` with a HARD timeout and NO retry loop —
// worst case is one bounded call, far under any save budget. Every failure mode degrades to [] and
// never throws or blocks the save: `gh` not installed, not authenticated, offline, non-zero exit,
// timeout, or simply no PR for the branch. A missing PR link is fine; a hung/failed save is not.
//
// stdout = the requested PRs as NDJSON (one per line); diagnostics (none needed) would go to stderr.

import { spawnSync } from "node:child_process";

export interface Pr {
  number: number;
  url: string;
  title: string;
  state: string; // lower-cased: "open" | "merged" | "closed"
}

// parseGhPrs(stdout) -> Pr[] : pure parse of `gh pr list --json number,url,title,state` output.
// Tolerant (returns [] on empty / non-array / invalid JSON) and orders OPEN first, then newest
// (highest number) — so the caller can take prs[0] as the primary PR to put on the Session row.
export function parseGhPrs(stdout: string): Pr[] {
  let raw: unknown;
  try {
    raw = JSON.parse(stdout);
  } catch {
    return [];
  }
  if (!Array.isArray(raw)) return [];
  const prs: Pr[] = raw
    .filter((p): p is Record<string, unknown> => !!p && typeof p === "object")
    .map((p) => ({
      number: typeof p.number === "number" ? p.number : 0,
      url: typeof p.url === "string" ? p.url : "",
      title: typeof p.title === "string" ? p.title : "",
      state: typeof p.state === "string" ? p.state.toLowerCase() : "",
    }))
    .filter((p) => p.url !== "");
  const rank = (s: string) => (s === "open" ? 0 : 1);
  return prs.sort(
    (a, b) => rank(a.state) - rank(b.state) || b.number - a.number,
  );
}

// prsForBranch(branch, timeoutMs) -> Pr[] : run `gh pr list --head <branch>` with a hard timeout,
// FAIL-SOFT to [] on any failure. The binary is overridable via IROHA_GH_BIN so tests can point at a
// fixture stub without a real `gh` / network. Never throws — the save must not depend on GitHub.
export function prsForBranch(branch: string, timeoutMs = 8000): Pr[] {
  if (!branch) return [];
  const bin = process.env.IROHA_GH_BIN || "gh";
  let r: ReturnType<typeof spawnSync>;
  try {
    r = spawnSync(
      bin,
      [
        "pr",
        "list",
        "--head",
        branch,
        "--state",
        "all",
        "--limit",
        "5",
        "--json",
        "number,url,title,state",
      ],
      { encoding: "utf8", timeout: timeoutMs },
    );
  } catch {
    return []; // spawn itself threw (should not, but never let it bubble into the save)
  }
  // r.error => binary missing (ENOENT) or killed by timeout; r.status !== 0 => unauth / not-a-repo /
  // any gh error. Either way there is no trustworthy PR list, so degrade to silence.
  if (r.error || r.status !== 0) return [];
  return parseGhPrs(typeof r.stdout === "string" ? r.stdout : "");
}

// CLI: `bun gh.ts pr <branch>` -> one PR JSON per line (NDJSON), or no output when none / on any
// failure (fail-soft). The save-session skill runs this and links prs[0].url onto the Session row.
if (import.meta.main) {
  const [cmd, branch] = process.argv.slice(2);
  if (cmd !== "pr" || !branch) {
    process.stderr.write("usage: gh.ts pr <branch>\n");
    process.exit(2);
  }
  for (const pr of prsForBranch(branch))
    process.stdout.write(`${JSON.stringify(pr)}\n`);
}
