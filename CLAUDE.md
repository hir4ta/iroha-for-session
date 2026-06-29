# iroha-for-memory

Claude Code のセッションを Notion に保存し、人間も将来のセッションも参照できる
「生きたプロジェクト記憶」にする Claude Code プラグイン。いずれ世界配布する。

## 北極星

単なるアーカイブではなく、Claude が常時参照して育つ記憶。Claude Code 本体も今やネイティブ記憶を持つが、
それは **1 開発者のマシンに閉じ・エージェントが読み戻す用**。iroha はその**上**に乗る
**チーム共有・人間可読の決定台帳**(理由＋却下案＋supersede 履歴)＝ネイティブが出さない軸に集中する
(positioning の正本)。

- 「過去に似た開発は?」「X をやらないと決めた? 理由は?」に答えられる (Decisions を検索)
- 「前回どこまで? 未完了は?」を開始時に自発的に言える (Project State を注入)
- **決定の瞬間に台帳へ 1 行追記** (`/iroha:decide`) ＝重い save を待たず記憶が育つ (capture の軽量半分)

詳細な合意設計は会話履歴および
`~/.claude/projects/-Users-shunichi-Projects-iroha-for-memory/memory/project-goal-and-architecture.md` 参照。

## スタック

- ランタイム = **Bun + TypeScript** (`scripts/**/*.ts` / `hooks/**/*.ts`; `bun X.ts` で build なし直接実行)。
  かつて pure bash + jq だったが、JSON 取り回し・型・テスト・配布(`bun build --compile` 可)の利点から
  TS へ全面移行した (決定「ランタイム: Bun/TS」が旧「ランタイム: pure bash」を **supersede**)。
  TS/biome 規約は同 `~/Projects` の **kakeibo**、堅牢な CI/構成は **mumei** を参考にする。
- 各モジュールは **関数 export + `if (import.meta.main)` の CLI** を両対応。スキル/フックは互いを
  **in-process import** で再利用し subprocess を張らない (config / index / search / recall / extract)。
- Notion への読み書きは **スキル内で Claude が Notion MCP ツールを呼ぶ**
  (`notion-create-database` / `notion-create-pages` / `notion-update-page` / `notion-search`)。
- 認証は **Notion MCP の OAuth のみ**。API トークンは持たない
  (配布ユーザーは Notion MCP を接続するだけで使える = 単一セットアップ)。
- dev ツール = biome (TS/JSON lint+format) + `tsc --noEmit` (型) + `bun test` (振る舞いの正本) +
  typos + gitleaks (pre-commit)。
- 知性 (要約・決定抽出・Type 分類) は `/save-session` スキル内で **Claude 本体**が担う。
- recall は 2 段だが**ローカルにモデルを持たない**: ①常時の安価な前段 = 自前 BM25
  (`scripts/_lib/search.ts`・無依存・オフライン・毎プロンプト hook)、②深い semantic 後段 =
  `/iroha:recall` が **Notion 自身の意味検索 (`notion-search`・無料プラン)** で言い換えを拾う。
  ローカル dense / cross-encoder rerank は撤去した (小コーパスで BM25 ≈ dense・cross-encoder は
  terse 日本語で不安定・install が重い・深い semantic は notion-search が無料で担う＝過剰実装だった)。

## 言語境界

- 配布物 (`scripts/**/*.ts` / SKILL.md / plugin.json) = **英語**。
- 開発側 (CLAUDE.md / .claude/rules / docs / commit) = 日本語。
- Notion に保存する内容 = **ユーザーの会話言語に従う** (この利用者は日本語)。

## アーキテクチャ

- 不変条件は `.claude/rules/architecture.md`。
- 3 DB (Sessions / Decisions / **Projects**=技術スタック、relation は使わず **URL プロパティで連結**) + プロジェクト 1 枚の State ページ。Session は **`PR` URL カラム**で PR にも連結する (`gh.ts` が境界付き・fail-soft で抽出＝extract の pure-local 不変を破らない唯一のネットワーク隔離点。Phase 0=リンクのみ・PR DB や GitHub 側書き込みはしない)。
- **container は flat 蓄積を作らない**: 直下は ガイド + 3 DB + `States`/`Digests` フォルダ固定 (State はプロジェクト毎・Digest は実行毎にフォルダ配下へ)。**Decision の `Topic` は一級 SELECT** (title parse でなく明示、By Topic view で family 俯瞰、`Project` 同様 save が ensure-option)。大量データは**ページ階層でなく Notion ビュー** (Recent/Calendar/By Month/By Topic/Active) で捌く。State と Projects 行は分離維持し相互リンク (auto/manual のカデンツが別)。
- トリガーは手動 `/save-session` (記録) / `/iroha:decide` (決定 1 行を即台帳化＝軽量 capture) / `/iroha:recall` (深い semantic 検索=notion-search＋index で過去の決定・類似実装) / `/iroha:project` (スタック手動更新)。SessionStart hook は repo の `.iroha/state.md` を注入。UserPromptSubmit hook は毎プロンプト**ローカル BM25**(`search.ts`/index)で関連決定を proactively 注入 (LLM/ネットワーク不要)。**コーパスが小さい間 (既定 8 行未満) は proactive 注入を止める** (cold-start gate＝極小コーパスで BM25 IDF が誤較正＝誤発火を防ぐ。明示 `/iroha:recall` は常に動く・台帳が育てば自動解除)。

## ローカル検証

- `bun test` (振る舞いの正本) / `bun run lint` (biome) / `bunx tsc --noEmit` (型)。
- 品質 eval: `bun tests/recall-eval.ts` (BM25 recall) / `bun tests/recall-scale.ts` (スケール)。
  いずれも凍結 fixture コーパス (`tests/fixtures/recall-corpus`) に対して回すので再 save で揺れない。
- `pre-commit install && pre-commit install --hook-type pre-push`。

## Notion MCP (dogfood / 配布)

リポジトリ直下の `.mcp.json` がホスト型 Notion MCP (`https://mcp.notion.com/mcp`,
transport=http, **OAuth**) を宣言する。秘密情報を含まないのでコミット可。リポジトリ
ルート = プラグインルートなので、配布時はプラグインのバンドル MCP 設定も兼ねる。

接続手順 (dogfood):

1. 新規 Claude Code セッションを開始 → プロジェクト MCP の承認プロンプトを許可。
2. `/mcp` を実行 → `notion` を選び Notion の OAuth をブラウザで完了
   (CLI なら `claude mcp login notion`)。
3. ツールが見えたら `/iroha:init` → `/iroha:save-session`。

代替: `claude mcp add --transport http notion --scope project https://mcp.notion.com/mcp`。
SSE エンドポイントはレガシーなので使わない。

## やらないこと

- API 直叩き / トークン管理 (Notion MCP に統一)。
- relation プロパティ (MCP の relation 書き込みに既知バグ → URL 連結で回避)。
- SessionEnd 自動保存のための headless claude (複雑化・"閉じ込めない"思想と緊張 → ロードマップ。当面は SessionStart リマインドで担保)。
- 毎プロンプト headless `claude -p` での recall (撤廃済: SOTA に無い反パターン＝コスト/遅延/レート競合・誤発火。ローカル BM25 へ置換)。
- **ローカル dense embed / cross-encoder rerank の recall tier** (撤去済: 小コーパスで BM25 ≈ dense・cross-encoder は terse 日本語で ~0 のバイモーダルで効果薄・transformers.js＋数百MB モデルで install が重い・深い semantic は `/iroha:recall` の `notion-search` が無料で担う＝過剰実装。前段は無依存 BM25、後段は notion-search で十分)。
- Stop ブロックによる保存強制 (ユーザーを閉じ込める)。保存 hook は "リマインド" まで。recall はローカルで proactive (LLM 呼ばないので毎プロンプトでも安価)。
- **save をサブエージェント / 独自 MCP サーバに分散** (知性は現セッション文脈依存で転送劣化・書込は既に各1コール・no-token / intelligence-in-Claude の不変違反。正解は `extract.ts all` 集約 / Decision の `pages[]` 一括 / 独立書込の並列 tool_use)。
- **Sessions/Decisions を年/月のページ階層にネスト** (DB の filter/sort/search/recall を失い、スケールでかえって見にくくなる。階層ブラウズは日付グルーピング view で代替)。
- 投機的オプション / 未使用の抽象・将来仮定の hook point (YAGNI)。
- **pure bash への回帰** (TS へ移行済; bash 固有の JSON エスケープ事故・jq stderr 漏れ・無型を再導入しない)。
