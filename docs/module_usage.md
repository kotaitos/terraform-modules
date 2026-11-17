# モジュールの利用方法

本リポジトリのモジュールは、次の 2 つのユースケースの**どちらでもそのまま動く**ように設計されています。

| | パターン A: GitHub 参照 | パターン B: コピー＆ペースト |
| :--- | :--- | :--- |
| 記述 | `source = "git::https://github.com/...//modules/google/xxx?ref=main"` | `source = "./modules/xxx"` |
| バージョン管理 | `ref` のコミット SHA で固定。更新は `ref` の書き換え | 案件リポジトリ側で管理。更新は再コピー |
| アップストリームの改善 | `ref` を上げるだけで取り込める | 手動で差分を取り込む必要がある |
| 案件固有のカスタマイズ | 不可（PR で本体を改善する） | 自由に変更できる |
| 前提 | 認証不要（公開リポジトリ） | 認証不要 |
| 向いているケース | 複数案件で同じ構成を使い回す / 改善を共有したい | 案件固有の要件が多い / 外部依存を持ちたくない |

どちらを選んでも、モジュール側のインターフェース（変数・出力）と要求プロバイダーバージョンは同一です。

## プロジェクトとリージョンの渡し方

全モジュールが `environment` オブジェクトでプロジェクトとリージョンを受け取ります。
モジュールを並べて書くときに、同じ値の渡し方が揃うようにするためです。

```hcl
module "postgres" {
  source = "git::https://github.com/kotaitos/terraform-modules.git//modules/google/postgres-psc?ref=main"

  environment = {
    project_id = "my-project-id"
    region     = "asia-northeast1"
  }
  # ...
}
```

`external-lb` / `github-oidc` / `cloudbuild-bitbucket-connection` は、以前は
`project_id` / `region` をトップレベルで受け取っていました。これらは**非推奨として残しています**
（削除は将来の MAJOR リリースで、移行手順をリリースノートに書いてから行います）。
`environment` と非推奨のフラット変数を同時に指定すると `terraform plan` でエラーになります。

---

## パターン A: GitHub リポジトリを直接参照する

各モジュールディレクトリを `source` に指定します。リポジトリ URL とサブディレクトリの区切りは
**スラッシュ 2 つ (`//`)** です。1 つだけだとリポジトリ URL の一部と解釈され、取得に失敗します。

```hcl
module "artifact_registry" {
  source = "git::https://github.com/kotaitos/terraform-modules.git//modules/google/artifact-registry?ref=main"

  # ... 変数
}
```

### `ref` を固定する

`ref` を省略するとデフォルトブランチの HEAD を取得するため、`terraform init` を実行した時期に
よって構成が変わってしまいます。構成を固定したい場合は**コミット SHA を指定してください**
（このリポジトリはリリースタグを運用していません）。

```hcl
# ✅ Good: コミット SHA で固定（再現性がある）
source = "git::https://github.com/kotaitos/terraform-modules.git//modules/google/external-lb?ref=<commit-sha>"

# ⚠️ main に追従する（常に最新。取り込み時期で構成が変わる）
source = "git::https://github.com/kotaitos/terraform-modules.git//modules/google/external-lb?ref=main"

# ❌ Bad: ref 自体を省略する
source = "git::https://github.com/kotaitos/terraform-modules.git//modules/google/external-lb"
```

### アップグレード手順

`terraform init` はモジュールを `.terraform/modules` にキャッシュするため、`ref` を書き換えた
あとは `-upgrade` が必要です。

```bash
# source の ref を書き換えたあと
terraform init -upgrade
terraform plan   # 差分を必ず確認する
```

---

## パターン B: コピー＆ペーストして自案件で管理する

モジュールディレクトリを**ディレクトリ単位で**案件リポジトリにコピーし、ローカルパスで参照します。

```bash
# 案件リポジトリのルートで実行
git clone --depth 1 --branch v1.0.0 \
  https://github.com/kotaitos/terraform-modules.git /tmp/terraform-modules

mkdir -p modules
cp -r /tmp/terraform-modules/modules/google/artifact-registry ./modules/artifact-registry

# どのバージョンから取り込んだか分かるようにしておく
echo "copied from terraform-modules v1.0.0" > ./modules/artifact-registry/ORIGIN
```

```hcl
module "artifact_registry" {
  source = "./modules/artifact-registry"

  # ... 変数
}
```

> [!IMPORTANT]
> `.tf` ファイルを**ルートモジュール（`main.tf` があるディレクトリ）に直接**コピーしないでください。
> 各モジュールは `versions.tf` に自身の `terraform` ブロックを持っているため、ルートモジュールの
> `terraform` ブロックと `required_providers` が重複してエラーになります。
> 必ず `modules/<名前>/` のようなサブディレクトリに置き、`source` にローカルパスを指定してください。
> どうしてもルートに直接展開したい場合は、コピー後に `versions.tf` を削除し、ルート側の
> `required_providers` がモジュールの要求バージョンを満たしていることを確認してください。

---

## プロバイダーの設定（両パターン共通）

モジュール側は `required_providers` でバージョン制約のみを宣言し、`provider` ブロック
（認証情報やデフォルトの project / region）は**定義しません**。これはモジュールの責務ではなく、
利用者側のルートモジュールで設定します。

```hcl
# 案件リポジトリのルートモジュール
terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.14"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
```

`google-beta` を要求するモジュール（各モジュールの README の Requirements を参照）を使う場合は、
`google-beta` プロバイダーも合わせて宣言・設定してください。宣言しない場合 Terraform は
空の設定でデフォルトプロバイダーを生成するため、`google` 側だけに認証情報を書いていると
認証エラーになります。

```hcl
provider "google-beta" {
  project = var.project_id
  region  = var.region
}
```

## state に平文で入る機密情報

いくつかのモジュールは、生成した機密情報を **Terraform の state に平文で書き込みます。**
Terraform の仕組み上避けられません。

| モジュール | state に入るもの |
| :--- | :--- |
| [postgres-psc](../modules/google/postgres-psc) | `random_password` で生成したデータベースユーザーのパスワード |
| [service-accounts](../modules/google/service-accounts) | `secret_manager` を指定した場合に発行されるサービスアカウントの秘密鍵 |
| [cloud-run-service](../modules/google/cloud-run-service) | `secret_env_vars[*].secret_data` に渡した値 |

**これらを使う場合は、state のバックエンド（GCS バケットなど）を暗号化し、閲覧できる人を
限定してください。** バケットのバージョニングを有効にしている場合は、古い世代にも残ります。
