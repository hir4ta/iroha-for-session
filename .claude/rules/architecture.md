# アーキテクチャ不変条件

- **Notion 連携は MCP 一本**。書き込みは Claude がスキル内で Notion MCP ツールを呼ぶ:
  `notion-create-database` (DB 作成) / `notion-create-pages` (DB 行 + Markdown 本文) /
  `notion-update-page` (`replace_content` で State 全置換) / `notion-search` (リコール、無料プランで動く)。
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
  ID は config.json にキャッシュ。**決定/ルールの正本は Decisions DB / CLAUDE.md** に一本化し、
  State / Session ページに全文転記しない (重複防止)。
- **リコールは `notion-search` 主経路** (無料プランで動く。`query-database-view` /
  `query-data-sources` は有料なので使わない)。`/iroha:recall` は Sessions/Decisions を
  semantic 検索し、過去の決定・**類似実装**を引く (使うほど育つチーム記憶の中核)。
- **ミラーは repo の `.iroha/`**。`state.md` / `decisions.md` をコミットし teammate は pull で共有。
  SessionStart hook は Notion 非到達なので **repo の `.iroha/state.md` を注入**、オフライン recall は
  `.iroha/decisions.md` を grep (fallback)。config.json / saved マーカーは $HOME (マシン固有)。
- **命名と履歴**: Session = `YYYY-MM-DD — 主題`、Decision = `トピック: 選択` (理由は Rationale、
  却下案は Alternatives 欄)。決定を覆す時は旧行を **Status=Superseded** にし上書きしない (心変わりも
  記憶)。Session ページのセクション構造は固定 (コア固定＋任意2つ: Architecture / Failures のみ任意)。
- **冪等性**: `/init` は既存コンテナ/DB を検出したら再利用 (チーム参加 = 同じコマンド)。
  fallback = 複製可能 Notion テンプレート方式。
- **シークレットを持たない**。Notion 認証は MCP OAuth で完結。userConfig / env トークンは無し。
- **フックは強制でなくリマインド**。保存忘れは SessionStart で検知して注意喚起するに留める。
  Stop の exit 2 ブロックは使わない。State ミラー注入時に「実装前に `/iroha:recall` で過去の
  類似事例を確認」も促す。
