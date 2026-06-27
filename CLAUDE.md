# iroha-for-session

Claude Code のセッションを Notion に保存し、人間も将来のセッションも参照できる
「生きたプロジェクト記憶」にする Claude Code プラグイン。いずれ世界配布する。

## 北極星

単なるアーカイブではなく、Claude が常時参照して育つ記憶。

- 「過去に似た開発は?」「X をやらないと決めた? 理由は?」に答えられる (Decisions を検索)
- 「前回どこまで? 未完了は?」を開始時に自発的に言える (Project State を注入)

詳細な合意設計は会話履歴および
`~/.claude/projects/-Users-shunichi-Projects-iroha-for-session/memory/project-goal-and-architecture.md` 参照。

## スタック

- ランタイム = **pure bash** (`extract.sh` 等; `set -u`, `jq`)。mumei / iroha-for-agents と同じ流儀。
- Notion への読み書きは **スキル内で Claude が Notion MCP ツールを呼ぶ**
  (`notion-create-database` / `notion-create-pages` / `notion-update-page` / `notion-search`)。
- 認証は **Notion MCP の OAuth のみ**。API トークンは持たない
  (配布ユーザーは Notion MCP を接続するだけで使える = 単一セットアップ)。
- dev ツール = biome (JSON lint/format) + shellcheck + typos + gitleaks (pre-commit) + pure-bash selftest。
- 知性 (要約・決定抽出・Type 分類) は `/save-session` スキル内で **Claude 本体**が担う。

## 言語境界

- 配布物 (scripts / SKILL.md / plugin.json) = **英語**。
- 開発側 (CLAUDE.md / .claude/rules / docs / commit) = 日本語。
- Notion に保存する内容 = **ユーザーの会話言語に従う** (この利用者は日本語)。

## アーキテクチャ

- 不変条件は `.claude/rules/architecture.md`。
- 3 DB (Sessions / Decisions / **Projects**=技術スタック、relation は使わず **URL プロパティで連結**) + プロジェクト 1 枚の State ページ。
- **container は flat 蓄積を作らない**: 直下は ガイド + 3 DB + `States`/`Digests` フォルダ固定 (State はプロジェクト毎・Digest は実行毎にフォルダ配下へ)。**Decision の `Topic` は一級 SELECT** (title parse でなく明示、By Topic view で family 俯瞰、`Project` 同様 save が ensure-option)。大量データは**ページ階層でなく Notion ビュー** (Recent/Calendar/By Month/By Topic/Active) で捌く。State と Projects 行は分離維持し相互リンク (auto/manual のカデンツが別)。
- トリガーは手動 `/save-session` (記録) / `/iroha:recall` (深い semantic 検索=notion-search＋index で過去の決定・類似実装) / `/iroha:project` (スタック手動更新)。SessionStart hook は repo の `.iroha/state.md` を注入。UserPromptSubmit hook は毎プロンプト**ローカル BM25**(`search.sh`/index)で関連決定を proactively 注入 (LLM/ネットワーク不要)。

## ローカル検証

- `npm run lint` (biome) / `npm run test:bash` (`tests/selftest.sh` が振る舞いの正本)。
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
- Stop ブロックによる保存強制 (ユーザーを閉じ込める)。保存 hook は "リマインド" まで。recall はローカルで proactive (LLM 呼ばないので毎プロンプトでも安価)。
- **save をサブエージェント / 独自 MCP サーバに分散** (知性は現セッション文脈依存で転送劣化・書込は既に各1コール・no-token / intelligence-in-Claude の不変違反。正解は `extract.sh all` 集約 / Decision の `pages[]` 一括 / 独立書込の並列 tool_use)。
- **Sessions/Decisions を年/月のページ階層にネスト** (DB の filter/sort/search/recall を失い、スケールでかえって見にくくなる。階層ブラウズは日付グルーピング view で代替)。
- 将来用の TS src / 投機的オプション (YAGNI)。
