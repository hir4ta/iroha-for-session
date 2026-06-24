# アーキテクチャ不変条件

- **Notion 連携は MCP 一本**。書き込みは Claude がスキル内で Notion MCP ツールを呼ぶ:
  `notion-create-database` (DB 作成) / `notion-create-pages` (DB 行 + Markdown 本文) /
  `notion-update-page` (`replace_content` で State 全置換) / `notion-query-database-view` (リコール)。
  **API トークンは使わない**。認証は MCP の OAuth のみ (配布ユーザーは MCP 接続だけ)。
- **relation プロパティは使わない**。MCP の relation 書き込みに既知バグ (makenotion/notion-mcp-server
  Issue #45)。Session↔Decision は **URL プロパティ**で連結。安定確認後にネイティブ relation へ昇格可。
- **決定論抽出は bash**。`scripts/extract.sh` が transcript JSONL から chat/files/commands/meta を
  read-only で抽出。stdout = 要求されたビューのみ、診断ログは **必ず stderr**。
- **知性は Claude 本体 (スキル内)**。要約・決定抽出・Type 分類は `/save-session` の中で Claude が行う。
  コードから Anthropic API を呼ばない。
- **append 非対応を前提に設計**。Session ページ = 作成のみ (1 回で全部書く)、Project State = 毎回
  `replace_content` で全置換。逐次 append はしない。
- **データモデル**: Session DB + Decisions DB の 2 つ + プロジェクト 1 枚の State ページ。
  ID は `${CLAUDE_PLUGIN_DATA}/config.json` にキャッシュ。State は SessionStart (Phase 2) で注入。
- **冪等性**: `/init` は既存コンテナ/DB を検出したら再利用 (チーム参加 = 同じコマンド)。
  fallback = 複製可能 Notion テンプレート方式。
- **シークレットを持たない**。Notion 認証は MCP OAuth で完結。userConfig / env トークンは無し。
- **フックは強制でなくリマインド**。保存忘れは SessionStart で検知して注意喚起するに留める。
  Stop の exit 2 ブロックは使わない。
