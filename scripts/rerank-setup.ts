// rerank-setup.ts — OPT-IN setup for the HEAVY (hybrid) recall tier: a dense bi-encoder candidate
// generator + a cross-encoder reranker. iroha's proactive recall works out of the box on the
// dependency-free BM25 stage (scripts/_lib/search.ts; no deps, no model). This adds the higher-
// quality tier:
//   - DENSE retrieval (embed.mjs): surfaces the semantic near-matches BM25 misses.
//   - RERANK (rerank.mjs): PROMOTES the strong matches above the BM25 advisory list.
// It is opt-in because it is HEAVY — a Node runtime dep (@huggingface/transformers) + two local
// models (hundreds of MB each). embed.mjs / rerank.mjs stay .mjs (run via node): their dependency is
// uninstalled by default, so they are intentionally outside strict TS typechecking (lib research
// 2026 confirmed transformers.js is the right, still-maintained offline choice — see architecture.md).
//
// Run once: bun scripts/rerank-setup.ts
// Override either model first (e.g. a lighter, Japanese-specialized reranker):
//   IROHA_RERANK_MODEL=hotchpotch/japanese-reranker-xsmall-v2 IROHA_RERANK_DTYPE=fp32 bun scripts/rerank-setup.ts

import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { configSet } from "./_lib/config.ts";

const SCRIPTS = import.meta.dir;
const env = process.env;
const MODEL =
  env.IROHA_RERANK_MODEL || "onnx-community/bge-reranker-v2-m3-ONNX";
const DTYPE = env.IROHA_RERANK_DTYPE || "q8";
const EMODEL = env.IROHA_EMBED_MODEL || "Xenova/multilingual-e5-small";
const EDTYPE = env.IROHA_EMBED_DTYPE || "q8";
const MODELDIR = env.IROHA_MODEL_DIR || join(homedir(), ".iroha", "models");

function die(msg: string): never {
  process.stderr.write(`${msg}\n`);
  process.exit(1);
}

if (!Bun.which("node")) die("rerank-setup: node is required (>=18)");
if (!Bun.which("npm")) die("rerank-setup: npm is required");

console.log(
  "1/4  Installing the Node runtime (@huggingface/transformers) into the plugin…",
);
// --no-save keeps the SHIPPED package.json lean (a default install stays dependency-free); this is a
// per-user opt-in. Re-run this script after a clean reinstall to restore it.
const install = spawnSync(
  "npm",
  ["install", "--no-save", "@huggingface/transformers"],
  {
    cwd: join(SCRIPTS, ".."),
    stdio: "inherit",
  },
);
if (install.status !== 0) die("rerank-setup: npm install failed");

// Warm up a model script via node with download enabled; on failure print the tail and exit 1.
function warm(
  label: string,
  script: string,
  payload: string,
  extraEnv: Record<string, string>,
): void {
  const res = spawnSync("node", [join(SCRIPTS, script)], {
    input: payload,
    encoding: "utf8",
    env: { ...env, IROHA_MODEL_DIR: MODELDIR, ...extraEnv },
  });
  if (res.status !== 0) {
    process.stderr.write(
      `rerank-setup: ${label} download/load failed (exit ${res.status}):\n`,
    );
    process.stderr.write(
      `${(res.stdout ?? "") + (res.stderr ?? "")}`
        .split("\n")
        .slice(-5)
        .join("\n") + "\n",
    );
    process.exit(1);
  }
}

console.log(
  `2/4  Downloading the reranker model (${MODEL}, dtype=${DTYPE}) to ${MODELDIR} …`,
);
console.log(
  "     (one-time; the default bge-reranker-v2-m3 is ~570MB — Ctrl-C and set a lighter",
);
console.log(
  "      IROHA_RERANK_MODEL=hotchpotch/japanese-reranker-xsmall-v2 if you prefer ~37MB.)",
);
mkdirSync(MODELDIR, { recursive: true });
warm(
  "reranker",
  "rerank.mjs",
  '{"query":"warmup","docs":[{"id":"w","text":"warmup passage"}],"threshold":0.0,"topn":1}',
  {
    IROHA_RERANK_ALLOW_DOWNLOAD: "1",
    IROHA_RERANK_MODEL: MODEL,
    IROHA_RERANK_DTYPE: DTYPE,
  },
);

console.log(
  `3/4  Downloading the dense embedder (${EMODEL}, dtype=${EDTYPE}) to ${MODELDIR} …`,
);
console.log(
  "     (one-time; multilingual-e5-small is ~120MB — the dense lane that recovers the",
);
console.log("      semantic near-matches BM25 misses.)");
warm(
  "embedder",
  "embed.mjs",
  '{"query":"warmup","docs":[{"id":"w","text":"warmup passage"}],"topk":1}',
  {
    IROHA_EMBED_ALLOW_DOWNLOAD: "1",
    IROHA_EMBED_MODEL: EMODEL,
    IROHA_EMBED_DTYPE: EDTYPE,
  },
);

console.log("4/4  Arming the heavy recall tier (rerank_enabled=true) …");
configSet("rerank_enabled", "true");

console.log(`
Done. Proactive recall now runs the hybrid tier: BM25 ∪ dense candidates -> the cross-encoder
promotes the strong matches above the BM25 advisory list (higher recall AND precision, locally).
  reranker:  ${MODEL} (${DTYPE})
  embedder:  ${EMODEL} (${EDTYPE})
  model dir: ${MODELDIR}
  disable:   IROHA_RERANK_DISABLE=1  (per session)  /  bun scripts/_lib/config.ts set rerank_enabled false  (persistent)
  verify:    IROHA_MODEL_DIR=${MODELDIR} bun tests/hybrid-eval.ts   (recall+abstention end-to-end)
             IROHA_MODEL_DIR=${MODELDIR} bun tests/rerank-eval.ts   (cross-encoder unit precision)`);
