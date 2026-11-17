variable "environment" {
  description = "環境設定。ジョブは environment.region に作成されます。"
  type = object({
    project_id   = string
    region       = string
    project_name = optional(string)
    stack_name   = optional(string)
  })
}

variable "job" {
  description = "Cloud Run Job の設定。"
  type = object({
    name                  = string
    image                 = string
    service_account_email = string

    container_name      = optional(string, "main")
    timeout             = optional(string, "600s")
    max_retries         = optional(number, 0)
    task_count          = optional(number, 1)
    parallelism         = optional(number, 0)
    deletion_protection = optional(bool, true)

    # 省略した場合はコンテナイメージの ENTRYPOINT / CMD が使われる。
    command = optional(list(string))
    args    = optional(list(string))

    execution_environment = optional(string, "EXECUTION_ENVIRONMENT_GEN2")
    encryption_key        = optional(string)

    resources = optional(object({
      cpu    = optional(string, "1000m")
      memory = optional(string, "512Mi")
    }), {})

    # map のキーは Terraform 上の識別子。name を省略した場合はキーが環境変数名になる。
    env_vars = optional(map(object({
      name  = optional(string)
      value = string
    })), {})

    secret_env_vars = optional(map(object({
      name      = optional(string)
      secret_id = string
      version   = optional(string, "latest")
    })), {})

    vpc_access = optional(object({
      # Direct VPC egress を使う場合は network / subnetwork、
      # Serverless VPC Access コネクタを使う場合は connector を指定する。
      network      = optional(string)
      subnetwork   = optional(string)
      network_tags = optional(list(string))
      connector    = optional(string)
      egress       = optional(string)
    }))

    labels      = optional(map(string), {})
    annotations = optional(map(string), {})

    # roles/run.invoker を付与するメンバー (例: Cloud Scheduler のサービスアカウント)。
    invoker_members = optional(list(string), [])
  })

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,47}[a-z0-9])?$", var.job.name))
    error_message = "job.name は小文字英字で始まり、小文字英数字とハイフンのみ、49文字以内で指定してください。"
  }

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?s$", var.job.timeout))
    error_message = "job.timeout は秒を表す文字列 (例: \"600s\") で指定してください。"
  }

  validation {
    condition     = var.job.max_retries >= 0
    error_message = "job.max_retries は 0 以上で指定してください。"
  }

  validation {
    condition     = var.job.task_count >= 1
    error_message = "job.task_count は 1 以上で指定してください。"
  }

  validation {
    condition     = contains(["EXECUTION_ENVIRONMENT_GEN1", "EXECUTION_ENVIRONMENT_GEN2"], var.job.execution_environment)
    error_message = "job.execution_environment は EXECUTION_ENVIRONMENT_GEN1 または EXECUTION_ENVIRONMENT_GEN2 を指定してください。"
  }

  validation {
    condition     = can(regex("^[a-z0-9.@_-]+$", var.job.service_account_email))
    error_message = "job.service_account_email はサービスアカウントのメールアドレスを指定してください。"
  }

  # Direct VPC egress とコネクタは併用できない。
  # Terraform 1.10 では条件式が短絡評価されないため、null になりうるオブジェクトの属性には
  # try() 経由でアクセスする。直接参照すると vpc_access を省略しただけで
  # 「Attempt to get attribute from null value」で落ちる。
  validation {
    condition = !(
      try(var.job.vpc_access.connector, null) != null &&
      (
        try(var.job.vpc_access.network, null) != null ||
        try(var.job.vpc_access.subnetwork, null) != null
      )
    )
    error_message = "job.vpc_access では connector と network/subnetwork を同時に指定できません。どちらか一方を選んでください。"
  }

  validation {
    condition = (
      var.job.vpc_access == null ||
      try(var.job.vpc_access.connector, null) != null ||
      (
        try(var.job.vpc_access.network, null) != null &&
        try(var.job.vpc_access.subnetwork, null) != null
      )
    )
    error_message = "job.vpc_access を指定する場合は connector、または network と subnetwork の両方を指定してください。"
  }

  validation {
    condition = alltrue([
      for member in var.job.invoker_members :
      can(regex("^(user|group|serviceAccount|domain|principal|principalSet|allUsers|allAuthenticatedUsers)", member))
    ])
    error_message = "job.invoker_members は 'serviceAccount:...' のように IAM プリンシパルの接頭辞付きで指定してください。"
  }

  # 環境変数名は Cloud Run 側で C_IDENTIFIER (英字かアンダースコア始まり、英数字と
  # アンダースコアのみ) でなければならない。マップのキーがそのまま名前になるため、
  # "MY-VAR" のようなキーは plan では通り apply で失敗する。
  validation {
    condition = alltrue(concat(
      [for key, env in var.job.env_vars : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", coalesce(env.name, key)))],
      [for key, env in var.job.secret_env_vars : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", coalesce(env.name, key)))],
    ))
    error_message = "env_vars / secret_env_vars の環境変数名は英字かアンダースコア始まり、英数字とアンダースコアのみで指定してください（マップのキーがそのまま名前になります。ハイフンは使えません）。"
  }

  # env_vars と secret_env_vars は別々の env ブロックになるため、実効名が衝突すると
  # 「同じ名前の環境変数が 2 つある」として apply が失敗する。
  validation {
    condition = length(distinct(concat(
      [for key, env in var.job.env_vars : coalesce(env.name, key)],
      [for key, env in var.job.secret_env_vars : coalesce(env.name, key)],
    ))) == length(var.job.env_vars) + length(var.job.secret_env_vars)
    error_message = "環境変数名が重複しています。env_vars と secret_env_vars を通して、実際に設定される名前（name を省略した場合はマップのキー）が一意になるようにしてください。"
  }
}
