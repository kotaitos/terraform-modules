# terraform-modules

案件で使い回す Terraform モジュールを提供する社内リポジトリ。利用者は
`?ref=<タグ>` でこのリポジトリを参照するため、**公開済みのタグは不変**として扱う。

## 構成

| パス | 中身 |
| :--- | :--- |
| `modules/<provider>/<module>/` | 配布するモジュール。プロバイダーは増える前提（Google Cloud 専用ではない） |
| `templates/module/<provider>/` | `make new-module` が使う雛形 |
| `scripts/` | 規約チェック・バージョン算出。スクリプト自身のテストは `make test-scripts` |
| `docs/` | 規約とワークフローの唯一の情報源 |
| `.agents/skills/<名前>/SKILL.md` | よく使う作業の手順。どのエージェントからも同じものを読む |

モジュールの一覧はどこにもハードコードしない（Makefile も CI も規約チェックも
`modules/<provider>/<module>/` を動的に探索する）。

## 変更したら実行する

```bash
make preflight                                    # fmt + policy + validate + test + lint
make check                                        # preflight + security（CI と同じ内容）
make MODULE=modules/google/external-lb preflight  # 1 モジュールだけ
```

`make policy` は README と実装（変数・出力・バージョン制約）の整合まで検査する。
変数や出力を足したら、そのモジュールの README の表も直す。検査項目の一覧は
[docs/maintenance.md](docs/maintenance.md) の 6 章にある。

## 守ること

- **PR は `develop` へ出す。** `main` はリリース専用。タイトルは
  `<type>(<scope>): <subject>` 形式で、squash マージによりそのままコミットになり、
  リリースのバージョン判定に使われる（規約は
  [docs/commit_message.md](docs/commit_message.md)、判定はローカルが commitlint
  （[.commitlintrc.json](.commitlintrc.json)）、PR タイトルが
  amannn/action-semantic-pull-request）。`develop` へのマージでは Issue は閉じない
  （GitHub が閉じるのは `main` に入ったときだけ）。
- **利用者のインターフェースを壊さない。** 変数を消す・名前を変えるのではなく、古い変数を
  `optional` で残して非推奨にする。破壊的変更（MAJOR）は利用者の対応を必要とするので、
  避けられるなら避ける。判断基準は
  [docs/module_contribution_guidelines.md](docs/module_contribution_guidelines.md) の 8 章。
- **タグを手で打たない。リリースブランチ（`release/vX.Y.Z`）を手で作らない。**
  リリースは月次で自動。手順は
  [docs/release_workflow.md](docs/release_workflow.md) が唯一の情報源。
- **モジュール内に `provider` ブロックを書かない。** 認証情報と project / region の
  既定値は利用者のルートモジュールの責務。
- **API 側の制約は `validation` で plan 時に落とす。** apply でしか分からないエラーを
  利用者に見せない。
- テストは `terraform test` + `mock_provider`。実リソースは作らず、認証情報も要らない。
- 新しいモジュールは `make new-module NAME=<provider>/<module> DESC="概要"` から作る。
  雛形が無いプロバイダーを足すときは
  [templates/module/README.md](templates/module/README.md) の手順に従う。

## ドキュメント

入口は [CONTRIBUTING.md](CONTRIBUTING.md)（どの文書に何が書いてあるかの表がある）。
規約をここに書き写さず、参照する。同じ規約が二か所にあると必ず片方が腐る。

よく使う作業の手順は `.agents/skills/<名前>/SKILL.md` にスキルとして置いてある
（`commit-changes` / `create-issue` / `create-pr` / `plan-issue-impl` / `sync-docs`）。
スキルとして自動で読み込まれない環境では、その作業をするときにファイルを開いて従う。

## エージェントごとの設定

**実体は 1 つだけ置き、残りはリンクにする。** 内容を書き写すと必ず片方が腐る。

| 実体 | それを読ませる仕掛け |
| :--- | :--- |
| `AGENTS.md`（このファイル） | Cursor / Codex / Copilot などはそのまま読む。`CLAUDE.md` はこのファイルへのシンボリックリンク。Gemini CLI は [.gemini/settings.json](.gemini/settings.json) の `context.fileName` で読む |
| `.agents/skills/<名前>/SKILL.md` | Cursor / Codex / Gemini CLI はそのまま読む。`.claude/skills/<名前>` は実体へのシンボリックリンク |
| [GEMINI.md](GEMINI.md) | Gemini CLI 固有の注意だけを書く。規約は書かない |

スキルを足したら Claude Code 用のリンクも作る（`.claude/skills/` は実体を持たない）。

```bash
ln -s ../../.agents/skills/<名前> .claude/skills/<名前>
```
