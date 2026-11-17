# terraform-modules

案件で使い回せる Terraform モジュール群を提供します。モジュールは
`modules/<プロバイダー>/<モジュール名>/` に置き、プロバイダーは必要に応じて増やします
（現在は Google Cloud のモジュールが揃っています）。

## コンセプト

- **どちらの使い方でもそのまま動く**: GitHub からの直接参照（`source = "git::https://...//modules/google/xxx?ref=vX.Y.Z"`）と、
  案件リポジトリへのコピー＆ペースト（`source = "./modules/xxx"`）のどちらでも、
  同じ変数・同じ出力・同じプロバイダー要件で動作します。
- **ベストプラクティスの集約**: 「そのリソースを実運用に乗せるために本当は何が必要か」
  （IAM の付与順序、依存関係、API 側の排他制約）をモジュールに閉じ込め、組織の設計知識を標準化します。
- **apply 前に失敗させる**: API 側の制約は `validation` ブロックで表現し、
  `terraform plan` の時点でわかりやすいエラーメッセージにします。

## モジュール一覧

| モジュール | 概要 |
| :--- | :--- |
| [artifact-registry](./modules/google/artifact-registry) | Artifact Registry リポジトリ + IAM + クリーンアップポリシー |
| [cloud-run-job](./modules/google/cloud-run-job) | Cloud Run v2 Job（バッチ処理）+ Secret 参照 + VPC 接続 + 実行権限 |
| [cloud-run-service](./modules/google/cloud-run-service) | Cloud Run v2 Service + Secret Manager 連携 + ヘルスチェック + 呼び出し権限 |
| [cloudbuild-bitbucket-connection](./modules/google/cloudbuild-bitbucket-connection) | Cloud Build と Bitbucket Cloud の接続 + シークレットのアクセス権 |
| [external-lb](./modules/google/external-lb) | 外部 ALB（サーバーレス NEG）+ マネージド証明書 + DNS + Cloud Armor |
| [github-oidc](./modules/google/github-oidc) | GitHub Actions の Workload Identity 連携（キーレス認証） |
| [postgres-psc](./modules/google/postgres-psc) | Cloud SQL for PostgreSQL（Private Service Connect）+ ユーザー + 資格情報シークレット |
| [service-accounts](./modules/google/service-accounts) | 複数サービスアカウント + IAM ロール + なりすまし許可 |

各モジュールの `README.md` に、使い方・入力・出力・注意事項が揃っています。
一覧はパス順（プロバイダーごとにまとまる順序）で並びます。

## 利用方法

詳細は [docs/module_usage.md](./docs/module_usage.md) を参照してください。以下は要点です。

### パターン A: GitHub リポジトリを直接参照する

改善をリリースタグ経由で取り込めます。複数案件で同じ構成を使い回す場合に向いています。

```hcl
module "artifact_registry" {
  source = "git::https://github.com/brainpad-whiterabbit/terraform-modules.git//modules/google/artifact-registry?ref=v1.0.0"

  environment = {
    project_id = "my-project-id"
  }

  repository = {
    repository_id = "my-docker-repo"
    format        = "DOCKER"
    location      = "asia-northeast1"
  }
}
```

- リポジトリ URL とサブディレクトリの区切りは**スラッシュ 2 つ (`//`)** です。
- `ref` は必ずリリースタグを指定してください（省略するとデフォルトブランチに追従します）。
- 本リポジトリはプライベートです。`terraform init` を実行する環境に GitHub の読み取り権限が必要です。

### パターン B: コピー＆ペーストして自案件で管理する

案件固有の要件が多い場合や、外部依存を持ちたくない場合に向いています。

```bash
# 案件リポジトリのルートで実行
git clone --depth 1 --branch v1.0.0 \
  https://github.com/brainpad-whiterabbit/terraform-modules.git /tmp/terraform-modules
cp -r /tmp/terraform-modules/modules/google/artifact-registry ./modules/artifact-registry
```

```hcl
module "artifact_registry" {
  source = "./modules/artifact-registry"
  # 変数はパターン A と完全に同じ
}
```

> [!IMPORTANT]
> `.tf` ファイルをルートモジュール（`main.tf` があるディレクトリ）に直接展開しないでください。
> 各モジュールは `versions.tf` に自身の `terraform` ブロックを持つため、`required_providers` が
> 重複してエラーになります。必ずサブディレクトリに置いてローカルパスで参照してください。

### プロバイダーの設定（両パターン共通）

モジュールはバージョン制約のみを宣言し、認証情報やデフォルトの project / region は
利用者側のルートモジュールで設定します。`google-beta` を要求するモジュールを使う場合は、
`google-beta` の `provider` ブロックも忘れずに定義してください。

## 開発

```bash
make help                                     # 利用できるタスクの一覧
make hooks                                    # git フック（fmt・規約・コミットメッセージ）を有効にする
make preflight                                # fmt + policy + validate + test + lint（コミット前に実行）
make check                                    # preflight + security（CI と同じ内容）
make fmt-fix                                  # フォーマットの自動修正
make MODULE=modules/google/external-lb test   # 単一モジュールのテスト
make new-module NAME=google/pubsub-topic DESC="概要"   # モジュールの雛形を作る
make next-version REF=origin/develop          # 次のリリースバージョンを確認する
```

必要なのは Terraform CLI (>= 1.10) と Python 3、それに
[mise](https://mise.jdx.dev/) です。tflint / trivy / pre-commit は
[`.tool-versions`](./.tool-versions) で固定したバージョンを `make tools` が入れます。
プロバイダーは `.terraform-plugin-cache/` に共有キャッシュされます。

`make policy` は「README と実装が食い違っていないか」まで検査します。変数や出力を足したら
README の表も更新してください（CI でも同じチェックが走ります）。

リリースは月 1 回、自動で行われます。**毎月 1 日**に `release/vX.Y.Z` が切られて `main` への
リリース PR が作られ、**毎月 4 日**（または手でマージしたとき）にタグ付け・全チェック・
GitHub Release の作成まで自動で進みます（[リリースワークフロー](./docs/release_workflow.md)）。

- [コントリビューションガイド](./CONTRIBUTING.md)
- [コーディング規約](./docs/coding_standards.md)
- [モジュールコントリビューションガイドライン](./docs/module_contribution_guidelines.md)
- [開発ワークフロー](./docs/development_workflow.md)
- [リリースワークフロー](./docs/release_workflow.md)
- [メンテナンスガイド](./docs/maintenance.md)

## 貢献

このリポジトリへの貢献を歓迎します。新しいモジュールの追加、既存モジュールの改善、
バグ修正、ドキュメントの更新など、あらゆる貢献をお待ちしています。
進め方は [CONTRIBUTING.md](./CONTRIBUTING.md) にまとめています。

モジュールを修正する際は、[モジュールコントリビューションガイドライン](./docs/module_contribution_guidelines.md)
の「8. 後方互換性とリリース」に従い、破壊的変更かどうかを判断してください。
