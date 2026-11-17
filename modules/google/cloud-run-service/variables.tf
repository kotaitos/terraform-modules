variable "environment" {
  description = "環境設定。サービスは environment.region に作成されます。"
  type = object({
    project_id   = string
    region       = string
    project_name = optional(string)
    stack_name   = optional(string)
  })
}

variable "service" {
  description = "Cloud Run サービスの設定。"
  type = object({
    service_name          = string
    image                 = string
    service_account_email = string

    description = optional(string)
    labels      = optional(map(string), {})
    annotations = optional(map(string), {})

    # --- コンテナ ---
    cpu               = optional(string, "1000m")
    memory            = optional(string, "512Mi")
    startup_cpu_boost = optional(bool, true)
    # false にするとリクエスト外でも CPU が割り当てられる (常時 CPU)。
    cpu_idle        = optional(bool, true)
    container_ports = optional(list(number), [8080])
    # gRPC や HTTP/2 をコンテナで直接受ける場合は true。
    use_http2 = optional(bool, false)

    # --- 環境変数 ---
    # map のキーは Terraform 上の識別子。name を省略した場合はキーが環境変数名になる。
    env_vars = optional(map(object({
      name  = optional(string)
      value = string
    })), {})

    # secret_data を指定するとシークレット本体もこのモジュールが作成する。
    # 既存シークレットを参照する場合は secret_data を省略する。
    secret_env_vars = optional(map(object({
      name        = optional(string)
      secret_id   = string
      version     = optional(string, "latest")
      secret_data = optional(string)
      # secret_data が sensitive でマークされた値の場合は、このフラグで作成の有無を明示する。
      create_secret = optional(bool)
    })), {})

    # --- リクエスト処理 ---
    timeout_seconds                  = optional(number, 300)
    max_instance_request_concurrency = optional(number, 80)
    min_instances                    = optional(number, 0)
    max_instances                    = optional(number, 100)
    session_affinity                 = optional(bool, false)

    # --- ネットワーク / アクセス制御 ---
    ingress = optional(string, "INGRESS_TRAFFIC_ALL")
    # true にすると allUsers に roles/run.invoker を付与し、認証なしで公開する。
    allow_unauthenticated = optional(bool, false)
    # 個別に roles/run.invoker を付与するメンバー。
    invoker_members  = optional(list(string), [])
    custom_audiences = optional(list(string))

    vpc_access = optional(object({
      # Serverless VPC Access コネクタを使う場合は connector、
      # Direct VPC egress を使う場合は network_interfaces を指定する。
      connector = optional(string)
      egress    = optional(string)
      network_interfaces = optional(list(object({
        network    = optional(string)
        subnetwork = optional(string)
        tags       = optional(list(string))
      })), [])
    }))

    # --- その他 ---
    # Unix ソケット経由で Cloud SQL に接続する場合のインスタンス接続名。/cloudsql にマウントされる。
    cloud_sql_instances   = optional(list(string), [])
    execution_environment = optional(string)
    encryption_key        = optional(string)
    deletion_protection   = optional(bool, true)

    # path を指定すると HTTP GET、省略すると TCP ソケットでの死活監視になる。
    startup_probe = optional(object({
      path                  = optional(string)
      port                  = optional(number)
      initial_delay_seconds = optional(number)
      timeout_seconds       = optional(number)
      period_seconds        = optional(number)
      failure_threshold     = optional(number)
    }))
    liveness_probe = optional(object({
      path                  = optional(string)
      port                  = optional(number)
      initial_delay_seconds = optional(number)
      timeout_seconds       = optional(number)
      period_seconds        = optional(number)
      failure_threshold     = optional(number)
    }))
  })

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.service.service_name))
    error_message = "service.service_name は小文字英字で始まり、小文字英数字とハイフンのみ、63文字以内で指定してください。"
  }

  validation {
    condition = contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER",
    ], var.service.ingress)
    error_message = "service.ingress は INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY, INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER のいずれかを指定してください。"
  }

  validation {
    condition     = var.service.min_instances >= 0 && var.service.min_instances <= var.service.max_instances
    error_message = "service.min_instances は 0 以上かつ max_instances 以下で指定してください。"
  }

  validation {
    condition     = var.service.timeout_seconds >= 1 && var.service.timeout_seconds <= 3600
    error_message = "service.timeout_seconds は 1〜3600 の範囲で指定してください。"
  }

  validation {
    condition     = var.service.max_instance_request_concurrency >= 1
    error_message = "service.max_instance_request_concurrency は 1 以上で指定してください。"
  }

  # Cloud Run v2 はコンテナポートを 1 つしか公開できない。
  validation {
    condition     = length(var.service.container_ports) <= 1
    error_message = "service.container_ports に指定できるポートは 1 つまでです。"
  }

  validation {
    condition = var.service.execution_environment == null || contains(
      ["EXECUTION_ENVIRONMENT_GEN1", "EXECUTION_ENVIRONMENT_GEN2"],
      coalesce(var.service.execution_environment, "EXECUTION_ENVIRONMENT_GEN2")
    )
    error_message = "service.execution_environment は EXECUTION_ENVIRONMENT_GEN1 または EXECUTION_ENVIRONMENT_GEN2 を指定してください。"
  }

  # コネクタと Direct VPC egress は併用できない。
  # Terraform 1.10 では条件式が短絡評価されないため、null になりうるオブジェクトの属性には
  # try() 経由でアクセスする。直接参照すると vpc_access を省略しただけで
  # 「Attempt to get attribute from null value」で落ちる。
  validation {
    condition = !(
      try(var.service.vpc_access.connector, null) != null &&
      try(length(var.service.vpc_access.network_interfaces), 0) > 0
    )
    error_message = "service.vpc_access では connector と network_interfaces を同時に指定できません。どちらか一方を選んでください。"
  }

  validation {
    condition = (
      var.service.vpc_access == null ||
      try(var.service.vpc_access.connector, null) != null ||
      try(length(var.service.vpc_access.network_interfaces), 0) > 0
    )
    error_message = "service.vpc_access を指定する場合は connector または network_interfaces のいずれかを指定してください。"
  }

  validation {
    condition = alltrue([
      for member in var.service.invoker_members :
      can(regex("^(user|group|serviceAccount|domain|principal|principalSet|allUsers|allAuthenticatedUsers)", member))
    ])
    error_message = "service.invoker_members は 'serviceAccount:...' のように IAM プリンシパルの接頭辞付きで指定してください。"
  }

  validation {
    condition     = can(regex("^[a-z0-9.@_-]+$", var.service.service_account_email))
    error_message = "service.service_account_email はサービスアカウントのメールアドレスを指定してください。"
  }

  # liveness_probe を TCP で行う場合、プロバイダー側で port が必須になる。
  validation {
    condition = (
      var.service.liveness_probe == null ||
      try(var.service.liveness_probe.path, null) != null ||
      try(var.service.liveness_probe.port, null) != null ||
      length(var.service.container_ports) == 1
    )
    error_message = "TCP の liveness_probe には port が必要です。liveness_probe.port を指定するか、container_ports を 1 つ指定してください。"
  }

  # 環境変数名は Cloud Run 側で C_IDENTIFIER (英字かアンダースコア始まり、英数字と
  # アンダースコアのみ) でなければならない。マップのキーがそのまま名前になるため、
  # "MY-VAR" のようなキーは plan では通り apply で失敗する。
  validation {
    condition = alltrue(concat(
      [for key, env in var.service.env_vars : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", coalesce(env.name, key)))],
      [for key, env in var.service.secret_env_vars : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", coalesce(env.name, key)))],
    ))
    error_message = "env_vars / secret_env_vars の環境変数名は英字かアンダースコア始まり、英数字とアンダースコアのみで指定してください（マップのキーがそのまま名前になります。ハイフンは使えません）。"
  }

  # env_vars と secret_env_vars は別々の env ブロックになるため、実効名が衝突すると
  # 「同じ名前の環境変数が 2 つある」として apply が失敗する。name で上書きできるので
  # マップのキーが違っても衝突しうる。
  validation {
    condition = length(distinct(concat(
      [for key, env in var.service.env_vars : coalesce(env.name, key)],
      [for key, env in var.service.secret_env_vars : coalesce(env.name, key)],
    ))) == length(var.service.env_vars) + length(var.service.secret_env_vars)
    error_message = "環境変数名が重複しています。env_vars と secret_env_vars を通して、実際に設定される名前（name を省略した場合はマップのキー）が一意になるようにしてください。"
  }

  # secret_data を渡した場合はこのモジュールがシークレット本体も作るため、
  # Secret Manager のシークレット ID の書式を満たしている必要がある。
  validation {
    condition = alltrue([
      for key, env in var.service.secret_env_vars :
      can(regex("^[a-zA-Z0-9_-]{1,255}$", env.secret_id))
    ])
    error_message = "secret_env_vars の secret_id は Secret Manager の書式 (英大小文字・数字・ハイフン・アンダースコアのみ、255文字以内) で指定してください。"
  }
}
