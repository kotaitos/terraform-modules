variable "environment" {
  description = "環境設定。このモジュールは project_id のみを使用しますが、他モジュールとインターフェースを揃えるため同じ形を受け取ります。"
  type = object({
    project_id   = string
    project_name = optional(string)
    region       = optional(string)
    stack_name   = optional(string)
  })
}

variable "service_accounts" {
  description = "作成するサービスアカウントのリスト。"
  type = list(object({
    account_id   = string
    display_name = optional(string)
    description  = optional(string)

    # プロジェクトレベルで付与する IAM ロール。
    iam_roles = optional(list(string), [])

    # このサービスアカウントへのなりすまし (roles/iam.workloadIdentityUser) を許可するメンバー。
    # 'serviceAccount:' 接頭辞は省略可能。
    wi_user_service_accounts = optional(list(string), [])

    # 指定した場合、サービスアカウントキーを発行して Secret Manager に保存する。
    # セキュリティ上のリスクがあるため、他に手段がない場合のみ使用すること (README の Notes を参照)。
    secret_manager = optional(object({
      secret_id        = string
      labels           = optional(map(string), {})
      iam_role_members = optional(map(list(string)), {})
    }))
  }))

  validation {
    condition     = length(var.service_accounts) == length(distinct([for sa in var.service_accounts : sa.account_id]))
    error_message = "service_accounts の account_id は一意でなければなりません。"
  }

  validation {
    condition = alltrue([
      for sa in var.service_accounts : can(regex("^[a-z]([a-z0-9-]{4,28}[a-z0-9])$", sa.account_id))
    ])
    error_message = "account_id は小文字英字始まり、小文字英数字とハイフンのみ、6〜30文字で指定してください。"
  }

  validation {
    condition = alltrue(flatten([
      for sa in var.service_accounts : [
        for role in sa.iam_roles :
        can(regex("^(roles/|projects/[^/]+/roles/|organizations/[0-9]+/roles/)", role))
      ]
    ]))
    error_message = "iam_roles は 'roles/...' またはカスタムロールの完全修飾名で指定してください。"
  }

  validation {
    condition = alltrue(flatten([
      for sa in var.service_accounts : [
        for role, members in coalesce(try(sa.secret_manager.iam_role_members, {}), {}) :
        can(regex("^(roles/|projects/[^/]+/roles/|organizations/[0-9]+/roles/)", role))
      ]
    ]))
    error_message = "secret_manager.iam_role_members のキーは 'roles/...' 形式の IAM ロールで指定してください。"
  }

  # secret_id が重複すると、あとから apply したサービスアカウントのキーで上書きされてしまう。
  validation {
    condition = length([
      for sa in var.service_accounts : sa.secret_manager.secret_id if sa.secret_manager != null
      ]) == length(distinct([
        for sa in var.service_accounts : sa.secret_manager.secret_id if sa.secret_manager != null
    ]))
    error_message = "secret_manager.secret_id は一意でなければなりません。"
  }

  # このモジュールがシークレット本体を作るため、Secret Manager のシークレット ID の
  # 書式を満たしている必要がある。plan では落ちず apply が Error 400 で失敗する。
  validation {
    condition = alltrue([
      for account in var.service_accounts :
      account.secret_manager == null ||
      can(regex("^[a-zA-Z0-9_-]{1,255}$", try(account.secret_manager.secret_id, "")))
    ])
    error_message = "secret_manager.secret_id は Secret Manager の書式 (英大小文字・数字・ハイフン・アンダースコアのみ、255文字以内) で指定してください。"
  }
}
