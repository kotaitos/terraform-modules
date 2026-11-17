# モジュールコントリビューションガイドライン

このドキュメントは、`terraform-modules` リポジトリへのモジュールコントリビューションに関する
ガイドラインを定めます。高品質で一貫性のあるモジュールを維持するため、このガイドラインに従ってください。

## 1. モジュール設計の基本方針

- **公式モジュールの活用**: `terraform-google-modules` をはじめとする公式モジュールを積極的に活用します。
- **独自モジュールの提供**: 公式モジュールが存在しない、あるいは複数のリソースを組み合わせて
  特定のユースケースに対応するなど、このリポジトリ独自の価値を提供できる場合に限り開発します。
- **「実運用に必要な一式」をカプセル化する**: 単一リソースの薄いラッパーは作りません。
  そのリソースを本番で動かすために本当は何が必要か（IAM の付与順序、依存関係、
  DNS やネットワークの前提）をモジュール側に閉じ込めます。
- **2 つの利用パターンの両方で動くこと**: GitHub からの直接参照とコピー＆ペーストの
  どちらでも同じように動く必要があります（[module_usage.md](./module_usage.md) 参照）。
  そのため `versions.tf` は必須で、`provider` ブロックはモジュール内に置きません。

## 2. モジュール構成

各モジュールは `./modules/<provider>/<module-name>` に配置し、以下のファイルを持ちます。
`make policy` がこの構成をチェックします。雛形は
`make new-module NAME=<provider>/<module-name> DESC="<1 行の概要>"` で生成できます
（生成直後の状態で `make preflight` が通ります）。雛形はプロバイダーごとに
`templates/module/<provider>/` にあります。

| ファイル | 必須 | 内容 |
| :--- | :--: | :--- |
| `main.tf` | ✅ | リソース・データソース・`locals` の定義 |
| `variables.tf` | ✅ | 入力変数の定義（`type` / `description` / `validation`） |
| `outputs.tf` | ✅ | 出力の定義（`description` 必須） |
| `versions.tf` | ✅ | `required_version` と `required_providers` |
| `README.md` | ✅ | 使い方・入力・出力・注意事項 |
| `main.tftest.hcl` | ✅ | `terraform test` のテスト定義 |
| `locals.tf` | | ロジックが大きい場合に `main.tf` から分離してよい |
| `moved.tf` | | リソースアドレスの変更時に state を自動移行するための `moved` ブロック |

バージョンごとのディレクトリ（`v1/`, `v2/` など）は作りません。バージョンは Git のタグで管理します。

### `provider` ブロックを書かないこと

モジュール内で `provider` ブロック（認証情報や project / region の既定値）を定義してはいけません。
これは利用者側のルートモジュールの責務です。モジュールは `required_providers` で
バージョン制約を宣言するだけにします。

## 3. バージョン制約

### `versions.tf` のテンプレート

```hcl
terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0, < 8.0.0"
    }
  }
}
```

- `required_version` はリポジトリ全体で `>= 1.10` に揃えます。
- プロバイダーは**下限と上限の両方**を指定します。上限がないと、
  破壊的変更を含むメジャーバージョンを勝手に取り込んでしまいます。
- モジュールが実際に使うプロバイダーだけを宣言します。使っていない `google-beta` を
  宣言すると、利用者に不要な `provider "google-beta"` の設定を強いることになります。
- 逆に、`provider = google-beta` を指定するリソースがある場合は**必ず宣言**してください。
  宣言漏れは暗黙の推論に依存し、利用者の構成次第で壊れます。

### `.terraform.lock.hcl` はコミットしない

このリポジトリはモジュールのみを提供します。ロックファイルはルートモジュール（利用者側）が
持つものであり、モジュール側に置いても利用者には使われません。
各モジュールディレクトリに生成されるロックファイルは `terraform test` の副産物なので
`.gitignore` で除外しています。

## 4. 変数の設計

- **プロジェクトとリージョンは `environment` オブジェクトで受け取ります。** モジュールをまたいで
  同じ値の渡し方を揃えるため、全モジュールが次の形を受け取ります（雛形にも入っています）。
  モジュールが使わない属性も `optional` で受け取り、`description` に「このモジュールでは未使用」と
  書きます。リージョンを必ず使うモジュールだけ `region` を必須にします。

  ```hcl
  variable "environment" {
    description = "環境設定。<リソース>は environment.region に作成されます。"
    type = object({
      project_id   = string
      region       = string           # プロジェクト単位のモジュールでは optional(string)
      project_name = optional(string)
      stack_name   = optional(string)
    })
  }
  ```

  モジュール固有の設定は `environment` に足さず、モジュール名と同じ名前の変数に入れてください。
  これは **Google Cloud のモジュールの規約**です。雛形（`templates/module/google/`）に
  入っているので `make new-module` で作れば自動的に揃います。別のプロバイダーを追加する
  場合は、そのプロバイダーで自然な形を雛形に定義してください。

- すべての変数に `type` と `description` を指定します。
- **省略できるものは `optional()` にする**。「実質使わないのに `null` を明示的に渡さないと
  いけない」属性は、利用者にとって負担でありバグの原因になります。
- API 側の制約は `validation` で表現します。特に以下は plan 時に落とせるようにします。
  - 列挙値（`contains([...], var.x)`）
  - 名前の長さ・文字種（`can(regex(...))`）
  - 一意性（`length(x) == length(distinct(x))`）
  - 排他制約（「A と B は同時に指定できない」）
  - 依存制約（「A を有効にするなら B も有効でなければならない」）
- **変数から名前を組み立てるときは、「組み立てた結果」を検査してください。** 変数を 1 つずつ
  検査しても、連結した結果が API の制約を外れることがあります。連結先のサービスによって
  使える文字が違うのが主な原因です。

  ```hcl
  # ❌ Bad: users[*].name だけを見ても、生成されるシークレット ID が不正になりうる
  #         （PostgreSQL のユーザー名にはドットが使えるが、Secret Manager の ID には使えない）
  secret_id = coalesce(user.secret_id, "${var.database.instance_name}-${user.name}-credentials")

  # ✅ Good: 組み立てた結果そのものを検査する
  validation {
    condition = alltrue([
      for user in var.database.users :
      can(regex(
        "^[a-zA-Z0-9_-]{1,255}$",
        coalesce(user.secret_id, "${var.database.instance_name}-${user.name}-credentials")
      ))
    ])
    error_message = "..."
  }
  ```

  よく使う制約:

  | 名前 | 制約 |
  | :--- | :--- |
  | Compute / Cloud DNS のリソース名 | `^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$`（63 文字以内） |
  | Secret Manager のシークレット ID | `^[a-zA-Z0-9_-]{1,255}$` |
  | Cloud Run の環境変数名 | `^[A-Za-z_][A-Za-z0-9_]*$`（C_IDENTIFIER。ハイフン不可） |

- **同じキー空間に入る値は、マップやリストをまたいだ一意性も検査してください。**
  `env_vars` と `secret_env_vars` のように別々の変数から同じ `env` ブロックを作る場合、
  それぞれのマップのキーが一意でも、実際に設定される名前が衝突して apply で失敗します。
- `error_message` には「何が悪いか」だけでなく「どう直すか」を書きます。
- `any` 型は使いません。ネストしたオブジェクトも明示的に型付けします。
- **`null` になりうるオブジェクトの属性には `try()` 経由でアクセスします。**
  最小サポートバージョンである Terraform 1.10 は条件式を短絡評価しないため、
  `var.x.obj == null || var.x.obj.attr != null` のような書き方でも右辺が評価され、
  省略しただけで `Attempt to get attribute from null value` で落ちます。
  新しい Terraform では通ってしまうので、CI の最小バージョンのジョブで検出します。

```hcl
# ❌ Bad: vpc_access を省略しただけで Terraform 1.10 では落ちる
condition = var.job.vpc_access == null || var.job.vpc_access.connector != null

# ✅ Good: どのバージョンでも安全
condition = (
  var.job.vpc_access == null ||
  try(var.job.vpc_access.connector, null) != null
)
```

```hcl
# ✅ Good
validation {
  condition     = var.service.min_instances >= 0 && var.service.min_instances <= var.service.max_instances
  error_message = "service.min_instances は 0 以上かつ max_instances 以下で指定してください。"
}

# ❌ Bad: 何を直せばよいか分からない
validation {
  condition     = var.service.min_instances <= var.service.max_instances
  error_message = "invalid instance count"
}
```

## 5. apply で初めて失敗する書き方を避ける

`terraform plan` と `terraform test` を通っても、apply で初めて落ちる書き方があります。
既知のものは以下にまとめ、機械的に判定できるものは `make policy` で検査しています。

### `count` / `for_each` に apply 時の値を使わない

`count` と `for_each` は plan 時に確定していなければなりません。リソースの属性
（`self_link`、`id` など）から導出した値を使うと、
`The "count" value depends on resource attributes that cannot be determined until apply`
というエラーになり、**初回 apply が必ず失敗します**。

分岐の判定には変数から導出した値だけを使ってください。

```hcl
# ❌ Bad: 証明書の self_link は apply 時にしか決まらない
locals {
  is_https_enabled = local.effective_certificate_self_link != null
}
resource "google_compute_target_https_proxy" "main" {
  count = local.is_https_enabled ? 1 : 0
}

# ✅ Good: 変数だけから決まる
locals {
  is_https_enabled = length(var.domain_names) > 0 || var.ssl_certificate_self_link != null
}
```

### Private Service Connect の転送ルールに `subnetwork` を指定しない

`load_balancing_scheme = ""` の `google_compute_forwarding_rule` は Private Service Connect
（PSC）のエンドポイントを意味します。ここに `subnetwork` を指定すると、Compute API が内部
ロードバランサーの転送ルールと解釈して `loadBalancingScheme` を `INTERNAL` と見なし、apply が
次のエラーで失敗します。

```text
Error 400: Invalid value for field 'resource.loadBalancingScheme': 'INTERNAL'.
Invalid field set in Private Service Connect Forwarding Rule.
```

エンドポイントが属するサブネットは、転送ルールが参照する予約済み内部 IP
（`google_compute_address`）側の `subnetwork` で決まるため、転送ルールでの指定は不要です。

```hcl
# ❌ Bad: subnetwork があると apply が INTERNAL のエラーで落ちる
resource "google_compute_forwarding_rule" "main" {
  network               = local.network_config.network_name
  subnetwork            = local.network_config.subnetwork_name
  ip_address            = google_compute_address.main.self_link
  load_balancing_scheme = ""
  target                = google_sql_database_instance.main.psc_service_attachment_link
}

# ✅ Good: サブネットは google_compute_address 側で決める
resource "google_compute_address" "main" {
  address_type = "INTERNAL"
  subnetwork   = local.network_config.subnetwork_name
}

resource "google_compute_forwarding_rule" "main" {
  network               = local.network_config.network_name
  ip_address            = google_compute_address.main.self_link
  load_balancing_scheme = ""
  target                = google_sql_database_instance.main.psc_service_attachment_link
}
```

`subnetwork` は computed 属性なので plan 時の値が未知になり、`terraform test` の `assert` では
検証できません（`Unknown condition value` になります）。この落とし穴は
`postgres-psc/main.tf` のコメントとしても残してあります。

## 6. テスト (`main.tftest.hcl`)

すべてのモジュールに `main.tftest.hcl` を置き、`terraform test` が成功する状態を維持します。
`mock_provider` を使うため、実際の Google Cloud リソースは作成されません。

最低限、以下の `run` ブロックを用意します（`run` の名前は内容が伝わるものであれば自由ですが、
**正常系 2 つ以上**と **`expect_failures` を使ったテスト 1 つ以上**、そして `mock_provider` の
使用は `make policy` が検査します）。

1. **最小構成**: 必須変数のみを渡し、既定値が意図どおりであることを確認する。
   特に「省略したときにリソースが作られないこと」（`length(...) == 0`）を明示的に検証します。
2. **フル構成**: 主要なオプションをすべて指定し、値が正しく反映されることを確認する。
3. **`reject_*`**: `expect_failures` で `validation` が実際に落ちることを確認する。

```hcl
run "reject_min_greater_than_max_instances" {
  command = plan
  module { source = "./" }
  variables {
    service = { /* ... */ min_instances = 5, max_instances = 2 }
  }
  expect_failures = [var.service]
}
```

### テストを書くときのはまりどころ

- `command = plan` では **apply 時に決まる値をアサートできません**（`Unknown condition value`）。
  設定から決まる値、またはリソースの個数・キーの集合を検証してください。
- プロバイダーがセット (`TypeSet`) として扱うブロックは添字アクセスできません。
  `for` 式と `if` 節を使ってください。
- `keys(...)` はタプルを返すため `== ["a"]` のようなリストとの比較は型不一致になります。
  `length(...)` と `contains(...)` を組み合わせてください。
- `mock_provider` は computed な属性にランダム値を生成します。JSON など形式が決まっている
  属性（`google_iam_policy.policy_data` など）は `mock_data` で明示してください。
- `run` ブロックを追加したら `terraform init` を再実行する必要があります
  （`make test` は毎回 init するので不要です）。
- **アサーションでも短絡評価に頼らないでください。** `env.name == "X" && env.value_source[0]...`
  のような式は、Terraform 1.10 では条件を満たさない要素に対しても添字アクセスが評価され、
  `Invalid index` で落ちます。`try(env.value_source[0].secret_key_ref[0].version, null) == "latest"`
  のように `try()` で包みます。

## 7. ドキュメント (`README.md`)

各モジュールの `README.md` は以下の構成に揃えます。見出しの有無、Inputs / Outputs の表と
実装の一致、Requirements と `versions.tf` の一致、2 つの利用パターンの記載は
`make policy` が検査します（変数を追加して README を直し忘れると CI で落ちます）。

1. **タイトルと概要**: 何を作るモジュールか 1〜2 文で。
2. **なぜこのモジュールを使うのか**: 素の `resource` で書いた場合に何が面倒／危険なのかを書き、
   このモジュールがそれをどう解決するかを示します。ここが薄いモジュールは、
   そもそも作る価値があるかを再検討してください。
3. **構成リソース**: `mermaid` の図で依存関係を示します。
4. **使い方**: **パターン A（GitHub 参照）とパターン B（コピー＆ペースト）の両方**を載せ、
   [module_usage.md](./module_usage.md) にリンクします。加えてフル構成の例を示します。
5. **Inputs**: トップレベルの表に加えて、**`object` になっているすべての階層**に
   `### <パス>` の見出し（パスはバッククォートで囲む）と表を作ります。パスはコレクションの
   段ごとに `[*]` を付けた `neg_backends[*].cloud_armor_config.rules[*]` のような表記にします。
   表の項目が型と一致していることは `make policy`（D006 / D007）が検査します。
   属性が同じ複数のパスは、見出しに両方を書いて 1 つの表にまとめてもかまいません
   （`service.startup_probe` と `service.liveness_probe` が該当します）。
6. **Outputs**: 名前と説明の表。
7. **Requirements**: Terraform とプロバイダーのバージョン（`versions.tf` と一致させる）。
8. **Notes**: 制約・前提・落とし穴。特に以下は必ず書きます。
   - `deletion_protection` のように、削除時に追加操作が必要なもの
   - state に平文で保存される機密情報
   - authoritative な IAM リソースを使っている場合の副作用
   - `lifecycle.ignore_changes` の対象と、その結果 Terraform が検知しない変更

## 8. 後方互換性

既存モジュールを修正する際は、既に利用している案件への影響を最小化します。
`ref` を上げたときに `terraform plan` へ予期しない差分が出ないことが重要です。

### 非破壊的にできること

- `optional()` な属性を追加する
- 必須属性を `optional()` に緩める
- 出力を追加する
- `validation` を追加する（ただし既存の正しい設定を落とさないこと）

### 破壊的変更

- 変数の削除・リネーム・必須化
- リソースの再作成やダウンタイムを伴う変更（リソース名の変更、`load_balancing_scheme` の変更など）

破壊的変更を行う場合は、そのモジュールの README の Notes に移行手順を書いてください。

### リソースアドレスを変えるときは `moved` ブロックを使う

リソース名の整理やリファクタリングでアドレスが変わる場合、`moved` ブロックを追加すれば
利用者が `terraform state mv` を実行せずに済みます。いずれ削除する旨をコメントに書いておきます。

```hcl
moved {
  from = google_cloudbuildv2_connection.bitbucket_connection
  to   = google_cloudbuildv2_connection.main
}
```

`for_each` のキーが動的に決まる場合は `moved` で表現できません。その場合は
README の Notes に「plan に差分が出るが実害はない」ことを明記してください。

## 9. 新規モジュール追加のチェックリスト

- [ ] `modules/<provider>/<module-name>/` に配置した（`make new-module` で雛形を作れる）
- [ ] 「2. モジュール構成」の必須ファイルが揃っている（`make policy` が通る）
- [ ] `versions.tf` に `required_version` と、実際に使うプロバイダーだけを宣言した
- [ ] モジュール内に `provider` ブロックを書いていない
- [ ] すべての変数に `type` と `description` があり、省略可能なものは `optional()` にした
- [ ] API 側の制約を `validation` で表現した
- [ ] `count` / `for_each` が apply 時の値に依存していない
- [ ] apply で初めて落ちる API 制約（PSC の転送ルールなど）を踏んでいない
- [ ] 正常系 2 つ以上と `reject_*`（`expect_failures`）のテストを書いた
- [ ] README に 2 つの利用パターンと Notes を書き、Inputs / Outputs / Requirements を実装と一致させた
- [ ] `make preflight` が通る
- [ ] ルート `README.md` のモジュール一覧に追記した（`make new-module` を使った場合は自動で追記される）
