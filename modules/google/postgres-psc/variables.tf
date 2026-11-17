variable "environment" {
  description = "環境設定。インスタンスは environment.region に作成されます。"
  type = object({
    project_id   = string
    region       = string
    project_name = optional(string)
    stack_name   = optional(string)
  })
}

variable "database" {
  description = "Cloud SQL for PostgreSQL (Private Service Connect) の設定。"
  type = object({
    instance_name = string
    database_name = string

    version = optional(string, "POSTGRES_17")
    tier    = optional(string, "db-f1-micro")

    # 組み込みユーザー。パスワードは自動生成され、Secret Manager に JSON で保存される。
    users = optional(list(object({
      name      = string
      secret_id = optional(string)
    })), [])

    # 生成するパスワードの長さ。変更すると既存ユーザーのパスワードも再生成される点に注意。
    password_length = optional(number, 16)

    # 作成したシークレットに roles/secretmanager.secretAccessor を付与するメンバー。
    secret_accessor_members = optional(list(string), [])
    # 後方互換: 単一のサービスアカウントを指定する旧インターフェース。
    service_account_email_address = optional(string)

    settings = optional(object({
      deletion_protection = optional(bool, false)
      edition             = optional(string, "ENTERPRISE")
      activation_policy   = optional(string, "ALWAYS")
      availability_type   = optional(string, "ZONAL")
      disk_size           = optional(number, 10)
      disk_type           = optional(string, "PD_SSD")
      # 空き容量が不足したときにディスクを自動拡張する。
      disk_autoresize       = optional(bool, true)
      disk_autoresize_limit = optional(number, 0)
      user_labels           = optional(map(string), {})
      # 既定で TLS を強制する。PSC 経由の閉域接続でも、経路上の傍受に対する防御として
      # 暗号化を必須にしておく。TLS 非対応のクライアントがある場合に限り
      # ALLOW_UNENCRYPTED_AND_ENCRYPTED を明示的に指定する。
      ssl_mode  = optional(string, "ENCRYPTED_ONLY")
      time_zone = optional(string)

      backup_configuration = optional(object({
        enabled                        = optional(bool, false)
        start_time                     = optional(string)
        location                       = optional(string)
        point_in_time_recovery_enabled = optional(bool, false)
        transaction_log_retention_days = optional(number, 7)
        retained_backups               = optional(number)
      }))

      maintenance_window = optional(object({
        day          = optional(number)
        hour         = optional(number)
        update_track = optional(string)
      }))

      insights_config = optional(object({
        query_insights_enabled  = optional(bool, true)
        query_plans_per_minute  = optional(number)
        query_string_length     = optional(number)
        record_application_tags = optional(bool)
        record_client_address   = optional(bool)
      }))

      database_flags = optional(list(object({
        name  = string
        value = string
      })), [])
    }), {})

    psc_config = object({
      network_config = object({
        network_name    = string
        subnetwork_name = string

        # 省略時は instance_name から自動生成する。
        forwarding_rule_name = optional(string)
        address_name         = optional(string)
        # 非推奨: address_name を使用。Compute Address の「リソース名」を指定する旧インターフェース。
        address = optional(string)
        # 予約したい内部 IP。省略時はサブネットから自動割り当て。
        ip_address = optional(string)
      })

      # PSC での接続を許可するプロジェクト。省略時は自プロジェクトのみ。
      allowed_consumer_projects = optional(list(string))
    })

    dns_config = optional(object({
      # インスタンスの DNS 名を解決するプライベートゾーンを作成するか。
      # 同一 VPC に複数インスタンスを作る場合は zone_name を明示するか、
      # ゾーン管理を外部に任せて false にする。
      create_zone = optional(bool, true)
      zone_name   = optional(string)
      ttl         = optional(number, 300)
    }), {})
  })

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,36}[a-z0-9])?$", var.database.instance_name))
    error_message = "database.instance_name は小文字英字始まり、小文字英数字とハイフンのみ、38文字以内で指定してください（関連リソース名の接頭辞に使うため）。"
  }

  validation {
    condition     = startswith(var.database.version, "POSTGRES_")
    error_message = "database.version は PostgreSQL のバージョン (例: POSTGRES_17) を指定してください。このモジュールは PostgreSQL 専用です。"
  }

  validation {
    condition     = length(var.database.users) == length(distinct([for user in var.database.users : user.name]))
    error_message = "database.users の name は一意でなければなりません。"
  }

  validation {
    condition = length(distinct([
      for user in var.database.users : coalesce(user.secret_id, "${var.database.instance_name}-${user.name}-credentials")
    ])) == length(var.database.users)
    error_message = "database.users の secret_id は一意でなければなりません。"
  }

  validation {
    condition     = var.database.password_length >= 8 && var.database.password_length <= 100
    error_message = "database.password_length は 8〜100 の範囲で指定してください。"
  }

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.database.settings.edition)
    error_message = "database.settings.edition は ENTERPRISE または ENTERPRISE_PLUS を指定してください。"
  }

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.database.settings.availability_type)
    error_message = "database.settings.availability_type は ZONAL または REGIONAL を指定してください。"
  }

  validation {
    condition     = contains(["ALWAYS", "NEVER"], var.database.settings.activation_policy)
    error_message = "database.settings.activation_policy は ALWAYS または NEVER を指定してください。"
  }

  validation {
    condition     = var.database.settings.disk_size >= 10
    error_message = "database.settings.disk_size は 10 GB 以上で指定してください。"
  }

  validation {
    condition = (
      var.database.settings.disk_autoresize_limit == 0 ||
      var.database.settings.disk_autoresize_limit >= var.database.settings.disk_size
    )
    error_message = "database.settings.disk_autoresize_limit は 0 (無制限) または disk_size 以上で指定してください。"
  }

  validation {
    condition = contains(
      ["ALLOW_UNENCRYPTED_AND_ENCRYPTED", "ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"],
      var.database.settings.ssl_mode
    )
    error_message = "database.settings.ssl_mode は ALLOW_UNENCRYPTED_AND_ENCRYPTED, ENCRYPTED_ONLY, TRUSTED_CLIENT_CERTIFICATE_REQUIRED のいずれかを指定してください（省略時は ENCRYPTED_ONLY）。"
  }

  # PITR は自動バックアップが有効でないと使えない。
  validation {
    condition = (
      var.database.settings.backup_configuration == null ||
      !coalesce(try(var.database.settings.backup_configuration.point_in_time_recovery_enabled, false), false) ||
      coalesce(try(var.database.settings.backup_configuration.enabled, false), false)
    )
    error_message = "point_in_time_recovery_enabled を有効にする場合は backup_configuration.enabled も true にしてください。"
  }

  validation {
    condition = alltrue([
      for member in var.database.secret_accessor_members :
      can(regex("^(user|group|serviceAccount|domain|principal|principalSet):", member))
    ])
    error_message = "database.secret_accessor_members は 'serviceAccount:...' のように IAM プリンシパルの接頭辞付きで指定してください。"
  }

  # 実際に作られるシークレット ID を検査する。Secret Manager のシークレット ID は
  # 英大小文字・数字・ハイフン・アンダースコアのみ (255 文字以内) だが、PostgreSQL の
  # ユーザー名にはドットなども使えるため、自動生成した ID が不正になりうる。
  # plan では落ちず apply が Error 400 (Invalid secret ID) で失敗する。
  validation {
    condition = alltrue([
      for user in var.database.users :
      can(regex(
        "^[a-zA-Z0-9_-]{1,255}$",
        coalesce(user.secret_id, "${var.database.instance_name}-${user.name}-credentials")
      ))
    ])
    error_message = "資格情報シークレットの ID が Secret Manager の書式 (英大小文字・数字・ハイフン・アンダースコアのみ、255文字以内) になりません。database.users の name にドットなどが含まれる場合は、users[*].secret_id で明示的に指定してください。"
  }

  # 実際に作られる DNS ゾーン名を検査する。Cloud DNS のゾーン名は Compute と同じ
  # RFC1035 形式 (小文字英字始まり、小文字英数字とハイフン、63文字以内)。
  # network_name が長いと自動生成した名前が 63 文字を超え、apply で失敗する。
  validation {
    condition = (
      !var.database.dns_config.create_zone ||
      can(regex(
        "^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$",
        coalesce(
          var.database.dns_config.zone_name,
          "${var.database.psc_config.network_config.network_name}-private-zone",
        )
      ))
    )
    error_message = "DNS ゾーン名が Cloud DNS の書式 (小文字英字始まり、小文字英数字とハイフンのみ、63文字以内) になりません。dns_config.zone_name で明示的に指定してください（省略時は \"<network_name>-private-zone\"）。"
  }

  # 明示指定した Compute リソース名の書式。自動生成の場合は instance_name の検査でカバーされる。
  validation {
    condition = alltrue([
      for name in compact([
        var.database.psc_config.network_config.address_name,
        var.database.psc_config.network_config.address,
        var.database.psc_config.network_config.forwarding_rule_name,
      ]) :
      can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", name))
    ])
    error_message = "psc_config.network_config の address_name / forwarding_rule_name は Compute リソース名の書式 (小文字英字始まり、小文字英数字とハイフンのみ、63文字以内) で指定してください。"
  }
}
