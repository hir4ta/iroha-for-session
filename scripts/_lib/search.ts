// search.ts — lexical recall over the local keys-only index (BM25, CJK-bigram aware).
//
// This is the CHEAP, always-on first stage of recall (Adaptive-RAG / Self-RAG routing): a
// local, token-free, offline ranking that needs no headless LLM and no Notion round-trip. It
// ranks the index's decision/session rows by lexical relevance to a query so the
// UserPromptSubmit hook can proactively surface "we have a relevant past decision". Deep semantic
// recall stays in the explicit /iroha:recall.
//
// Why lexical, not embeddings: at this scale (tens-hundreds of short, project-specialized
// records) BM25 ≈ dense, and embeddings would break the no-API-token invariant. Notion's own
// semantic search (free plan) is the dense complement, used by /iroha:recall.
//
// Tokenization is codepoint-native (CJK runs -> overlapping 2-grams, alnum runs kept whole), so
// "連結" matches a title containing "連結" — what a whitespace split (the data is Japanese) cannot.
//
// Scoring: BM25 term saturation (k1=1.2) with BM25 idf, length-norm dropped (b=0 — records are
// short and uniform). A small "importance" proxy multiplies the score using fields already in the
// index: decisions outrank sessions, Active outranks Superseded.

import { indexRead } from "./index.ts";

export interface SearchHit {
  score: number;
  type: string;
  id: string;
  topic: string;
  status: string;
  date: string;
  title: string;
}

// Ultra-common English function words carry no lexical signal. Romaji identifiers like
// "iroha-for-session" inject them into the corpus, so without this a cross-domain query leaks on
// the shared "for". CJK 2-grams are never in this set, so Japanese recall is untouched.
const STOP = new Set([
  "a",
  "an",
  "the",
  "for",
  "of",
  "to",
  "in",
  "on",
  "at",
  "by",
  "as",
  "and",
  "or",
  "is",
  "are",
  "be",
  "with",
  "it",
  "this",
  "that",
  "from",
]);

const K1 = 1.2;

// ASCII-only downcase (matches jq ascii_downcase — non-ASCII left as-is, then bigram-tokenized).
function asciiDowncase(s: string): string {
  return s.replace(/[A-Z]/g, (c) => c.toLowerCase());
}

// Codepoint class: "a" alnum (0-9 a-z) / "c" CJK (kana + unified + compat + halfwidth kana) / "s".
function classOf(cp: number): "a" | "c" | "s" {
  if ((cp >= 48 && cp <= 57) || (cp >= 97 && cp <= 122)) return "a";
  if (
    (cp >= 12352 && cp <= 12543) ||
    (cp >= 13312 && cp <= 40959) ||
    (cp >= 63744 && cp <= 64255) ||
    (cp >= 65381 && cp <= 65439)
  )
    return "c";
  return "s";
}

// alnum run -> one token; cjk run -> overlapping 2-grams (or the single char); separators dropped.
// Then drop stopwords.
export function tokenize(s: string): string[] {
  const cps = [...asciiDowncase(s)];
  const tokens: string[] = [];
  let i = 0;
  while (i < cps.length) {
    const ch = cps[i] as string;
    const cls = classOf(ch.codePointAt(0) as number);
    if (cls === "s") {
      i += 1;
      continue;
    }
    let j = i + 1;
    while (
      j < cps.length &&
      classOf((cps[j] as string).codePointAt(0) as number) === cls
    )
      j += 1;
    const run = cps.slice(i, j);
    if (cls === "a") {
      tokens.push(run.join(""));
    } else if (run.length <= 1) {
      tokens.push(run.join(""));
    } else {
      for (let k = 0; k < run.length - 1; k++)
        tokens.push(run.slice(k, k + 2).join(""));
    }
    i = j;
  }
  return tokens.filter((t) => !STOP.has(t));
}

// search(root, query, type, topn, minscore) -> ranked hits, best first.
export function search(
  root: string,
  query: string,
  type = "",
  topn = 5,
  minscore = 0,
): SearchHit[] {
  const qt = [...new Set(tokenize(query))];
  const docs = indexRead(root).filter((d) => type === "" || d.type === type);
  const n = docs.length;
  if (qt.length === 0 || n === 0) return [];

  const docText = (d: Record<string, unknown>) =>
    `${String(d.title ?? "")} ${String(d.topic ?? "")} ${String(d.text ?? "")}`;
  const dtoks = docs.map((d) => tokenize(docText(d)));

  // document frequency per term (over the unique tokens of each doc).
  const df = new Map<string, number>();
  for (const toks of dtoks) {
    for (const t of new Set(toks)) df.set(t, (df.get(t) ?? 0) + 1);
  }

  const hits: SearchHit[] = [];
  for (let i = 0; i < n; i++) {
    const toks = dtoks[i] as string[];
    let bm = 0;
    for (const t of qt) {
      const tf = toks.filter((x) => x === t).length;
      if (tf === 0) continue;
      const nt = df.get(t) ?? 0;
      const idf = Math.log(1 + (n - nt + 0.5) / (nt + 0.5));
      bm += (idf * (tf * (K1 + 1))) / (tf + K1);
    }
    if (bm <= 0) continue;
    const doc = docs[i] as Record<string, unknown>;
    const wt = doc.type === "session" ? 0.85 : 1.0;
    const ws = doc.status === "Superseded" ? 0.6 : 1.0;
    const score = bm * wt * ws;
    if (score < minscore) continue;
    hits.push({
      score,
      type: String(doc.type ?? ""),
      id: String(doc.id ?? ""),
      topic: String(doc.topic ?? ""),
      status: String(doc.status ?? ""),
      date: String(doc.date ?? ""),
      title: String(doc.title ?? ""),
    });
  }
  // Stable descending sort by score (ties keep index order, matching jq sort_by).
  hits.sort((a, b) => b.score - a.score);
  return hits.slice(0, topn);
}

// CLI: `bun search.ts <root> <query> [type] [topN] [minScore]`. One compact JSON hit per line.
if (import.meta.main) {
  const [root, query, type, topn, minscore] = process.argv.slice(2);
  const hits = search(
    root ?? "",
    query ?? "",
    type ?? "",
    topn ? Number(topn) : 5,
    minscore ? Number(minscore) : 0,
  );
  for (const h of hits) process.stdout.write(`${JSON.stringify(h)}\n`);
}
