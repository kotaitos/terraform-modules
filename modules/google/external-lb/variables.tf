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

variable "lb_name" {
  description = "ロードバランサーと関連リソースの名前に使う接頭辞。"
  type        = string

  # 生成されるリソース名で最も長いのは "<lb_name>-redirect-http-forwarding-rule-ipv6" (接尾辞 35 文字)。
  # Compute リソース名の上限 63 文字に収まるよう 28 文字に制限する。
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,26}[a-z0-9])?$", var.lb_name))
    error_message = "lb_name は小文字英字始まり、小文字英数字とハイフンのみ、28文字以内で指定してください（関連リソース名の接頭辞として使うため短くしています）。"
  }
}

variable "neg_backends" {
  description = "サーバーレス NEG を使うバックエンドのマップ。キーがリソース名の一部になる。"
  type = map(object({
    # cloud-run / cloud-function / app-engine
    type = string
    # cloud-run なら Cloud Run サービス名、cloud-function なら関数名、app-engine ならサービス名。
    service_name = string
    region       = string
    # このバックエンドにルーティングする URL パス (例: ["/api/*"])。
    paths = list(string)

    # app-engine のみ: 対象バージョン。省略時は default バージョン。
    app_engine_version = optional(string)

    timeout_sec = optional(number, 30)
    port_name   = optional(string, "http")
    protocol    = optional(string, "HTTP")
    description = optional(string)

    enable_cdn = optional(bool, false)
    # アクセスログの取得。sample_rate は 0.0〜1.0。
    log_config = optional(object({
      enable      = optional(bool, true)
      sample_rate = optional(number, 1.0)
    }))

    cloud_armor_config = optional(object({
      enabled             = bool
      default_rule_action = optional(string, "deny(403)")
      description         = optional(string)
      # rules のキーは Terraform 上の識別子。priority がルールの評価順を決める。
      rules = map(object({
        description = optional(string)
        action      = string
        priority    = number
        # src_ip_ranges と expression はどちらか一方のみを指定する。
        src_ip_ranges = optional(list(string))
        expression    = optional(string)
        preview       = optional(bool, false)
      }))
    }))
  }))

  validation {
    condition     = length(var.neg_backends) > 0
    error_message = "neg_backends には少なくとも 1 つのバックエンドを指定してください。"
  }

  validation {
    condition = alltrue([
      for key, backend in var.neg_backends :
      contains(["cloud-run", "cloud-function", "app-engine"], backend.type)
    ])
    error_message = "neg_backends.type は cloud-run, cloud-function, app-engine のいずれかを指定してください。"
  }

  validation {
    condition = alltrue([
      for key, backend in var.neg_backends : can(regex("^[a-z]([a-z0-9-]{0,30}[a-z0-9])?$", key))
    ])
    error_message = "neg_backends のキーは小文字英字始まり、小文字英数字とハイフンのみ、32文字以内で指定してください。"
  }

  # "<lb_name>-<key>-security-policy" が Compute リソース名の上限 63 文字を超えないこと。
  validation {
    condition = alltrue([
      for key, backend in var.neg_backends : length("${var.lb_name}-${key}-security-policy") <= 63
    ])
    error_message = "lb_name と neg_backends のキーの合計が長すぎます。\"<lb_name>-<key>-security-policy\" が 63 文字以内になるよう短くしてください。"
  }

  validation {
    condition = alltrue([
      for key, backend in var.neg_backends : length(backend.paths) > 0
    ])
    error_message = "neg_backends.paths には少なくとも 1 つのパスを指定してください (例: [\"/*\"])。"
  }

  # 同じパスを 2 つのバックエンドに割り当てると URL マップの作成が失敗する。
  validation {
    condition = length(flatten([for key, backend in var.neg_backends : backend.paths])) == length(distinct(
      flatten([for key, backend in var.neg_backends : backend.paths])
    ))
    error_message = "neg_backends.paths は全バックエンドを通して重複しないよう指定してください。"
  }

  validation {
    condition = alltrue([
      for key, backend in var.neg_backends :
      backend.log_config == null || (
        coalesce(try(backend.log_config.sample_rate, 1.0), 1.0) >= 0 &&
        coalesce(try(backend.log_config.sample_rate, 1.0), 1.0) <= 1
      )
    ])
    error_message = "neg_backends.log_config.sample_rate は 0.0〜1.0 で指定してください。"
  }

  # Cloud Armor のルールは 1 つのマッチ条件しか持てない。
  validation {
    condition = alltrue(flatten([
      for key, backend in var.neg_backends : [
        for rule_key, rule in coalesce(try(backend.cloud_armor_config.rules, {}), {}) :
        (rule.src_ip_ranges != null) != (rule.expression != null)
      ]
    ]))
    error_message = "cloud_armor_config.rules では src_ip_ranges と expression のどちらか一方のみを指定してください。"
  }

  validation {
    condition = alltrue(flatten([
      for key, backend in var.neg_backends : [
        for rule_key, rule in coalesce(try(backend.cloud_armor_config.rules, {}), {}) :
        rule.priority >= 0 && rule.priority < 2147483647
      ]
    ]))
    error_message = "cloud_armor_config.rules.priority は 0 以上 2147483647 未満で指定してください (2147483647 は既定ルールが使用します)。"
  }

  validation {
    condition = alltrue([
      for key, backend in var.neg_backends :
      length(coalesce(try(backend.cloud_armor_config.rules, {}), {})) == length(distinct([
        for rule_key, rule in coalesce(try(backend.cloud_armor_config.rules, {}), {}) : rule.priority
      ]))
    ])
    error_message = "cloud_armor_config.rules の priority は同一バックエンド内で一意でなければなりません。"
  }
}

variable "default_backend_key" {
  description = "どのパスにもマッチしなかったリクエストを処理する neg_backends のキー。"
  type        = string

  validation {
    condition     = contains(keys(var.neg_backends), var.default_backend_key)
    error_message = "default_backend_key は neg_backends に存在するキーを指定してください。"
  }
}

variable "domain_names" {
  description = <<-EOT
    Google 管理の SSL 証明書と DNS レコードを作成する対象ドメイン。
    1 つ以上指定すると HTTPS ロードバランサーになり、HTTP からのリダイレクトも作成されます。
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.domain_names) == length(distinct(var.domain_names))
    error_message = "domain_names に重複したドメインを指定できません。"
  }

  validation {
    condition = alltrue([
      for domain in var.domain_names : can(regex("^[a-zA-Z0-9*]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$", domain))
    ])
    error_message = "domain_names にはホスト名を指定してください（末尾のドットは不要です）。"
  }
}

variable "domain_name" {
  description = "**非推奨**: `domain_names` を使ってください。単一ドメインを指定する旧インターフェース。"
  type        = string
  default     = null

  validation {
    condition     = var.domain_name == null || length(var.domain_names) == 0
    error_message = "domain_name と domain_names は同時に指定できません。domain_names のみを使ってください。"
  }
}

variable "dns_managed_zone_name" {
  description = "DNS レコードを作成する Cloud DNS マネージドゾーン名。省略すると DNS レコードを作成しません。"
  type        = string
  default     = null
}

variable "ssl_certificate_self_link" {
  description = <<-EOT
    既に作成済みの SSL 証明書の self_link。`domain_names` / `domain_name` を指定した場合は無視されます。
    どちらも指定しない場合は HTTP のみのロードバランサーになります。
  EOT
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "HTTPS プロキシに適用する SSL ポリシーの self_link。TLS の最小バージョンや暗号スイートを制限する場合に指定します。"
  type        = string
  default     = null
}

variable "enable_ipv6" {
  description = "IPv6 のグローバル IP と転送ルールも作成する。"
  type        = bool
  default     = false
}

variable "load_balancing_scheme" {
  description = <<-EOT
    ロードバランサーの種別。
    - `EXTERNAL_MANAGED`: グローバル外部アプリケーション ロードバランサー（推奨）
    - `EXTERNAL`: クラシック アプリケーション ロードバランサー
    既存構成から変更するとバックエンドサービスと転送ルールが再作成されるため、
    稼働中の環境で切り替える際は注意してください。
  EOT
  type        = string
  default     = "EXTERNAL_MANAGED"

  validation {
    condition     = contains(["EXTERNAL_MANAGED", "EXTERNAL"], var.load_balancing_scheme)
    error_message = "load_balancing_scheme は EXTERNAL_MANAGED または EXTERNAL を指定してください。"
  }
}
