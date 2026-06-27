// rerank.ts — local, offline cross-encoder reranker: the PRECISION gate for proactive recall.
//
// Why this exists. The cheap always-on first stage (scripts/_lib/search.ts, BM25) has great recall
// but limited precision on a small single-domain corpus: a prompt that merely shares the project's
// vocabulary ("upload an image to Notion", "how to write bash tests") lexically matches an unrelated
// decision and, measured, can outscore a genuinely relevant one — so a higher floor cannot separate
// them. A cross-encoder reranker CAN: it scores the (query, decision) PAIR for actual relevance,
// crushing same-vocabulary-but-off-topic candidates to ~0 while keeping real matches high (measured:
// 0/7 false injections on hard negatives, real matches rank #1).
//
// Opt-in contract. It adds the @huggingface/transformers dep + a ~570MB local model, so it is
// strictly OPT-IN — a fresh install pays nothing and keeps the dependency-free BM25 advisory
// behavior; only a user who runs the rerank setup and arms it (config rerank_enabled=true) pays the
// cost. It supersedes the earlier decision "リコール精度: lexical据置". Runs in-process under Bun
// (transformers v4 supports Bun) — NO node subprocess, NO API token, NO network at query time (the
// model is local and cached); the broken invariant is "zero deps", not "no token / offline". The
// heavy dep is imported via a VARIABLE specifier so a default install (dep absent) still typechecks.

export interface Doc {
  id: string;
  text: string;
}
export interface Scored {
  id: string;
  score: number;
}

// Minimal shape of the bits of @huggingface/transformers we use (it ships no types we depend on).
type Tokenizer = (
  text: string,
  opts: { text_pair: string; padding: boolean; truncation: boolean },
) => unknown;
type Model = (
  inputs: unknown,
) => Promise<{ logits: { data: ArrayLike<number> } }>;
type TransformersModule = {
  AutoTokenizer: { from_pretrained: (model: string) => Promise<Tokenizer> };
  AutoModelForSequenceClassification: {
    from_pretrained: (model: string, opts: { dtype: string }) => Promise<Model>;
  };
  env: { cacheDir?: string; allowRemoteModels?: boolean };
};

// Model is per-user and cached (survives plugin reinstall), like config.json. Default to the
// Transformers.js-compatible ONNX export of bge-reranker-v2-m3 (strong multilingual incl Japanese).
const MODEL =
  process.env.IROHA_RERANK_MODEL || "onnx-community/bge-reranker-v2-m3-ONNX";
const DTYPE = process.env.IROHA_RERANK_DTYPE || "q8";
// Variable specifier (not a string literal) so tsc cannot resolve it: the heavy dep stays optional
// and a default install (dep absent) still typechecks. The dynamic import is `any` either way.
const TRANSFORMERS = "@huggingface/transformers";

// rerankPromote — score each (query, doc) pair, keep the "strong" (>= threshold) survivors, desc,
// <= topn. THROWS when the runtime or model is unavailable; the caller (recall.ts) catches and
// falls back to the BM25 advisory result. An empty return means "judged everything irrelevant"
// (confident abstain) — distinct from a throw, which means "could not judge" (keep BM25 hits).
export async function rerankPromote(
  query: string,
  docs: Doc[],
  threshold = 0.05,
  topn = 3,
): Promise<Scored[]> {
  if (!query || docs.length === 0) return [];

  const { AutoTokenizer, AutoModelForSequenceClassification, env } =
    (await import(TRANSFORMERS)) as TransformersModule;
  // Keep the model under the per-user iroha dir so it is found regardless of cwd / plugin reinstall.
  if (process.env.IROHA_MODEL_DIR) env.cacheDir = process.env.IROHA_MODEL_DIR;
  // Hook safety: NEVER download at query time (a first-prompt 570MB fetch would blow the hook's ~5s
  // budget and hang the prompt). The setup step pre-downloads with IROHA_RERANK_ALLOW_DOWNLOAD=1; at
  // hook time we use the cached model only, and a cache miss cleanly throws -> caller falls back.
  if (process.env.IROHA_RERANK_ALLOW_DOWNLOAD !== "1")
    env.allowRemoteModels = false;

  const tokenizer = await AutoTokenizer.from_pretrained(MODEL);
  const model = await AutoModelForSequenceClassification.from_pretrained(
    MODEL,
    {
      dtype: DTYPE,
    },
  );
  const relevance = async (q: string, d: string): Promise<number> => {
    const inputs = tokenizer(q, {
      text_pair: d,
      padding: true,
      truncation: true,
    });
    const { logits } = await model(inputs);
    return 1 / (1 + Math.exp(-(logits.data[0] as number))); // sigmoid(logit) -> 0..1 relevance
  };

  const scored: Scored[] = [];
  for (const doc of docs) {
    if (!doc?.id || !doc?.text) continue;
    try {
      scored.push({ id: doc.id, score: await relevance(query, doc.text) });
    } catch {
      // Skip a single bad pair rather than failing the whole rerank.
    }
  }

  return scored
    .filter((s) => s.score >= threshold)
    .sort((a, b) => b.score - a.score)
    .slice(0, topn)
    .map((s) => ({ id: s.id, score: Math.round(s.score * 1000) / 1000 }));
}

// CLI (warmup/manual): stdin = {"query","docs":[{id,text}],"threshold","topn"}; stdout = Scored[].
//   exit 0 = ok (empty array = confident abstain)  exit 2 = bad input  exit 3 = runtime/model
//   unavailable -> caller falls back to the BM25 advisory result.
if (import.meta.main) {
  let raw = "";
  for await (const chunk of process.stdin) raw += chunk;
  let input: {
    query?: string;
    docs?: Doc[];
    threshold?: number;
    topn?: number;
  };
  try {
    input = JSON.parse(raw);
  } catch {
    process.stderr.write("rerank: invalid JSON on stdin\n");
    process.exit(2);
  }
  const docs = Array.isArray(input.docs) ? input.docs : [];
  const threshold =
    typeof input.threshold === "number" ? input.threshold : 0.05;
  const topn = typeof input.topn === "number" ? input.topn : 3;
  try {
    const out = await rerankPromote(input.query ?? "", docs, threshold, topn);
    process.stdout.write(`${JSON.stringify(out)}\n`);
    process.exit(0);
  } catch (e) {
    process.stderr.write(
      `rerank: model/runtime unavailable (${e instanceof Error ? e.message : e}); falling back\n`,
    );
    process.exit(3);
  }
}
