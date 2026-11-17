# コントリビューションガイド

このリポジトリは社内向けの OSS です。モジュールの追加・改善、バグ修正、ドキュメントの更新を
歓迎します。**まずこのページを読み、詳細は各ドキュメントを参照してください。**

## 3 行でわかる進め方

1. Issue を作る（[バグ報告](.github/ISSUE_TEMPLATE/bug_report.yml) /
   [新しいモジュール](.github/ISSUE_TEMPLATE/new_module.yml) のテンプレートがあります）。
2. `develop` から `feature/*` ブランチを切り、`make preflight` が通る状態で `develop` に PR を出す。
3. リリースは月 1 回、自動です。**毎月 1 日**に `release/vX.Y.Z` が切られて `main` への
   リリース PR が作られ、**毎月 4 日に自動でマージ**されてタグと GitHub Release が作られます
   （すぐ出したいときはリリース PR を手でマージするだけ）。

## セットアップ

必要なのは **Terraform CLI (>= 1.10)**、**Python 3**、**[mise](https://mise.jdx.dev/)** です。
tflint / trivy / pre-commit は [`.tool-versions`](./.tool-versions) で固定したバージョンを
`make tools` が入れます。

```bash
make tools       # .tool-versions のツールを入れる（最初に一度）
make hooks       # git フック（fmt・規約・コミットメッセージ）を有効にする（最初に一度）
make help        # 使えるタスクの一覧
make preflight   # fmt + policy + validate + test + lint（コミット前に実行）
make check       # preflight + security（CI と同じ内容）
```

`terraform test` は `mock_provider` を使うため、**実際のクラウドリソースは作成されず、
認証情報も不要**です。

## 守ってほしいこと

- **コミットメッセージと PR タイトルは `<type>(<scope>): <subject>` 形式**（scope は必須）。
  `develop` へは squash マージなので、PR タイトルがそのままコミットになり、
  **リリースのバージョン判定に使われます**。破壊的変更を含む場合は type の後ろに `!` を付けてください。
  規約: [docs/commit_message.md](docs/commit_message.md)
- **README と実装を一致させる**。変数や出力を足したら、モジュールの README の表も更新してください
  （`make policy` が食い違いを検出します）。
- **モジュールは 2 つの利用パターン（GitHub 参照 / コピー＆ペースト）の両方で動くこと。**
  設計方針は
  [docs/module_contribution_guidelines.md](docs/module_contribution_guidelines.md) を参照してください。
- **ラベルとアサインは自動で付きます。** 手で設定する必要はありません（足りないときだけ追加）。
  レビュー依頼も [.github/CODEOWNERS](.github/CODEOWNERS) から自動で飛びます。

## 新しいモジュールを追加する

```bash
make new-module NAME=google/pubsub-topic DESC="Pub/Sub トピック + IAM"
```

雛形・テスト・ルート README の一覧まで生成され、生成直後の状態で `make preflight` が通ります。
そこからサンプル実装を置き換えてください。単一リソースの薄いラッパーは作りません
（判断基準は
[docs/module_contribution_guidelines.md](docs/module_contribution_guidelines.md)）。

## ドキュメント

| 知りたいこと | ドキュメント |
| :--- | :--- |
| モジュールの使い方（利用者向け） | [docs/module_usage.md](docs/module_usage.md) |
| 日々の開発フロー | [docs/development_workflow.md](docs/development_workflow.md) |
| リリースの仕組みと手順 | [docs/release_workflow.md](docs/release_workflow.md) |
| 自動化されている仕組みと失敗時の対処 | [docs/maintenance.md](docs/maintenance.md) |
| コーディング規約 | [docs/coding_standards.md](docs/coding_standards.md) |
| AI エージェントで作業するとき | [AGENTS.md](AGENTS.md)（`CLAUDE.md` はこのファイルへのシンボリックリンク。Gemini CLI 固有の注意だけ [GEMINI.md](GEMINI.md)） |
| モジュールの設計方針・テスト要件 | [docs/module_contribution_guidelines.md](docs/module_contribution_guidelines.md) |
