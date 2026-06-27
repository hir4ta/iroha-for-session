#!/usr/bin/env bash
# search.sh — pure-jq lexical recall over the local keys-only index (BM25, CJK-bigram aware).
#
# This is the CHEAP, always-on first stage of recall (Adaptive-RAG / Self-RAG routing): a
# local, token-free, offline ranking that needs no headless LLM and no Notion round-trip. It
# ranks the index's decision/session rows by lexical relevance to a query so the
# UserPromptSubmit hook can proactively surface "we have a relevant past decision" without the
# per-prompt cost of spawning `claude`. Deep semantic recall stays in the explicit /iroha:recall.
#
# Why lexical, not embeddings: at this scale (tens-hundreds of short, project-specialized
# records) BM25 ≈ dense (BEIR shows BM25 is the robust out-of-domain baseline; a small-corpus
# study found a 0.3pp gap), and embeddings would break the no-API-token / pure-bash invariant.
# Notion's own semantic search (free plan) is the dense complement, used by /iroha:recall.
#
# Why jq, not awk: the index is UTF-8 and the data is Japanese. awk's whitespace split collapses
# a Japanese run into one token, so lexical matching dies. jq (already a hard dependency) is
# codepoint-native: CJK runs are split into overlapping 2-grams (the standard CJK lexical
# tokenization), alnum runs are kept whole — so "連結" matches a title containing "連結".
#
# Scoring: BM25 term saturation (k1=1.2) with BM25 idf, length-norm dropped (b=0 — records are
# short and uniform, so length normalization barely moves ranking). A small "importance" proxy
# multiplies the score using fields already in the index (no Notion schema change): decisions
# outrank sessions, Active outranks Superseded — the Generative-Agents idea (relevance +
# importance) implemented deterministically and for free.
#
# Usage: search.sh <root> <query> [type] [topN] [minScore]
#   type     "decision" | "session" | "" (all)
#   topN     max hits (default 5)
#   minScore drop hits below this final score (default 0 = keep any token match)
# Output: one compact JSON object per line, best first:
#   {score, type, id, topic, status, date, title}
set -u

iroha_search() { # iroha_search <root> <query> [type] [topN] [minScore]
  local root="$1" query="$2" type="${3:-}" topn="${4:-5}" minscore="${5:-0}"
  local f="$root/.iroha/index.ndjson"
  [ -f "$f" ] || return 0
  jq -s -c \
    --arg q "$query" --arg type "$type" \
    --argjson topn "$topn" --argjson minscore "$minscore" '
    # jq has no hex literals, so codepoint ranges are decimal:
    #   48-57 0-9 / 97-122 a-z (after ascii_downcase)              -> "a" (alnum)
    #   12352-12543  Hiragana+Katakana  (U+3040-U+30FF)
    #   13312-40959  CJK ext-A + Unified (U+3400-U+9FFF)
    #   63744-64255  CJK compat ideographs (U+F900-U+FAFF)
    #   65381-65439  halfwidth Katakana (U+FF65-U+FF9F)            -> "c" (cjk: bigram it)
    def cls($c):
      if   ($c>=48 and $c<=57) or ($c>=97 and $c<=122) then "a"
      elif ($c>=12352 and $c<=12543) or ($c>=13312 and $c<=40959)
        or ($c>=63744 and $c<=64255) or ($c>=65381 and $c<=65439) then "c"
      else "s" end;
    # Group codepoints into maximal same-class runs (alnum / cjk); separators break runs.
    def runs:
      ascii_downcase | explode
      | reduce .[] as $c ([];
          cls($c) as $k
          | if (length>0 and .[-1].cls==$k and $k!="s")
            then .[0:-1] + [(.[-1] | .ch += [$c])]
            else . + [{cls:$k, ch:[$c]}] end);
    # alnum run -> one token; cjk run -> overlapping 2-grams (or the single char); sep -> none.
    def tok_of_run:
      if .cls=="a" then [(.ch|implode)]
      elif .cls=="c" then
        (if (.ch|length)<=1 then [(.ch|implode)]
         else [range(0; (.ch|length)-1) as $i | (.ch[$i:$i+2]|implode)] end)
      else [] end;
    # Ultra-common English function words carry no lexical signal. Romaji identifiers like
    # "iroha-for-session" inject them into the corpus, so without this a cross-domain query
    # ("terraform provider configuration for gcp") leaks on the shared "for". CJK 2-grams are
    # never in this set, so Japanese recall is untouched; meaningful short tokens (gh/pr/ci) too.
    def stop: {"a":1,"an":1,"the":1,"for":1,"of":1,"to":1,"in":1,"on":1,"at":1,"by":1,"as":1,
               "and":1,"or":1,"is":1,"are":1,"be":1,"with":1,"it":1,"this":1,"that":1,"from":1};
    def tokenize: ((runs | map(tok_of_run)) | add) // [] | map(select(. as $t | (stop | has($t)) | not));

    ($q | tokenize | unique) as $qt
    | [ .[] | select(($type=="") or (.type==$type)) ] as $docs
    | ($docs | length) as $N
    | if ($qt|length)==0 or $N==0 then empty else
        [ $docs[] | ((.title//"") + " " + (.topic//"") + " " + (.text//"")) | tokenize ] as $dtoks
        # document frequency per term (over unique tokens of each doc)
        | ( reduce $dtoks[] as $d ({};
              reduce ($d|unique)[] as $t (.; .[$t]=((.[$t]//0)+1)) ) ) as $df
        | 1.2 as $k1
        | [ range(0;$N) as $i
            | $dtoks[$i] as $d
            | ( reduce $qt[] as $t (0;
                  ($d | map(select(.==$t)) | length) as $tf
                  | if $tf==0 then . else
                      ($df[$t]//0) as $n
                      | (1 + ($N - $n + 0.5)/($n + 0.5) | log) as $idf
                      | . + $idf*($tf*($k1+1))/($tf+$k1)
                    end) ) as $bm
            | select($bm>0)
            | $docs[$i] as $doc
            | (if $doc.type=="session" then 0.85 else 1.0 end) as $wt
            | (if $doc.status=="Superseded" then 0.6 else 1.0 end) as $ws
            | ($bm*$wt*$ws) as $score
            | select($score >= $minscore)
            | {score:$score, type:$doc.type, id:$doc.id, topic:$doc.topic,
               status:$doc.status, date:$doc.date, title:$doc.title}
          ]
        | sort_by(-.score) | .[0:$topn] | .[]
      end
  ' "$f" 2>/dev/null
}

# CLI: usable from skills/hooks as `bash search.sh <root> <query> ...`. Guarded so sourcing is a no-op.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  command -v jq >/dev/null 2>&1 || { echo "search.sh: jq is required" >&2; exit 1; }
  iroha_search "${1:-}" "${2:-}" "${3:-}" "${4:-5}" "${5:-0}"
fi
