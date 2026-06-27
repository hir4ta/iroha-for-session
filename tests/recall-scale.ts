// recall-scale.ts — proves local BM25 recall (scripts/_lib/search.ts) and the enumeration index
// still behave at "hundreds of sessions" scale, retiring the "does recall hold up as the memory
// grows?" risk with a MEASURED test instead of a vibe.
//
// It proves four scale-sensitive properties on a synthetic large corpus (N≈320: a few known needles
// among hundreds of plausible distractors that share filler vocabulary):
//   1. ranking      — each needle's paraphrase query surfaces THAT needle in the top-K, above the
//                     production floor, despite 300+ competing rows (BM25 idf keeps a rare on-topic
//                     term outranking common filler);
//   2. abstention   — an unrelated query still injects nothing (no false positive at scale);
//   3. enumeration  — index list returns the COMPLETE set;
//   4. latency      — a full search finishes within the UserPromptSubmit hook timeout.
// Run: bun tests/recall-scale.ts; echo $?   (0 = scale thresholds met)

import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { indexList } from "../scripts/_lib/index.ts";
import { search } from "../scripts/_lib/search.ts";

const out = (s: string) => process.stdout.write(`${s}\n`);

const K = 3;
const MINSCORE = Number(process.env.IROHA_RECALL_MINSCORE ?? "1.2"); // production floor
const TIMEOUT_S = 5; // the UserPromptSubmit hook timeout (hooks/hooks.json)
const DISTRACTORS = 315; // plausible-but-irrelevant rows surrounding the needles

const root = mkdtempSync(join(tmpdir(), "iroha-scale-"));
mkdirSync(join(root, ".iroha"), { recursive: true });
const idx = join(root, ".iroha", "index.ndjson");

// 315 distractor decisions sharing filler vocab (実装/調整/テスト). They must NOT outrank a needle
// whose distinctive terms (OAuth, relation, BM25, …) are rare across the corpus and so carry high idf.
const lines: string[] = [];
for (let i = 1; i <= DISTRACTORS; i++) {
  lines.push(
    `{"type":"decision","id":"dec-${i}","topic":"機能${i}","status":"Active","date":"2026-01-01","title":"機能${i}: 実装と調整","project":"scaletest","text":"機能${i} の実装・調整・テストを行った汎用的な作業ログ"}`,
  );
}
// 5 known needles with distinctive terms + the paraphrase a developer would actually type.
lines.push(
  '{"type":"decision","id":"ndl-auth","topic":"認証方式","status":"Active","date":"2026-06-25","title":"認証方式: OAuth一本","project":"scaletest","text":"API トークンを持たず Notion MCP の OAuth で認証を一本化する"}',
  '{"type":"decision","id":"ndl-link","topic":"連結方式","status":"Active","date":"2026-06-25","title":"連結方式: URLプロパティ","project":"scaletest","text":"relation は書き込みバグがあるため URL プロパティでページを連結する"}',
  '{"type":"decision","id":"ndl-recall","topic":"検索方式","status":"Active","date":"2026-06-25","title":"検索方式: ローカルBM25","project":"scaletest","text":"毎回の LLM 呼び出しを避けローカルの BM25 で関連を先出しする"}',
  '{"type":"session","id":"ndl-compact","topic":"","status":"Complete","date":"2026-06-25","title":"2026-06-25 — 圧縮復帰","project":"scaletest","text":"compact の後に会話を transcript から再注入してスレッドを復元する"}',
  '{"type":"decision","id":"ndl-extract","topic":"抽出方式","status":"Active","date":"2026-06-25","title":"抽出方式: pure bash","project":"scaletest","text":"決定論抽出は bash で行い知性は Claude が担う"}',
);
writeFileSync(idx, `${lines.join("\n")}\n`);

const total = lines.length;
let pass = 0;
let fail = 0;
out(
  `=== recall-scale (N=${total} rows, Recall@${K}, MINSCORE=${MINSCORE}, timeout=${TIMEOUT_S}s) ===`,
);

function checkNeedle(q: string, want: string) {
  const rank =
    search(root, q, "", K, MINSCORE)
      .map((h) => h.id)
      .indexOf(want) + 1;
  if (rank > 0) {
    out(`  PASS  needle "${q}" -> rank ${rank}`);
    pass += 1;
  } else {
    out(`  FAIL  needle "${q}" -> ${want} not in top${K} among ${total} rows`);
    fail += 1;
  }
}

checkNeedle("認証にトークンは必要か", "ndl-auth");
checkNeedle("ページの連結にrelationを使うべきか", "ndl-link");
checkNeedle("関連の先出しはどう実装する", "ndl-recall");
checkNeedle("compactした後に会話を戻したい", "ndl-compact");
checkNeedle("抽出はbashとClaudeどちらでやる", "ndl-extract");

// abstention at scale: an unrelated query must inject nothing.
const abs = search(
  root,
  "deploy the kubernetes cluster with terraform on aws",
  "",
  K,
  MINSCORE,
);
if (abs.length === 0) {
  out("  PASS  abstain on unrelated query");
  pass += 1;
} else {
  out(`  FAIL  abstain leaked: ${abs[0]?.id}`);
  fail += 1;
}

// enumeration completeness at scale: index list returns every row.
const listed = indexList(root).length;
if (listed === total) {
  out(`  PASS  enumeration complete (${listed}/${total})`);
  pass += 1;
} else {
  out(`  FAIL  enumeration dropped rows (${listed}/${total})`);
  fail += 1;
}

// latency: a full search must finish within the hook timeout even at scale.
const t0 = Date.now();
search(root, "認証 連結 検索 抽出 圧縮 機能", "", K, MINSCORE);
const el = Math.floor((Date.now() - t0) / 1000);
if (el < TIMEOUT_S) {
  out(`  PASS  search latency ${el}s < ${TIMEOUT_S}s (hook timeout)`);
  pass += 1;
} else {
  out(
    `  FAIL  search latency ${el}s >= ${TIMEOUT_S}s (would time out the hook)`,
  );
  fail += 1;
}

rmSync(root, { recursive: true, force: true });
out(`--- result: ${pass} passed, ${fail} failed ---`);
process.exit(fail === 0 ? 0 : 1);
