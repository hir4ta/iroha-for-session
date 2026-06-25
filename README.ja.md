# iroha for Notion

[English](README.md) | **日本語**

**Claude Code との会話を、Notion に「育つチームの記憶」として残すプラグインです。**

セッションが終わるたびに、その回で何を・なぜ決めたか、何が残っているか、どう作られているかを
Notion に整理して保存します。

次に開くセッションは——自分のでもチームメイトのでも——ちゃんと続きから始められます。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/hir4ta/iroha-for-notion/actions/workflows/ci.yml/badge.svg)](https://github.com/hir4ta/iroha-for-notion/actions/workflows/ci.yml)

## こんな課題に

Claude のメモリは便利ですが、薄いし、しかも自分のマシンの中だけ。

「あの判断、なんでそうしたんだっけ?」「前に似たもの作らなかった?」が、毎回ふりだしに戻ります。

iroha は、その記憶を Notion に逃がします。

検索できて、チームで共有できて、使うほど厚くなる。「前に似た実装したっけ?」と聞けば、
その時のセッション・触ったファイル・理由まで返ってきます。

## どう動くのか

役割はシンプルに分かれています。

- **決まりきった抽出は bash に。** `scripts/extract.sh`（pure bash + jq）が、トランスクリプトから変更ファイル・コマンド・メタ情報を取り出します。
- **頭を使うところは Claude に。** 要約・意思決定の抽出・分類・チャットのハイライトは、スキルの中で Claude 本体が書きます。
- **Notion とのやりとりは MCP だけ。** API トークンは持ちません。認証は Notion MCP の OAuth ひとつ。検索（リコール）は無料プランでも動く `notion-search` を使います。

セッションを開いた瞬間、フックがプロジェクトの「現在地」を注入します。

だから Claude は、頼まなくても「前回ここまで、これが未完了です」と教えてくれます。

`/compact` や auto-compact の後は、そのセッション自身の会話（あなたの発言＋直近のやりとり）も再注入します。だから要約で流れが切れません。

保存される各セッションには、**メトリクス・ダッシュボード**（ターン数・ツール呼び出し・変更ファイル・所要時間）と、折りたためる**フルチャットの監査トレイル**も付きます。`/iroha:digest` は週次・月次を 1 枚にまとめ、`/iroha:audit` は育つ記憶を健全に保ちます（重複決定・State ドリフト・陳腐化の検出）。

## 記憶のかたち — 3層 + State

```mermaid
graph TD
  CC["Claude Code session"] -->|/iroha:save-session| SK["save-session skill"]
  SK -->|deterministic| EX["extract.sh (bash)"]
  SK -->|intelligence| CL["Claude"]
  SK -->|Notion MCP / OAuth| N[("Notion")]
  N --> SES["Sessions — what happened"]
  N --> DEC["Decisions — why"]
  N --> PRJ["Projects — current stack"]
  N --> ST["State — where we are"]
  ST -->|repo .iroha/state.md| HK["SessionStart hook"]
  DEC -->|notion-search| RC["/iroha:recall"]
```

| 層 | 役割 |
| --- | --- |
| **Sessions** | その回に何が起きたか（要約・下した決定・ハイライト・変更ファイル）。 |
| **Decisions** | なぜ今の形なのか（理由と却下案。方針転換の履歴も残ります）。 |
| **Projects** | いま何で出来ているか（言語・ライブラリ・CI・構成図）。オンボーディングと横断検索に。 |
| **State** | 「今どこ / 何が残っているか」。セッション開始時に注入されます。 |

## 必要なもの

- Claude Code
- Notion アカウントと、ホスト型 Notion MCP の接続（OAuth）

無料プランでそのまま動きます。

## 入れる

Claude Code の中で:

```
/plugin marketplace add hir4ta/iroha-for-notion
/plugin install iroha@iroha-for-notion
```

## はじめかた

1. **Notion をつなぐ** — `/mcp` から `notion` を選び、ブラウザで OAuth を済ませます。
2. **`/iroha:init`** — Sessions / Decisions / Projects のデータベースを、選んだページの下に作ります。チームで使うなら、同じページで誰かが実行すれば参加できます。
3. **`/iroha:save-session`** — いまのセッションを保存。
4. **`/iroha:recall <調べたいこと>`** — 「X をやめたのはなぜ?」「前に作ってない?」
5. **`/iroha:project`** — プロジェクトの技術スタックを記録します（手動。エンジニアが確認してから）。

## コマンド

| コマンド | 何をするか |
| --- | --- |
| `/iroha:init` | 一度きりのセットアップ（冪等）。Notion の DB とビューを作る、または既存に参加する。 |
| `/iroha:save-session` | このセッションを保存。要約・決定・変えたルール・作業状態・ハイライト・変更ファイル。 |
| `/iroha:recall <query>` | Sessions と Decisions を意味検索。過去の決定や、似た過去作業を引く。 |
| `/iroha:project` | このプロジェクトのアーキテクチャを記録／更新（手動）。 |
| `/iroha:digest [week\|month\|範囲]` | 期間を 1 枚に集約。決定・セッション・合計メトリクス・未完了・タイムライン。 |
| `/iroha:audit [--fix]` | 記憶の健全性チェック（重複決定・State ドリフト・陳腐化）。安全な可逆修正のみ任意適用。 |

## あえて、やらないこと

- **秘密は持たない。** 管理する API トークンはありません。認証は MCP の OAuth だけ、手元に置くのは秘密でない id だけです。
- **relation プロパティは使わない。** Notion MCP の relation 書き込みにバグがあるので、URL で連結しています（安定したら乗り換え可）。
- **会話を逐語のまま丸ごとは残さない。** 主役はキュレーションした「ハイライト」（*You* は実発言にアンカーし、創作しません）。その下に、thinking とツール出力を除いた整形済み・1ターン上限の「フルチャット」を監査用として折りたたんで添えます。
- **保存を強制しない。** フックはそっと促すだけ。あなたを止めたりはしません。

## もっと知る

- 設計の不変条件 — [`.claude/rules/architecture.md`](.claude/rules/architecture.md)
- プロジェクトのメモとスコープ — [`CLAUDE.md`](CLAUDE.md)
- 開発に参加する — [`CONTRIBUTING.md`](CONTRIBUTING.md) ／ セキュリティ — [`SECURITY.md`](SECURITY.md)

## ライセンス

[MIT](LICENSE) © Shunichi Hirata
