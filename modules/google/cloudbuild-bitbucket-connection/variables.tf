variable "environment" {
  description = "環境設定。Cloud Build 接続は environment.region に作成されます。"
  type = object({
    project_id   = string
    region       = string
    project_name = optional(string)
    stack_name   = optional(string)
  })

  # 後方互換のため既定値は null。プロジェクト ID とリージョンは environment か、
  # 非推奨の project_id / region 変数のどちらかで指定する（下の validation で検査する）。
  default = null

  validation {
    condition     = var.environment != null || (var.project_id != null && var.region != null)
    error_message = "environment、または非推奨の project_id と region の両方を指定してください。environment = { project_id = \"...\", region = \"...\" } を推奨します。"
  }

  validation {
    condition     = var.environment == null || (var.project_id == null && var.region == null)
    error_message = "environment と、非推奨の project_id / region は同時に指定できません。environment だけを使ってください。"
  }

  validation {
    condition     = var.environment == null || can(regex("^[a-z]+-[a-z]+[0-9]+$", var.environment.region))
    error_message = "environment.region はリージョン名 (例: asia-northeast1) を指定してください。"
  }
}

variable "project_id" {
  description = "**非推奨**: `environment.project_id` を使用してください。デプロイ先の Google Cloud プロジェクト ID。"
  type        = string
  default     = null
}

variable "project_number" {
  description = <<-EOT
    Google Cloud プロジェクトの番号。Cloud Build サービスエージェント
    (service-<project_number>@gcp-sa-cloudbuild.iam.gserviceaccount.com) の特定と、
    シークレットバージョンの完全修飾名の組み立てに使用します。
    省略した場合は google_project データソースから取得します。
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.project_number == null || can(regex("^[0-9]+$", coalesce(var.project_number, "0")))
    error_message = "project_number は数字のみで指定してください。"
  }
}

variable "region" {
  description = "**非推奨**: `environment.region` を使用してください。Cloud Build 接続を作成するリージョン (例: asia-northeast1)。"
  type        = string
  default     = null

  validation {
    condition     = var.region == null || can(regex("^[a-z]+-[a-z]+[0-9]+$", coalesce(var.region, "")))
    error_message = "region はリージョン名 (例: asia-northeast1) を指定してください。"
  }
}

variable "bitbucket_config" {
  description = <<-EOT
    Bitbucket Cloud 接続の設定。
    *_secret には Secret Manager の**シークレット ID**（値ではなく名前）を指定します。
    シークレット本体はこのモジュールでは作成しません。事前に作成しておいてください。
  EOT
  type = object({
    workspace          = string
    connection_name    = string
    admin_token_secret = string
    read_token_secret  = string
    webhook_secret     = string

    # 指定した場合、その Bitbucket リポジトリを接続に紐付ける
    # (google_cloudbuildv2_repository) リソースも作成します。
    repo_slug = optional(string)

    # 参照するシークレットのバージョン。通常は latest のままで問題ありません。
    secret_version = optional(string, "latest")
  })

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.bitbucket_config.connection_name))
    error_message = "bitbucket_config.connection_name は小文字英字始まり、小文字英数字とハイフンのみ、63文字以内で指定してください。"
  }

  validation {
    condition = alltrue([
      for secret in [
        var.bitbucket_config.admin_token_secret,
        var.bitbucket_config.read_token_secret,
        var.bitbucket_config.webhook_secret,
      ] : !can(regex("^projects/", secret))
    ])
    error_message = "*_secret には完全修飾名ではなくシークレット ID (名前のみ) を指定してください。"
  }

  validation {
    condition     = length(distinct([var.bitbucket_config.admin_token_secret, var.bitbucket_config.read_token_secret, var.bitbucket_config.webhook_secret])) == 3
    error_message = "admin_token_secret / read_token_secret / webhook_secret には別々のシークレットを指定してください。"
  }
}

variable "additional_secret_accessors" {
  description = <<-EOT
    シークレットに roles/secretmanager.secretAccessor を追加で付与するメンバー。
    このモジュールは authoritative な google_secret_manager_secret_iam_policy を使うため、
    モジュール外で付与したバインディングは削除されます。Cloud Build サービスエージェント以外に
    アクセスを許可したいメンバーは、ここに列挙してポリシーに含めてください。
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for member in var.additional_secret_accessors :
      can(regex("^(user|group|serviceAccount|domain|principal|principalSet):", member))
    ])
    error_message = "additional_secret_accessors は 'serviceAccount:...' のように IAM プリンシパルの接頭辞付きで指定してください。"
  }
}
