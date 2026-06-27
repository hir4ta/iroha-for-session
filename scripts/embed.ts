// embed.ts — local, offline DENSE retrieval: the semantic candidate generator for hybrid recall.
//
// Why this exists. The cheap BM25 first stage (scripts/_lib/search.ts) and the cross-encoder
// reranker (scripts/rerank.ts) share one blind spot: the reranker can only re-order what BM25
// already surfaced. When the right decision shares little surface vocabulary with the prompt
// ("リコールの設計方針はどうする" vs a decision titled "リコール: hybrid(検索+index)"), BM25 never
// puts it in the candidate shortlist, so the reranker cannot rescue it (measured: the two
// recall-eval MISSes are candidate-GENERATION misses, not ranking misses). A dense bi-encoder
// embeds query and decisions into one vector space, so a semantic near-match enters the candidate
// pool even with zero lexical overlap. Hybrid recall then reranks (BM25 ∪ dense) candidates —
// closing the gap the reranker alone cannot.
//
// Opt-in contract. It adds the @huggingface/transformers dep + a local embedding model, so it is
// strictly OPT-IN. A fresh install pays nothing and keeps the dependency-free BM25 advisory
// behavior. Runs in-process under Bun (transformers v4 supports Bun) — NO node subprocess, NO API
// token, NO network at query time (the model is local and cached); the broken invariant is "zero
// deps", not "no token / offline". The heavy dep is imported via a VARIABLE specifier so a default
// install (dep uninstalled) still typechecks: tsc cannot resolve a non-literal import and leaves it
// `any`, keeping embed.ts inside strict tsc without forcing the dep into the shipped package.json.
//
// Doc embeddings are cached per-machine (keyed by a hash of each doc's embedding input), so
// re-embedding the stable corpus is incremental; only the query is embedded fresh each call.

import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { dirname } from "node:path";

export interface Doc {
  id: string;
  text: string;
}
export interface Scored {
  id: string;
  score: number;
}

// Minimal shape of the bits of @huggingface/transformers we use (it ships no types we depend on).
type Extractor = (
  text: string,
  opts: { pooling: string; normalize: boolean },
) => Promise<{ data: ArrayLike<number> }>;
type TransformersModule = {
  pipeline: (
    task: string,
    model: string,
    opts: { dtype: string },
  ) => Promise<Extractor>;
  env: { cacheDir?: string; allowRemoteModels?: boolean };
};

// Model is per-user and cached (survives plugin reinstall), like config.json. Default to a small,
// strong multilingual (incl. Japanese) sentence embedder. e5 models expect the "query: "/"passage: "
// instruction prefixes; override to "" for a model that does not use them.
const MODEL = process.env.IROHA_EMBED_MODEL || "Xenova/multilingual-e5-small";
const DTYPE = process.env.IROHA_EMBED_DTYPE || "q8";
const Q_PREFIX = process.env.IROHA_EMBED_QUERY_PREFIX ?? "query: ";
const P_PREFIX = process.env.IROHA_EMBED_PASSAGE_PREFIX ?? "passage: ";
// Variable specifier (not a string literal) so tsc cannot resolve it: the heavy dep stays optional
// and a default install (dep absent) still typechecks. The dynamic import is `any` either way.
const TRANSFORMERS = "@huggingface/transformers";

function dot(a: number[], b: number[]): number {
  let s = 0;
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) s += (a[i] as number) * (b[i] as number);
  return s;
}
function keyOf(text: string): string {
  return createHash("sha256").update(`${MODEL} ${text}`).digest("hex");
}

// denseRank — embed query + docs, return cosine-desc candidates (<= topk). THROWS when the runtime
// or model is unavailable (the dep is not installed, or the cached model fails to load); the caller
// (recall.ts) catches and falls back to BM25-only candidates. Returns [] for an empty query/corpus.
export async function denseRank(
  query: string,
  docs: Doc[],
  topk = 8,
): Promise<Scored[]> {
  if (!query || docs.length === 0) return [];

  const { pipeline, env } = (await import(TRANSFORMERS)) as TransformersModule;
  // Keep the model under the per-user iroha dir so it is found regardless of cwd / plugin reinstall.
  if (process.env.IROHA_MODEL_DIR) env.cacheDir = process.env.IROHA_MODEL_DIR;
  // Hook safety: NEVER download at query time (a first-prompt model fetch would blow the hook's ~5s
  // budget). The setup step pre-downloads with IROHA_EMBED_ALLOW_DOWNLOAD=1; at hook time we use the
  // cached model only, and a cache miss cleanly throws -> caller falls back to BM25-only candidates.
  if (process.env.IROHA_EMBED_ALLOW_DOWNLOAD !== "1")
    env.allowRemoteModels = false;

  const extractor = await pipeline("feature-extraction", MODEL, {
    dtype: DTYPE,
  });
  // Mean-pooled, L2-normalized sentence embedding -> cosine similarity is a plain dot product.
  const embed = async (text: string): Promise<number[]> => {
    const out = await extractor(text, { pooling: "mean", normalize: true });
    return Array.from(out.data);
  };

  // Per-machine embedding cache (derived data, like the search snippet — regenerable, not a source
  // of truth, so it is never committed). Keyed by model+text hash; only missing docs are embedded.
  const CACHE =
    process.env.IROHA_EMBED_CACHE ||
    `${process.env.IROHA_MODEL_DIR || `${process.env.HOME}/.iroha/models`}/../emb-cache.json`;
  let cache: Record<string, number[]> = {};
  try {
    if (existsSync(CACHE))
      cache = JSON.parse(readFileSync(CACHE, "utf8")) || {};
  } catch {
    cache = {};
  }

  let dirty = false;
  const scored: Scored[] = [];
  const qVec = await embed(Q_PREFIX + query);
  for (const doc of docs) {
    if (!doc?.id || !doc?.text) continue;
    const input = P_PREFIX + doc.text;
    const k = keyOf(input);
    let vec = cache[k];
    if (!vec) {
      vec = await embed(input);
      cache[k] = vec;
      dirty = true;
    }
    scored.push({ id: doc.id, score: dot(qVec, vec) });
  }

  if (dirty) {
    try {
      mkdirSync(dirname(CACHE), { recursive: true });
      const tmp = `${CACHE}.${process.pid}.tmp`;
      writeFileSync(tmp, JSON.stringify(cache));
      renameSync(tmp, CACHE); // atomic; concurrent prompts are idempotent (same content), last wins
    } catch {
      // A cache write failure is harmless — next call just re-embeds. Never fail the retrieval.
    }
  }

  return scored
    .sort((a, b) => b.score - a.score)
    .slice(0, topk)
    .map((s) => ({ id: s.id, score: Math.round(s.score * 1000) / 1000 }));
}

// CLI (warmup/manual): stdin = {"query","docs":[{id,text}],"topk"}; stdout = JSON Scored[].
//   exit 0 = ok (empty array when query/docs empty)  exit 2 = bad input  exit 3 = runtime/model
//   unavailable -> caller falls back to BM25-only candidates.
if (import.meta.main) {
  let raw = "";
  for await (const chunk of process.stdin) raw += chunk;
  let input: { query?: string; docs?: Doc[]; topk?: number };
  try {
    input = JSON.parse(raw);
  } catch {
    process.stderr.write("embed: invalid JSON on stdin\n");
    process.exit(2);
  }
  const docs = Array.isArray(input.docs) ? input.docs : [];
  const topk = typeof input.topk === "number" ? input.topk : 8;
  try {
    const out = await denseRank(input.query ?? "", docs, topk);
    process.stdout.write(`${JSON.stringify(out)}\n`);
    process.exit(0);
  } catch (e) {
    process.stderr.write(
      `embed: model/runtime unavailable (${e instanceof Error ? e.message : e}); falling back\n`,
    );
    process.exit(3);
  }
}
