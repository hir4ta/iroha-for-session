// integrity.ts — deterministic, OFFLINE self-monitoring of the iroha memory substrate.
//
// A living memory's trust depends on its enumeration index being complete and internally
// consistent. Dogfooding surfaced silent rot classes the prior self-checks missed: the local
// keys-only index drifting out of sync with Notion, and the State mirror advancing past the
// newest saved Session (a memory hole). This catches everything checkable OFFLINE from the
// committed repo files, so it can run in selftest + CI + pre-push and a corrupt substrate can
// never reach green. The complementary network check (row count vs the Notion DB) lives in audit.
//
// Checks (over <root>/.iroha/{index.ndjson,state.md}; no network):
//   1. index.ndjson parses — every non-empty line is valid JSON carrying at least {type,id}.
//   2. no duplicate ids (the upsert key) — a dup means an upsert failed to replace.
//   3. no two Active decisions sharing a <topic> — the duplicate-Active rot (degrades recall most).
//   4. State <-> index linkage — every page id linked from State's "## Recent sessions" block
//      resolves to a session row in the index (else State points at work never indexed/saved).
//   5. supersede lineage — every decision's `supersedes` points to an id that exists in the index.

import { existsSync, readFileSync } from "node:fs";
import { stateMdPath } from "./config.ts";
import { bareId, indexPath } from "./index.ts";

// integrity(root) -> issue strings (empty list = clean).
export function integrity(root: string): string[] {
  const idx = indexPath(root);
  const issues: string[] = [];
  // No index yet (fresh project) is not a failure — there is simply nothing to check.
  if (!existsSync(idx)) return issues;

  // Parse line-by-line: count malformed (invalid JSON OR missing type/id), collect valid records.
  let malformed = 0;
  const records: Record<string, unknown>[] = [];
  for (const line of readFileSync(idx, "utf8").split("\n")) {
    if (line.trim() === "") continue;
    let rec: Record<string, unknown>;
    try {
      rec = JSON.parse(line) as Record<string, unknown>;
    } catch {
      malformed += 1;
      continue;
    }
    if (!rec.type || !rec.id) {
      malformed += 1;
      continue;
    }
    records.push(rec);
  }

  // 1. Malformed lines.
  if (malformed > 0) {
    issues.push(
      `integrity: ${malformed} malformed index line(s) (must be JSON with type+id) in ${idx}`,
    );
  }

  // 2. Duplicate ids.
  const idCounts = new Map<string, number>();
  for (const r of records) {
    if (typeof r.id === "string")
      idCounts.set(r.id, (idCounts.get(r.id) ?? 0) + 1);
  }
  const dupIds = [...idCounts.entries()]
    .filter(([, n]) => n > 1)
    .map(([id]) => id)
    .sort();
  if (dupIds.length > 0) {
    issues.push(`integrity: duplicate index id(s): ${dupIds.join(" ")} `);
  }

  // 3. Duplicate Active decision topics.
  const topicCounts = new Map<string, number>();
  for (const r of records) {
    if (
      r.type === "decision" &&
      r.status === "Active" &&
      typeof r.topic === "string"
    ) {
      topicCounts.set(r.topic, (topicCounts.get(r.topic) ?? 0) + 1);
    }
  }
  const dupTopics = [...topicCounts.entries()]
    .filter(([, n]) => n > 1)
    .map(([t]) => t);
  if (dupTopics.length > 0) {
    issues.push(
      `integrity: duplicate Active decision topic(s) (one should be Superseded): ${dupTopics.join(" ")} `,
    );
  }

  // 4. State -> index linkage. Only ids from the "## Recent sessions" block (the Decisions-DB link
  //    in "## Decisions" must NOT be matched), normalized to bare 32-hex, must exist as session ids.
  const state = stateMdPath(root);
  if (existsSync(state)) {
    const linked = new Set<string>();
    let inBlock = false;
    for (const line of readFileSync(state, "utf8").split("\n")) {
      if (/^## Recent sessions/.test(line)) {
        inBlock = true;
        continue;
      }
      if (/^## /.test(line)) inBlock = false;
      if (inBlock) {
        // Page ids appear either dashed (UUID) or bare (32-hex) depending on what the LLM pasted as
        // the link; match BOTH and normalize to bare. A bare /[0-9a-f]{32}/ alone silently misses a
        // dashed UUID (max 8-hex run between dashes) — the guard then no-ops instead of catching a
        // State that points at unsaved work.
        for (const m of line.matchAll(
          /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g,
        ))
          linked.add(m[0].replace(/-/g, ""));
        for (const m of line.matchAll(/[0-9a-f]{32}/g)) linked.add(m[0]);
      }
    }
    if (linked.size > 0) {
      const sessions = new Set(
        records
          .filter((r) => r.type === "session" && typeof r.id === "string")
          .map((r) => (r.id as string).replace(/-/g, "")),
      );
      const dangling = [...linked].filter((id) => !sessions.has(id)).sort();
      if (dangling.length > 0) {
        issues.push(
          `integrity: State 'Recent sessions' links a session missing from the index (State ahead of saved sessions): ${dangling.join(" ")} `,
        );
      }
    }
  }

  // 5. Supersede lineage — every `supersedes` must point to an id that exists in the index.
  //    Normalize BOTH sides to bare (strip dashes): the index stores dashed UUIDs but a `supersedes`
  //    may be written bare (save-session's "<bare-old-id>" guidance), and a raw === would then falsely
  //    flag a real lineage as broken. Report the original supersedes string so the message is legible.
  const allIds = new Set(
    records
      .filter((r) => typeof r.id === "string")
      .map((r) => bareId(r.id as string)),
  );
  const danglingSup = [
    ...new Set(
      records
        .filter(
          (r) =>
            r.type === "decision" &&
            typeof r.supersedes === "string" &&
            r.supersedes !== "",
        )
        .map((r) => r.supersedes as string),
    ),
  ]
    .filter((id) => !allIds.has(bareId(id)))
    .sort();
  if (danglingSup.length > 0) {
    issues.push(
      `integrity: decision 'supersedes' points to an id missing from the index (broken lineage): ${danglingSup.join(" ")} `,
    );
  }

  return issues;
}

// CLI: usable from skills/CI as `bun integrity.ts <repo-root>`. exit 0 = clean; exit 1 = issues.
if (import.meta.main) {
  const issues = integrity(process.argv[2] ?? process.cwd());
  for (const line of issues) console.log(line);
  process.exit(issues.length === 0 ? 0 : 1);
}
