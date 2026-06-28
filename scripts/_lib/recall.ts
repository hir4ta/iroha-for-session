// recall.ts — the shared LOCAL recall used by the proactive hooks (recall-inject, check-inject).
//
// ONE always-on tier: a dependency-free BM25 over the keys-only index (scripts/_lib/search.ts). No
// LLM, no network, no model — instant and offline, which is exactly what a per-prompt UserPromptSubmit
// hook needs. A per-prompt LLM/agent recall was tried and removed (cost / latency / rate-competition
// with the live session / misfire on non-user turns), so this stage stays purely lexical. Deep
// SEMANTIC recall is the explicit /iroha:recall skill (Notion's own free semantic search over the
// canonical data), NOT a local embedding/reranker model tier.
//
// Output: ranked SearchHit records, best first (advisory; an empty list = honest silence).

import { type SearchHit, search } from "./search.ts";

// recallLocal(root, query, topn) -> BM25-ranked records. search() reads the index and returns [] for
// an empty index/query, so this is a thin, centralizing wrapper (one place owns the score floor).
export function recallLocal(
  root: string,
  query: string,
  topn = 3,
): SearchHit[] {
  const minscore = Number(process.env.IROHA_RECALL_MINSCORE ?? "1.2");
  return search(root, query, "", topn, minscore);
}

// CLI: `bun recall.ts <root> <query> [topn]`. One compact JSON hit per line.
if (import.meta.main) {
  const [root, query, topn] = process.argv.slice(2);
  const hits = recallLocal(root ?? "", query ?? "", topn ? Number(topn) : 3);
  for (const h of hits) process.stdout.write(`${JSON.stringify(h)}\n`);
}
