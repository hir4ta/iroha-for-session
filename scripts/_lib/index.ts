// index.ts — local enumeration index for iroha memory (the completeness layer search lacks).
//
// On the Notion FREE plan, `query-data-sources` is paid, so the Decisions / Sessions DBs
// cannot be enumerated — only `notion-search` (semantic top-N) and `notion-fetch` (one page)
// work. That makes reliable dedup, supersede checks, and honest abstention impossible:
// you cannot reason about a set you cannot list. This keeps a tiny NDJSON index of KEYS ONLY
// (no content — Notion remains the single source of truth for content) so those operations
// see the COMPLETE set, not just search's top-N.
//
// Lives in the repo at <root>/.iroha/index.ndjson (committed, shared with the team like the
// State mirror). One JSON object per line:
//   {type, id, topic, status, date, title, project, text, supersedes}.
//   type    "decision" | "session"
//   id      the Notion page id (the upsert key)
//   topic   for decisions, the "<topic>" prefix of "<topic>: <choice>" (the dedup key)
//   status  "Active" | "Superseded" (decisions) / "Complete" | "WIP" | "Interrupted" (sessions)
//   supersedes  for decisions, the id of the immediate predecessor this decision REPLACED —
//           either the DASHED UUID (as the index stores ids) or the BARE 32-hex form (what
//           save-session's "<bare-old-id>" guidance produces); lineage comparisons normalize the
//           dashes, so both link. Empty -> the key is omitted. This makes the supersede LINEAGE
//           walkable offline: /iroha:history starts at the current Active decision and follows back.
//   text    a short SEARCH SNIPPET (decision rationale / session summary, ~160 chars) — the
//           lexical-recall key for search.ts. DERIVED (regenerated each save), NOT canonical.

import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";

export interface IndexRecord {
  type: string;
  id: string;
  topic: string;
  status: string;
  date: string;
  title: string;
  project: string;
  text: string;
  supersedes?: string;
}

export function indexPath(root: string): string {
  return join(root, ".iroha", "index.ndjson");
}

// Read + parse the index, skipping malformed lines (tolerant, like jq with 2>/dev/null — but it
// keeps lines AFTER a broken one too, where a streaming jq parse would stop).
export function indexRead(root: string): Record<string, unknown>[] {
  const f = indexPath(root);
  if (!existsSync(f)) return [];
  const out: Record<string, unknown>[] = [];
  for (const line of readFileSync(f, "utf8").split("\n")) {
    if (line.trim() === "") continue;
    try {
      out.push(JSON.parse(line) as Record<string, unknown>);
    } catch {
      // skip a truncated / malformed line rather than failing the whole read.
    }
  }
  return out;
}

function writeLines(root: string, lines: string[]): void {
  const f = indexPath(root);
  mkdirSync(dirname(f), { recursive: true });
  // Temp file MUST live on the same filesystem as the destination, else renameSync throws EXDEV
  // ("cross-device link not permitted") and the write is silently lost — the default Linux layout
  // (tmpfs /tmp, repo on another partition) hits exactly that. dirname(f) is the just-created target
  // dir, so the rename stays same-fs and truly atomic.
  const tmp = join(dirname(f), `.idx.${process.pid}.${Date.now()}.tmp`);
  writeFileSync(tmp, lines.length ? `${lines.join("\n")}\n` : "");
  renameSync(tmp, f);
}

// Upsert by id: drop any existing line with the same id, then append the new one (so a status
// change — e.g. Active -> Superseded — replaces in place rather than duplicating).
export function indexUpsert(
  root: string,
  type: string,
  id: string,
  topic: string,
  status: string,
  date: string,
  title = "",
  project = "",
  text = "",
  supersedes = "",
): void {
  const rec: IndexRecord = {
    type,
    id,
    topic,
    status,
    date,
    title,
    project,
    text,
  };
  if (supersedes !== "") rec.supersedes = supersedes;
  const kept = indexRead(root)
    .filter((r) => r.id !== id)
    .map((r) => JSON.stringify(r));
  kept.push(JSON.stringify(rec));
  writeLines(root, kept);
}

// ASCII-only downcase (matches jq's ascii_downcase — non-ASCII, e.g. Japanese, is left as-is).
function asciiDowncase(s: string): string {
  return s.replace(/[A-Z]/g, (c) => c.toLowerCase());
}

// Page ids appear DASHED (UUID — how Notion's API returns them and how the index stores them) or
// BARE (32-hex — what save-session's "<bare-old-id>" supersede guidance produces). Normalize to the
// bare form before comparing an id against a `supersedes` value, so the lineage links regardless of
// which form was written (the same normalization integrity.ts's State-link check already applies).
// Without it, a bare `supersedes` never matches a dashed record id and the chain/lineage silently
// dead-ends — a real dogfood defect.
export function bareId(s: string): string {
  return s.replace(/-/g, "");
}

// Matching decision lines for a topic (any status). The dedup/supersede key is the topic;
// case-insensitive on ASCII.
export function indexFindTopic(
  root: string,
  topic: string,
): Record<string, unknown>[] {
  const t = asciiDowncase(topic);
  return indexRead(root).filter(
    (r) => r.type === "decision" && asciiDowncase(String(r.topic ?? "")) === t,
  );
}

// The supersede LINEAGE starting at <id>, newest first: <id>, then the predecessor it replaced
// (via .supersedes), and so on. Bounded (a malformed cycle / long chain cannot loop forever).
export function indexChain(
  root: string,
  id: string,
): Record<string, unknown>[] {
  const recs = indexRead(root);
  const out: Record<string, unknown>[] = [];
  let cur = bareId(id);
  let n = 0;
  while (cur !== "" && n < 50) {
    const rec = recs.find(
      (r) => r.type === "decision" && bareId(String(r.id ?? "")) === cur,
    );
    if (!rec) break;
    out.push(rec);
    cur = typeof rec.supersedes === "string" ? bareId(rec.supersedes) : "";
    n += 1;
  }
  return out;
}

// All lines, optionally filtered by type. The completeness primitive audit uses to enumerate the
// full set (then reconcile each id against Notion), instead of trusting search's partial recall.
export function indexList(root: string, type = ""): Record<string, unknown>[] {
  const recs = indexRead(root);
  return type === "" ? recs : recs.filter((r) => r.type === type);
}

// True if a record with this id (optionally constrained to a type) is indexed. The membership
// primitive save-session §9 uses to confirm every decision it created is indexed — a typed
// replacement for `list | jq -r .id | grep -qF "<id>"`, which mis-handles an empty id and treats
// regex metacharacters in an id as a pattern (false matches / misses).
export function indexHas(root: string, id: string, type = ""): boolean {
  if (id === "") return false;
  return indexRead(root).some(
    (r) => r.id === id && (type === "" || r.type === type),
  );
}

// Active records, optionally of a type (decisions carry Status=Active). Replaces the per-skill
// `list | jq -c 'select(.status=="Active")'` filter with a typed enumeration.
export function indexActive(
  root: string,
  type = "",
): Record<string, unknown>[] {
  return indexRead(root).filter(
    (r) => r.status === "Active" && (type === "" || r.type === type),
  );
}

// Topics that have MORE THAN ONE Active decision — the duplicate-topic signal audit reports (two
// Active rows under one topic usually means one should be Superseded). Case-insensitive on ASCII
// (matching find-topic); each offending topic returned once, in first-seen original casing.
// Replaces audit's `list | jq -s 'group_by(.topic)|map(select(length>1))...'`.
export function indexDupTopics(root: string): string[] {
  const seen = new Map<string, { topic: string; count: number }>();
  for (const r of indexRead(root)) {
    if (r.type !== "decision" || r.status !== "Active") continue;
    const topic = String(r.topic ?? "");
    if (topic === "") continue;
    const key = asciiDowncase(topic);
    const e = seen.get(key);
    if (e) e.count += 1;
    else seen.set(key, { topic, count: 1 });
  }
  return [...seen.values()].filter((e) => e.count > 1).map((e) => e.topic);
}

// Records whose date falls within [start, end] INCLUSIVE (ISO YYYY-MM-DD strings compare
// lexically), sorted NEWEST FIRST. Optional type and status filters. A record with an empty /
// too-short date is skipped (it cannot be placed in a period). Replaces digest's per-skill `jq`
// range+status+sort pipe in one typed call.
export function indexInRange(
  root: string,
  start: string,
  end: string,
  type = "",
  status = "",
): Record<string, unknown>[] {
  return indexRead(root)
    .filter((r) => {
      if (type !== "" && r.type !== type) return false;
      if (status !== "" && r.status !== status) return false;
      const d = String(r.date ?? "");
      if (d.length < 10) return false;
      return d >= start && d <= end;
    })
    .sort((a, b) => {
      const da = String(a.date ?? "");
      const db = String(b.date ?? "");
      return da < db ? 1 : da > db ? -1 : 0;
    });
}

// CLI: usable from skills as `bun index.ts <cmd> ...`. Each case returns the process exit code.
function runCli(): number {
  const [cmd, ...rest] = process.argv.slice(2);
  const emit = (recs: Record<string, unknown>[]) => {
    for (const r of recs) process.stdout.write(`${JSON.stringify(r)}\n`);
  };
  switch (cmd) {
    case "path":
      process.stdout.write(indexPath(rest[0] ?? ""));
      return 0;
    case "upsert":
      indexUpsert(
        rest[0] ?? "",
        rest[1] ?? "",
        rest[2] ?? "",
        rest[3] ?? "",
        rest[4] ?? "",
        rest[5] ?? "",
        rest[6] ?? "",
        rest[7] ?? "",
        rest[8] ?? "",
        rest[9] ?? "",
      );
      return 0;
    case "find-topic":
      emit(indexFindTopic(rest[0] ?? "", rest[1] ?? ""));
      return 0;
    case "chain":
      emit(indexChain(rest[0] ?? "", rest[1] ?? ""));
      return 0;
    case "list":
      emit(indexList(rest[0] ?? "", rest[1] ?? ""));
      return 0;
    case "has":
      // has <root> <type> <id>  (type "" = any) -> exit 0 if indexed, 1 if absent
      return indexHas(rest[0] ?? "", rest[2] ?? "", rest[1] ?? "") ? 0 : 1;
    case "active":
      // active <root> [type] -> Active records as NDJSON
      emit(indexActive(rest[0] ?? "", rest[1] ?? ""));
      return 0;
    case "dup-topics":
      // dup-topics <root> -> one topic per line with >1 Active decision
      for (const t of indexDupTopics(rest[0] ?? ""))
        process.stdout.write(`${t}\n`);
      return 0;
    case "in-range":
      // in-range <root> <start> <end> [type] [status] -> records in [start,end], newest first
      emit(
        indexInRange(
          rest[0] ?? "",
          rest[1] ?? "",
          rest[2] ?? "",
          rest[3] ?? "",
          rest[4] ?? "",
        ),
      );
      return 0;
    default:
      process.stderr.write(
        "usage: index.ts <path|upsert|find-topic|chain|list|has|active|dup-topics|in-range> ...\n",
      );
      return 2;
  }
}

if (import.meta.main) process.exit(runCli());
