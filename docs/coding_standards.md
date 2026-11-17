# コーディング規約

このドキュメントは、[HashiCorp Terraform Style Guide](https://developer.hashicorp.com/terraform/language/style) をベースに、`terraform-modules`リポジトリにおけるTerraformコードのコーディング規約を定めるものです。一貫性のある、読みやすく、保守しやすいコードを維持するために、すべてのコントリビューターはこの規約に従ってください。

## 1. コードスタイル

### 1.1. フォーマットと検証

-   **`terraform fmt`**: コードをバージョン管理にコミットする前に、必ず `terraform fmt -recursive` を実行し、コードのフォーマットを統一してください（`make fmt-fix`）。
-   **`terraform validate`**: コードが構文的に有効で、内部的に一貫していることを確認するために `terraform validate` を実行してください（`make validate`）。
-   **リンター**: `TFLint` を [.tflint.hcl](../.tflint.hcl) の設定で実行します（`make lint`）。
    公式ルールセットの全ルールと Google プロバイダー向けルールセットを有効にしており、
    未使用の宣言・命名規則・非推奨の構文などを検出します。
-   **規約チェック**: この規約のうち機械的に判定できるものは `make policy` が検査します
    （必須ファイル、`provider` ブロックの有無、バージョン制約、README と実装の整合など）。
    検査項目の一覧は [maintenance.md](./maintenance.md#6-規約チェックmake-policy-が見ているもの) を参照してください。

これらは `make preflight` にまとめてあり、CI でも同じチェックが走ります。

### 1.2. ファイル命名規則

コードベースが大きくなった場合、以下の命名規則に従ってファイルを分割することを推奨します。

-   `main.tf`: 主要なリソースとデータソースを定義します。
-   `variables.tf`: 変数 (`variable`) ブロックを定義します。
-   `outputs.tf`: 出力 (`output`) ブロックを定義します。
-   `versions.tf`: `terraform` ブロック（`required_version` と `required_providers`）を定義します。
-   `locals.tf`: ローカル値 (`locals`) を定義します。
-   `moved.tf`: リソースアドレスの変更に伴う `moved` ブロックを定義します。

> [!IMPORTANT]
> **モジュール内に `provider` ブロック（認証情報や project / region の既定値）を書いてはいけません。**
> これは利用者側のルートモジュールの責務です。モジュールは `versions.tf` の
> `required_providers` でバージョン制約を宣言するだけにします。
> 詳細は [module_contribution_guidelines.md](./module_contribution_guidelines.md) を参照してください。

### 1.3. 命名規則

命名は、リソースの目的が明確にわかるように、具体的かつ一貫性のあるものにします。

-   **言語**: すべての命名は英語（小文字）で行います。
-   **区切り文字**: 単語の区切りにはアンダースコア `_` を使用します (snake_case)。
-   **リソース名**:
    -   リソースの役割を示す名詞を使用します。
    -   リソースタイプを名前に含めないでください (例: `aws_s3_bucket` のリソース名は `app_bucket` であり、`app_s3_bucket` ではありません)。
    -   リソースタイプと名前はダブルクォートで囲みます。

    ```hcl
    # ✅ Good
    resource "google_project_service" "enable_cloud_run_api" {
      # ...
    }

    # ❌ Bad
    resource google_project_service "enable_cloud_run_api-project-service" {
      # ...
    }
    ```

### 1.4. 変数 (Variables)

-   すべての変数には `type` と `description` を必ず指定してください。
-   `any` 型は使わず、ネストしたオブジェクトも明示的に型付けしてください。
-   パスワードや秘密鍵などの機密情報を含む変数には `sensitive = true` を設定してください。
    ただし「シークレットの**名前**」のように秘密ではない値に `sensitive` を付けないでください。

設計の詳細（`optional()` の使いどころ、`validation` で表現する API 制約、`error_message` の
書き方、Terraform 1.10 が条件式を短絡評価しないことへの対処）は
[module_contribution_guidelines.md](./module_contribution_guidelines.md) の
「4. 変数の設計」を参照してください。

### 1.5. 出力 (Outputs)

-   すべての出力には `description` を必ず指定してください。

    ```hcl
    output "service_url" {
      description = "The URL of the deployed Cloud Run service."
      value       = google_cloud_run_v2_service.main.uri
    }
    ```

### 1.6. コメント

-   コード自体で意図が明確に伝わるように記述し、コメントは必要な場合にのみ使用します。
-   コメントを追加する場合は、「何をしているか」ではなく、「なぜそうしているか」という理由を説明することに重点を置きます。
-   単一行、複数行ともに `#` を使用します。

## 2. ワークフロースタイル

### 2.1. バージョン固定とモジュール構成

`required_version` とプロバイダーのバージョン制約、モジュールの配置場所は
リポジトリ全体で揃えます。ルールと `versions.tf` のテンプレートは
[module_contribution_guidelines.md](./module_contribution_guidelines.md) の
「2. モジュール構成」「3. バージョン制約」にあります（`make policy` が M003 / M004 / M005 で
検査します）。

### 2.2. `.gitignore`

バージョン管理に含めるべきでないファイルを `.gitignore` で除外します。

-   **除外対象**:
    -   `terraform.tfstate` 及び `terraform.tfstate.*`
    -   `.terraform/` ディレクトリ
    -   `-out` フラグで作成されたプランファイル
    -   機密情報を含む `.tfvars` ファイル
    -   `.terraform.lock.hcl`
-   **コミット対象**:
    -   すべての `.tf` ファイル（`main.tftest.hcl` を含む）
    -   `README.md`

`.terraform.lock.hcl` を除外している理由は
[module_contribution_guidelines.md](./module_contribution_guidelines.md) の
「`.terraform.lock.hcl` はコミットしない」にあります。

GitHubの [Terraform .gitignore](https://github.com/github/gitignore/blob/main/Terraform.gitignore) ファイルを参考にしてください。
