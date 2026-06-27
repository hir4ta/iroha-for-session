// chat-chunks.ts — split the cleaned full chat into Notion-ready Markdown chunks for save-session.
//
// save-session §5b posts the full cleaned chat (extract.ts `chat`) as a child page under the
// Session. For a BIG session the chat does NOT fit one notion-create-pages call, so it must be
// split — and splitting by hand drifts: re-summarizing, dropping turns, or cutting mid-turn (the
// past big-session save ended up "condensed, partial — not verbatim"). This makes the split
// DETERMINISTIC. It reuses extract's chatView (the SAME cleaned, per-turn-capped turns — no second
// formatting path), writes N chunk files of <= perChunk turns each, split ONLY on turn boundaries,
// and returns a manifest. The skill posts chunk 0 as the child page and appends the rest with
// insert_content — no hand-formatting, no drift, every turn present.
//
// Notion write itself stays MCP-only (the skill calls notion-create-pages / notion-update-page);
// this tool only does the deterministic formatting + chunking, never any network I/O.

import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { chatView, parseRecords } from "./extract.ts";

// Turns per chunk. 96 turns (~28KB) posted in one call during dogfooding, so 50 is a safe margin
// (each turn is capped at ~600 codepoints). Override with IROHA_CHAT_CHUNK for a smaller cap.
const PER_CHUNK = Number(process.env.IROHA_CHAT_CHUNK ?? "50");

export interface ChatChunks {
  totalTurns: number;
  chunkCount: number;
  files: string[];
}

// chatChunks(file, outDir, perChunk) -> write chat-chunk-NN.md files (paragraph Markdown, turn-
// boundary splits) and return the manifest. An empty chat yields 0 chunks (the caller writes a
// "(no content)" note instead of a fabricated page).
export function chatChunks(
  file: string,
  outDir: string,
  perChunk = PER_CHUNK,
): ChatChunks {
  const turns = chatView(parseRecords(file));
  mkdirSync(outDir, { recursive: true });
  const files: string[] = [];
  for (let i = 0; i < turns.length; i += perChunk) {
    // Each turn is already a single normalized line ("**You** …" / "**Claude** …"); join with a
    // blank line so every turn renders as its own Notion paragraph.
    const slice = turns.slice(i, i + perChunk);
    const p = join(
      outDir,
      `chat-chunk-${String(files.length).padStart(2, "0")}.md`,
    );
    writeFileSync(p, slice.join("\n\n"));
    files.push(p);
  }
  return { totalTurns: turns.length, chunkCount: files.length, files };
}

// CLI: `bun chat-chunks.ts <transcript.jsonl> <outDir> [perChunk]` -> manifest JSON on stdout.
//   exit 0 = ok (chunkCount 0 when the chat is empty)  exit 2 = bad usage.
if (import.meta.main) {
  const [file, outDir, per] = process.argv.slice(2);
  if (!file || !outDir) {
    process.stderr.write(
      "usage: chat-chunks.ts <transcript.jsonl> <outDir> [perChunk]\n",
    );
    process.exit(2);
  }
  const manifest = chatChunks(file, outDir, per ? Number(per) : PER_CHUNK);
  process.stdout.write(`${JSON.stringify(manifest)}\n`);
}
