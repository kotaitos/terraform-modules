# Cloud SQL for PostgreSQL (Private Service Connect) Module

Private Service Connect (PSC) 経由でのみ到達できる Cloud SQL for PostgreSQL インスタンスを、
データベース・ユーザー・資格情報のシークレット・プライベート DNS まで含めて構築します。

## なぜこのモジュールを使うのか

公式の `terraform-google-modules/sql-db` はインスタンス作成には優れていますが、
PSC 構成を成立させるには利用者側で以下を組み立てる必要があります。

- インスタンス側で `psc_enabled` と `allowed_consumer_projects` を設定する
- VPC 側に内部 IP を予約し、`load_balancing_scheme = ""` の転送ルールで
  インスタンスのサービスアタッチメントに向ける（PSC 特有の指定）
- Cloud SQL が払い出す `<uid>.<region>.sql.goog.` という DNS 名を、その内部 IP に
  解決させるプライベート DNS ゾーンとレコードを作る
- ユーザーのパスワードを生成し、Secret Manager に保存してアプリに読ませる

このモジュールはこれらを 1 つのモジュールコールにまとめ、パスワードは
`random_password` で生成して Secret Manager に JSON (`{"username":..,"password":..}`) として
保存します。**パスワードを Terraform コードに書く必要はありません。**

## 構成リソース

```mermaid
graph TD
    subgraph "VPC (利用者側)"
        ADDR["google_compute_address<br/>(内部 IP を予約)"]
        FR["google_compute_forwarding_rule<br/>(load_balancing_scheme = \"\")"]
        ZONE["google_dns_managed_zone<br/>(private)"]
        REC["google_dns_record_set (A)"]
    end

    subgraph "Cloud SQL (Google 管理側)"
        INST["google_sql_database_instance<br/>(psc_enabled = true)"]
        DB["google_sql_database"]
        USER["google_sql_user"]
    end

    subgraph "Secret Manager"
        PWD["random_password"]
        SEC["google_secret_manager_secret<br/>+ version (username/password の JSON)"]
        SIAM["google_secret_manager_secret_iam_member<br/>(roles/secretmanager.secretAccessor)"]
    end

    FR -- "target = psc_service_attachment_link" --> INST
    FR --> ADDR
    REC -- "dns_name -> 内部 IP" --> ADDR
    ZONE --> REC
    INST --> DB
    INST --> USER
    PWD --> USER
    PWD --> SEC
    SEC --> SIAM
```

## 使い方

利用パターンの詳細・プライベートリポジトリの認証・アップグレード手順は
[docs/module_usage.md](../../../docs/module_usage.md) を参照してください。

### パターン A: GitHub 参照

```hcl
module "postgres" {
  source = "git::https://github.com/kotaitos/terraform-modules.git//modules/google/postgres-psc?ref=main"

  environment = {
    project_id = "my-project-id"
    region     = "asia-northeast1"
  }

  database = {
    instance_name = "main"
    database_name = "app"

    users = [
      { name = "app" },
    ]

    psc_config = {
      network_config = {
        network_name    = "main"
        subnetwork_name = "main"
      }
    }
  }
}
```

### パターン B: コピー＆ペースト

`modules/google/postgres-psc` をディレクトリごと案件リポジトリの `modules/postgres-psc` に
コピーし、ローカルパスで参照します。変数はパターン A と完全に同じです。

```hcl
module "postgres" {
  source = "./modules/postgres-psc"

  environment = {
    project_id = "my-project-id"
    region     = "asia-northeast1"
  }

  database = {
    instance_name = "main"
    database_name = "app"
    users         = [{ name = "app" }]

    psc_config = {
      network_config = {
        network_name    = "main"
        subnetwork_name = "main"
      }
    }
  }
}
```

### 本番向けのフル構成

```hcl
module "postgres" {
  source = "git::https://github.com/kotaitos/terraform-modules.git//modules/google/postgres-psc?ref=main"

  environment = {
    project_id = "my-project-id"
    region     = "asia-northeast1"
  }

  database = {
    instance_name = "main"
    database_name = "app"
    version       = "POSTGRES_17"
    tier          = "db-custom-2-7680"

    users = [
      { name = "app" },
      { name = "readonly", secret_id = "postgres-readonly-credentials" },
    ]

    # 生成した資格情報をアプリのサービスアカウントに読ませる
    secret_accessor_members = [
      "serviceAccount:app@my-project-id.iam.gserviceaccount.com",
    ]

    settings = {
      deletion_protection = true
      availability_type   = "REGIONAL" # 高可用性
      disk_size           = 20
      disk_autoresize     = true
      ssl_mode            = "ENCRYPTED_ONLY"

      backup_configuration = {
        enabled                        = true
        start_time                     = "18:00" # UTC
        point_in_time_recovery_enabled = true
        retained_backups               = 14
      }

      maintenance_window = {
        day  = 7 # 日曜
        hour = 19
      }

      insights_config = {
        query_insights_enabled = true
      }

      database_flags = [
        { name = "max_connections", value = "200" },
      ]

      user_labels = {
        env = "production"
      }
    }

    psc_config = {
      network_config = {
        network_name    = "main"
        subnetwork_name = "main"
      }
    }

    # 同一 VPC に 2 つ目のインスタンスを作る場合は、ゾーン名が衝突しないよう明示する
    dns_config = {
      zone_name = "main-postgres-psc-zone"
    }
  }
}
```

### アプリから接続する

```hcl
module "api" {
  source = "git::https://github.com/kotaitos/terraform-modules.git//modules/google/cloud-run-service?ref=main"

  environment = { project_id = "my-project-id", region = "asia-northeast1" }

  service = {
    service_name          = "api"
    image                 = "asia-northeast1-docker.pkg.dev/my-project-id/app/api:v1"
    service_account_email = "app@my-project-id.iam.gserviceaccount.com"

    # PSC は VPC 内からのみ到達できるため Direct VPC egress が必要
    vpc_access = {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces = [{
        network    = "projects/my-project-id/global/networks/main"
        subnetwork = "projects/my-project-id/regions/asia-northeast1/subnetworks/main"
      }]
    }

    env_vars = {
      DB_HOST = { value = module.postgres.private_ip_address }
      DB_NAME = { value = module.postgres.database_name }
    }

    # 資格情報は Secret Manager から読む
    secret_env_vars = {
      DB_CREDENTIALS = { secret_id = module.postgres.user_credentials_secret_ids["app"] }
    }
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | 環境設定。 | `object` | n/a | yes |
| database | Cloud SQL for PostgreSQL の設定。 | `object` | n/a | yes |

### `environment`

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_id | デプロイ先の Google Cloud プロジェクト ID。 | `string` | n/a | yes |
| region | インスタンスを作成するリージョン。 | `string` | n/a | yes |
| project_name | プロジェクト名。このモジュールでは未使用。 | `string` | `null` | no |
| stack_name | スタック名。このモジュールでは未使用。 | `string` | `null` | no |

### `database`

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| instance_name | インスタンス名。38 文字以内（関連リソース名の接頭辞に使う）。 | `string` | n/a | yes |
| database_name | 作成するデータベース名。 | `string` | n/a | yes |
| psc_config | PSC のネットワーク設定。 | `object` | n/a | yes |
| version | PostgreSQL のバージョン。 | `string` | `"POSTGRES_17"` | no |
| tier | マシンタイプ。 | `string` | `"db-f1-micro"` | no |
| users | 作成する組み込みユーザー。パスワードは自動生成される。 | `list(object)` | `[]` | no |
| password_length | 生成するパスワードの長さ。 | `number` | `16` | no |
| secret_accessor_members | 資格情報シークレットに `roles/secretmanager.secretAccessor` を付与するメンバー。 | `list(string)` | `[]` | no |
| service_account_email_address | **非推奨**: `secret_accessor_members` を使用。単一サービスアカウント指定の旧インターフェース。 | `string` | `null` | no |
| settings | インスタンスの設定。 | `object` | `{}` | no |
| dns_config | プライベート DNS ゾーンの設定。 | `object` | `{}` | no |

### `database.users[*]`

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | データベースユーザー名。`secret_id` を省略する場合は、Secret Manager のシークレット ID に使える文字（英大小文字・数字・`-`・`_`）だけで指定してください。 | `string` | n/a | yes |
| secret_id | 資格情報を保存するシークレット ID。省略時は `<instance_name>-<name>-credentials`。英大小文字・数字・`-`・`_` のみ、255 文字以内。 | `string` | `null` | no |

### `database.settings`

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| deletion_protection | Terraform と Cloud SQL 両方の削除保護を有効にする。 | `bool` | `false` | no |
| edition | `ENTERPRISE` または `ENTERPRISE_PLUS`。 | `string` | `"ENTERPRISE"` | no |
| activation_policy | `ALWAYS` または `NEVER`。 | `string` | `"ALWAYS"` | no |
| availability_type | `ZONAL` または `REGIONAL`（高可用性）。 | `string` | `"ZONAL"` | no |
| disk_size | ディスクサイズ (GB)。10 以上。 | `number` | `10` | no |
| disk_type | `PD_SSD` または `PD_HDD`。 | `string` | `"PD_SSD"` | no |
| disk_autoresize | 空き容量不足時にディスクを自動拡張する。 | `bool` | `true` | no |
| disk_autoresize_limit | 自動拡張の上限 (GB)。`0` は無制限。 | `number` | `0` | no |
| user_labels | インスタンスに付けるラベル。 | `map(string)` | `{}` | no |
| ssl_mode | 接続に TLS を要求するか。`ALLOW_UNENCRYPTED_AND_ENCRYPTED` / `ENCRYPTED_ONLY` / `TRUSTED_CLIENT_CERTIFICATE_REQUIRED`。既定で TLS を強制する。 | `string` | `"ENCRYPTED_ONLY"` | no |
| time_zone | インスタンスのタイムゾーン。 | `string` | `null` | no |
| backup_configuration | 自動バックアップの設定。 | `object` | `null` | no |
| maintenance_window | メンテナンスウィンドウ (`day`, `hour`, `update_track`)。 | `object` | `null` | no |
| insights_config | Query Insights の設定。 | `object` | `null` | no |
| database_flags | データベースフラグ (`name`, `value`) のリスト。 | `list(object)` | `[]` | no |

### `database.settings.backup_configuration`

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| enabled | 自動バックアップを有効にする。 | `bool` | `false` | no |
| start_time | バックアップ開始時刻 (UTC, `HH:MM`)。 | `string` | `null` | no |
| location | バックアップの保存先ロケーション。 | `string` | `null` | no |
| point_in_time_recovery_enabled | PITR を有効にする（`enabled = true` が前提）。 | `bool` | `false` | no |
| transaction_log_retention_days | トランザクションログの保持日数。 | `number` | `7` | no |
| retained_backups | 保持するバックアップ数。 | `number` | `null` | no |

### `database.settings.maintenance_window`

省略すると Google が任意のタイミングでメンテナンスを実施します。業務影響の小さい時間帯に
固定したい場合に指定してください。

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| day | 曜日 (`1` = 月曜 〜 `7` = 日曜)。 | `number` | `null` | no |
| hour | 時 (UTC, `0`〜`23`)。 | `number` | `null` | no |
| update_track | 更新トラック。`canary`（早期）/ `stable`（既定）/ `week5`（5 週間後）。 | `string` | `null` | no |

### `database.settings.insights_config`

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| query_insights_enabled | Query Insights を有効にする。 | `bool` | `true` | no |
| query_plans_per_minute | 1 分あたりに取得する実行計画の数 (`0`〜`20`)。 | `number` | `null` | no |
| query_string_length | 保存するクエリ文字列の最大長 (`256`〜`4500` バイト)。 | `number` | `null` | no |
| record_application_tags | アプリケーションタグ（コメント）を記録する。 | `bool` | `null` | no |
| record_client_address | クライアントの IP アドレスを記録する。 | `bool` | `null` | no |

### `database.settings.database_flags[*]`

指定できるフラグと値は
[Cloud SQL のフラグ一覧](https://cloud.google.com/sql/docs/postgres/flags)を参照してください。

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | フラグ名 (例: `max_connections`)。 | `string` | n/a | yes |
| value | フラグの値。数値も文字列で指定する。 | `string` | n/a | yes |

### `database.psc_config`

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| network_config | ネットワーク設定。 | `object` | n/a | yes |
| allowed_consumer_projects | PSC 接続を許可するプロジェクト。省略時は自プロジェクトのみ。 | `list(string)` | `null` | no |

### `database.psc_config.network_config`

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| network_name | VPC ネットワーク名。 | `string` | n/a | yes |
| subnetwork_name | PSC エンドポイントの内部 IP を予約するサブネットワーク名。 | `string` | n/a | yes |
| forwarding_rule_name | 転送ルール名。省略時は `<instance_name>-psc-forwarding-rule`。小文字英字始まり、小文字英数字とハイフンのみ、63 文字以内。 | `string` | `null` | no |
| address_name | Compute Address のリソース名。省略時は `<instance_name>-psc-address`。小文字英字始まり、小文字英数字とハイフンのみ、63 文字以内。 | `string` | `null` | no |
| address | **非推奨**: `address_name` を使用。 | `string` | `null` | no |
| ip_address | 予約する内部 IP。省略時はサブネットから自動割り当て。 | `string` | `null` | no |

### `database.dns_config`

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| create_zone | プライベート DNS ゾーンとレコードを作成するか。 | `bool` | `true` | no |
| zone_name | ゾーン名。省略時は `<network_name>-private-zone`。小文字英字始まり、小文字英数字とハイフンのみ、63 文字以内（`network_name` が長い場合は明示指定が必要）。 | `string` | `null` | no |
| ttl | A レコードの TTL。 | `number` | `300` | no |

## Outputs

| Name | Description |
|------|-------------|
| this_google_sql_database_instance | 作成された Cloud SQL インスタンスのリソース全体（sensitive）。 |
| instance_name | インスタンス名。 |
| instance_connection_name | `<project>:<region>:<instance>` 形式の接続名。 |
| instance_self_link | インスタンスの self_link。 |
| dns_name | Cloud SQL が払い出した DNS 名。 |
| psc_service_attachment_link | PSC のサービスアタッチメントのリンク。 |
| private_ip_address | PSC 用に予約した内部 IP アドレス。 |
| database_name | 作成したデータベース名。 |
| user_credentials_secrets | 資格情報シークレットのリソース（sensitive）。 |
| user_credentials_secret_ids | ユーザー名 => シークレット ID のマップ。 |
| dns_managed_zone_name | 作成したプライベート DNS ゾーン名。`create_zone = false` の場合は `null`。 |
| connection_url | 先頭ユーザーでの PostgreSQL 接続 URL（sensitive）。`users` 未指定時は `null`。 |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.10 |
| google | >= 6.0.0, < 8.0.0 |
| random | >= 3.5.0, < 4.0.0 |

## Notes

- **接続は VPC 内からのみ可能です。** パブリック IP は常に無効です。Cloud Run から接続する場合は
  Direct VPC egress か Serverless VPC Access コネクタが必要です。
- **既定で TLS を強制します** (`settings.ssl_mode = "ENCRYPTED_ONLY"`)。PSC 経由の閉域接続でも、
  経路上の傍受に対する防御として暗号化を必須にしています。**TLS を使わないクライアントは
  接続できなくなる**ため、そうしたクライアントがある場合だけ
  `settings.ssl_mode = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"` を明示的に指定してください
  （`null` を渡した場合も既定の `ENCRYPTED_ONLY` が適用されます）。
- パスワードは `random_password` で生成され、**state に平文で保存されます。**
  state のバックエンド（GCS バケットなど）を暗号化し、アクセスを制限してください。
- `password_length` を変更すると全ユーザーのパスワードが再生成され、
  `google_sql_user` と Secret Manager のバージョンが更新されます。
  アプリが `latest` を参照していない場合は接続できなくなるため注意してください。
- `override_special` から URL 予約文字 (`@:/<>&?#%=-`) を除外しています。
  そのため生成パスワードは `postgresql://user:pass@host/db` の形でエスケープ不要です。
- `settings.disk_size` は `lifecycle.ignore_changes` の対象です。`disk_autoresize` で
  自動拡張された容量を Terraform が縮小しようとしないようにしています。
  意図的に拡張する場合は `disk_size` を変更しても plan に差分が出ないため、
  Cloud Console か `gcloud` で変更してください。
- **DNS ゾーン名の既定値は `<network_name>-private-zone` です。** 同一 VPC に複数の
  Cloud SQL インスタンスを作る場合、この名前が衝突して apply が失敗します。
  2 つ目以降は `dns_config.zone_name` を明示してください。
- `deletion_protection` を有効にすると Terraform からの削除が拒否されます。
  削除する場合は先に `false` で apply してください。
- IAM データベース認証（`CLOUD_IAM_USER` / `CLOUD_IAM_SERVICE_ACCOUNT`）は未対応です。
  必要な場合は `google_sql_user` を利用者側で追加してください。
- **PSC の転送ルールには `subnetwork` を指定しません。** `load_balancing_scheme = ""` の
  転送ルールに `subnetwork` を指定すると、Compute API が内部ロードバランサーと解釈して
  apply が `Error 400: Invalid value for field 'resource.loadBalancingScheme': 'INTERNAL'`
  で失敗します。エンドポイントが属するサブネットは
  `psc_config.network_config.subnetwork_name` から作られる `google_compute_address` 側で
  決まります。

## 既存構成からのアップグレード

| 変更 | plan に現れる内容 | 対応 |
| :--- | :--- | :--- |
| DNS ゾーン / レコードが `count` 付きになった | なし（`moved.tf` が state を自動移行） | 不要 |
| `settings.disk_size` が `lifecycle.ignore_changes` の対象になった | なし | 以後 `disk_size` の変更は plan に出ません |
| 資格情報シークレットにラベルが付くようになった | シークレットの**インプレース更新** | 不要 |
| `psc_config` が必須になった | なし | 従来も未指定では動作しなかったため実質的な変更なし |
| `settings.ssl_mode` の既定が `ENCRYPTED_ONLY` になった（**破壊的変更**） | インスタンスの**インプレース更新**（`ssl_mode` が空 → `ENCRYPTED_ONLY`） | TLS で接続するクライアントは対応不要。TLS 非対応のクライアントがある場合は、apply の**前に** `settings.ssl_mode = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"` を指定して従来の挙動を維持してください |
| 転送ルールの `subnetwork` 指定を削除した | なし（`subnetwork` は computed 属性のため、既存リソースがあれば現在の値が維持されます） | 不要。これまで apply が `loadBalancingScheme: 'INTERNAL'` で失敗していた場合は、そのまま apply できるようになります |

### 主な機能追加

- `psc_config.network_config` の `forwarding_rule_name` / `address_name` を省略でき、
  `instance_name` から自動命名するようになった
- `secret_accessor_members` で資格情報シークレットの読み取り権限を付与できるようになった
  （従来 `service_account_email_address` は宣言されていたが未使用だった）
- `users = []`（既定値）でも `connection_url` 出力が壊れなくなった
- `dns_config` で DNS ゾーン名の指定とゾーン作成の無効化ができるようになった
- `allowed_consumer_projects`、`disk_autoresize`、`insights_config`、`ssl_mode`、
  `user_labels`、`retained_backups` の追加
- `validation` による事前チェック（PostgreSQL 以外のバージョン、PITR の前提条件、
  ユーザー名 / シークレット ID の重複など）
