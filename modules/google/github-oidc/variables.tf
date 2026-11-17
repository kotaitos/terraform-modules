variable "environment" {
  description = "環境設定。このモジュールは project_id のみを使用しますが、他モジュールとインターフェースを揃えるため同じ形を受け取ります。"
  type = object({
    project_id   = string
    project_name = optional(string)
    region       = optional(string)
    stack_name   = optional(string)
  })

  # 後方互換のため既定値は null。プロジェクト ID は environment か、非推奨の
  # project_id 変数のどちらかで必ず指定する（下の validation で検査する）。
  default = null

  validation {
    condition     = var.environment != null || var.project_id != null
    error_message = "environment または project_id（非推奨）のどちらかを指定してください。environment = { project_id = \"...\" } を推奨します。"
  }

  validation {
    condition     = var.environment == null || var.project_id == null
    error_message = "environment と project_id（非推奨）は同時に指定できません。environment だけを使ってください。"
  }
}

variable "project_id" {
  description = "**非推奨**: `environment.project_id` を使用してください。デプロイ先の Google Cloud プロジェクト ID。"
  type        = string
  default     = null
}

variable "github_oidc_config" {
  description = "GitHub OIDC プロバイダーの設定。"
  type = object({
    # repository (単一) または repositories (複数) のどちらかを指定する。
    repository   = optional(string)
    repositories = optional(list(string), [])

    # 1 プロジェクトに複数の Pool を作る場合は変更する。
    pool_id     = optional(string, "github-actions")
    provider_id = optional(string, "github-actions-provider")

    pool_display_name     = optional(string, "GitHub Actions Pool")
    provider_display_name = optional(string, "GitHub Actions Provider")
    description           = optional(string, "Used by GitHub Actions")

    # リポジトリ条件に AND で追加する CEL 式。
    # 例: "assertion.ref == 'refs/heads/main'" (main ブランチからのみ許可)
    #     "assertion.environment == 'production'" (production environment からのみ許可)
    extra_attribute_condition = optional(string)

    # 追加の属性マッピング。google.subject と attribute.repository は常に含まれる。
    extra_attribute_mapping = optional(map(string), {})

    disabled = optional(bool, false)
  })

  validation {
    condition = length(concat(
      var.github_oidc_config.repository != null ? [var.github_oidc_config.repository] : [],
      var.github_oidc_config.repositories,
    )) > 0
    error_message = "github_oidc_config には repository または repositories のいずれかを指定してください。"
  }

  validation {
    condition = alltrue([
      for repository in concat(
        var.github_oidc_config.repository != null ? [var.github_oidc_config.repository] : [],
        var.github_oidc_config.repositories,
      ) :
      can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$", repository))
    ])
    error_message = "リポジトリは 'owner/repo' 形式で指定してください。"
  }

  validation {
    condition     = can(regex("^[a-z0-9-]{4,32}$", var.github_oidc_config.pool_id))
    error_message = "github_oidc_config.pool_id は小文字英数字とハイフン、4〜32文字で指定してください。"
  }

  validation {
    condition     = can(regex("^[a-z0-9-]{4,32}$", var.github_oidc_config.provider_id))
    error_message = "github_oidc_config.provider_id は小文字英数字とハイフン、4〜32文字で指定してください。"
  }

  validation {
    condition = !contains(
      keys(var.github_oidc_config.extra_attribute_mapping),
      "google.subject"
    )
    error_message = "google.subject は常に assertion.sub にマッピングされます。extra_attribute_mapping で上書きできません。"
  }
}

variable "service_account_config" {
  description = "作成して GitHub Actions に関連付けるサービスアカウントの設定。"
  type = object({
    account_id   = string
    display_name = string
    roles        = optional(list(string), [])
    description  = optional(string, "Used by GitHub Actions via Workload Identity Federation")
  })

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{4,28}[a-z0-9])$", var.service_account_config.account_id))
    error_message = "service_account_config.account_id は小文字英字始まり、小文字英数字とハイフンのみ、6〜30文字で指定してください。"
  }

  validation {
    condition = alltrue([
      for role in var.service_account_config.roles :
      can(regex("^(roles/|projects/[^/]+/roles/|organizations/[0-9]+/roles/)", role))
    ])
    error_message = "service_account_config.roles は 'roles/...' またはカスタムロールの完全修飾名で指定してください。"
  }
}
