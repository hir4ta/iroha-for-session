# iroha-for-notion

Claude Code のセッションを Notion に保存し、人間も将来のセッションも参照できる
「生きたプロジェクト記憶」にする Claude Code プラグイン。いずれ世界配布する。

## 北極星

単なるアーカイブではなく、Claude が常時参照して育つ記憶。

- 「過去に似た開発は?」「X をやらないと決めた? 理由は?」に答えられる (Decisions を検索)
- 「前回どこまで? 未完了は?」を開始時に自発的に言える (Project State を注入)

詳細な合意設計は会話履歴および
`~/.claude/projects/-Users-shunichi-Projects-iroha-for-notion/memory/project-goal-and-architecture.md` 参照。

## スタック

- ランタイム = **pure bash** (`extract.sh` 等; `set -u`, `jq`)。mumei / iroha-for-agents と同じ流儀。
- Notion への読み書きは **スキル内で Claude が Notion MCP ツールを呼ぶ**
  (`notion-create-database` / `notion-create-pages` / `notion-update-page` / `notion-query-database-view`)。
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
- 2 DB (Session / Decisions、relation は使わず **URL プロパティで連結**) + プロジェクト 1 枚の State ページ。
- トリガーは手動 `/save-session`。リコール (SessionStart 注入 / view-query) は Phase 2。

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
3. ツールが見えたら `/iroha-for-notion:init` → `/iroha-for-notion:save-session`。

代替: `claude mcp add --transport http notion --scope project https://mcp.notion.com/mcp`。
SSE エンドポイントはレガシーなので使わない。

## やらないこと

- API 直叩き / トークン管理 (Notion MCP に統一)。
- relation プロパティ (MCP の relation 書き込みに既知バグ → URL 連結で回避)。
- SessionEnd 自動保存のための headless claude (複雑化 → Phase 3)。
- Stop ブロックによる保存強制 (ユーザーを閉じ込める)。hooks は "リマインド" まで。
- 将来用の TS src / 投機的オプション (YAGNI)。
