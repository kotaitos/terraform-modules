# ------------------------------------------------------------------------------
# --- Locals
# ------------------------------------------------------------------------------
locals {
  network_config = var.database.psc_config.network_config

  # address (非推奨) / address_name のどちらでも受け付け、省略時は instance_name から生成する。
  address_name         = coalesce(local.network_config.address_name, local.network_config.address, "${var.database.instance_name}-psc-address")
  forwarding_rule_name = coalesce(local.network_config.forwarding_rule_name, "${var.database.instance_name}-psc-forwarding-rule")

  allowed_consumer_projects = coalesce(
    var.database.psc_config.allowed_consumer_projects,
    [var.environment.project_id],
  )

  users_map = { for user in var.database.users : user.name => user }

  secret_ids = {
    for name, user in local.users_map :
    name => coalesce(user.secret_id, "${var.database.instance_name}-${name}-credentials")
  }

  # 単一サービスアカウント指定 (非推奨) とリスト指定の両方を受け付ける。
  secret_accessor_members = toset(concat(
    var.database.service_account_email_address != null ? ["serviceAccount:${var.database.service_account_email_address}"] : [],
    var.database.secret_accessor_members,
  ))

  # ゾーン名の既定値は後方互換のため network 名由来のまま。同一 VPC に複数インスタンスを
  # 作る場合は dns_config.zone_name で明示的に分ける必要がある。
  dns_zone_name = coalesce(
    var.database.dns_config.zone_name,
    "${local.network_config.network_name}-private-zone",
  )

  network_url = "https://www.googleapis.com/compute/v1/projects/${var.environment.project_id}/global/networks/${local.network_config.network_name}"

  # 接続文字列の組み立てに使う代表ユーザー (users の先頭)。
  primary_user = length(var.database.users) > 0 ? var.database.users[0].name : null
}

# ------------------------------------------------------------------------------
# --- Compute Address
# --- PSC の転送ルールが使う内部 IP を予約する。
# ------------------------------------------------------------------------------
resource "google_compute_address" "main" {
  project      = var.environment.project_id
  region       = var.environment.region
  name         = local.address_name
  description  = "Private Service Connect address for Cloud SQL - ${var.database.instance_name}"
  address_type = "INTERNAL"
  subnetwork   = local.network_config.subnetwork_name
  address      = local.network_config.ip_address
}

# ------------------------------------------------------------------------------
# --- Forwarding Rule
# --- Cloud SQL のサービスアタッチメントへ VPC 内から到達できるようにする。
# ---
# --- PSC エンドポイントの転送ルールでは load_balancing_scheme を空文字にし、
# --- subnetwork は指定しない。subnetwork を指定すると Compute API が内部ロード
# --- バランサーの転送ルールと解釈して loadBalancingScheme を INTERNAL と見なし、
# --- apply が次のエラーで失敗する。
# ---   Error 400: Invalid value for field 'resource.loadBalancingScheme':
# ---   'INTERNAL'. Invalid field set in Private Service Connect Forwarding Rule.
# --- エンドポイントが所属するサブネットは、予約済み内部 IP
# --- (google_compute_address.main) 側の subnetwork で決まるため指定は不要。
# ------------------------------------------------------------------------------
resource "google_compute_forwarding_rule" "main" {
  project               = var.environment.project_id
  region                = var.environment.region
  name                  = local.forwarding_rule_name
  network               = local.network_config.network_name
  ip_address            = google_compute_address.main.self_link
  load_balancing_scheme = ""
  target                = google_sql_database_instance.main.psc_service_attachment_link
}

# ------------------------------------------------------------------------------
# --- SQL Database Instance
# ------------------------------------------------------------------------------
resource "google_sql_database_instance" "main" {
  project          = var.environment.project_id
  region           = var.environment.region
  name             = var.database.instance_name
  database_version = var.database.version

  # Terraform 側の削除ガード。settings.deletion_protection_enabled は Cloud SQL 側のガード。
  deletion_protection = var.database.settings.deletion_protection

  settings {
    tier                        = var.database.tier
    edition                     = var.database.settings.edition
    activation_policy           = var.database.settings.activation_policy
    availability_type           = var.database.settings.availability_type
    deletion_protection_enabled = var.database.settings.deletion_protection
    disk_size                   = var.database.settings.disk_size
    disk_type                   = var.database.settings.disk_type
    disk_autoresize             = var.database.settings.disk_autoresize
    disk_autoresize_limit       = var.database.settings.disk_autoresize_limit
    user_labels                 = var.database.settings.user_labels
    time_zone                   = var.database.settings.time_zone

    # PSC 専用構成。パブリック IP は常に無効。
    ip_configuration {
      ipv4_enabled = false
      ssl_mode     = var.database.settings.ssl_mode

      psc_config {
        psc_enabled               = true
        allowed_consumer_projects = local.allowed_consumer_projects
      }
    }

    dynamic "backup_configuration" {
      for_each = var.database.settings.backup_configuration != null ? [var.database.settings.backup_configuration] : []
      content {
        enabled                        = backup_configuration.value.enabled
        start_time                     = backup_configuration.value.start_time
        location                       = backup_configuration.value.location
        point_in_time_recovery_enabled = backup_configuration.value.point_in_time_recovery_enabled
        transaction_log_retention_days = backup_configuration.value.transaction_log_retention_days

        dynamic "backup_retention_settings" {
          for_each = backup_configuration.value.retained_backups != null ? [backup_configuration.value.retained_backups] : []
          content {
            retained_backups = backup_retention_settings.value
          }
        }
      }
    }

    dynamic "maintenance_window" {
      for_each = var.database.settings.maintenance_window != null ? [var.database.settings.maintenance_window] : []
      content {
        day          = maintenance_window.value.day
        hour         = maintenance_window.value.hour
        update_track = maintenance_window.value.update_track
      }
    }

    dynamic "insights_config" {
      for_each = var.database.settings.insights_config != null ? [var.database.settings.insights_config] : []
      content {
        query_insights_enabled  = insights_config.value.query_insights_enabled
        query_plans_per_minute  = insights_config.value.query_plans_per_minute
        query_string_length     = insights_config.value.query_string_length
        record_application_tags = insights_config.value.record_application_tags
        record_client_address   = insights_config.value.record_client_address
      }
    }

    dynamic "database_flags" {
      for_each = var.database.settings.database_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }
  }

  lifecycle {
    # disk_autoresize による自動拡張後の値を Terraform が縮小しようとしないようにする。
    ignore_changes = [settings[0].disk_size]
  }
}

# ------------------------------------------------------------------------------
# --- SQL Database
# ------------------------------------------------------------------------------
resource "google_sql_database" "main" {
  project  = var.environment.project_id
  instance = google_sql_database_instance.main.name
  name     = var.database.database_name
}

# ------------------------------------------------------------------------------
# --- Random Password
# ------------------------------------------------------------------------------
resource "random_password" "main" {
  for_each = local.users_map

  length           = var.database.password_length
  special          = true
  override_special = "!$^*()_+[]{}|;,."
  # URL予約文字を除外: @:/<>&?#%=-
  # これにより DATABASE_URL での接続文字列でエスケープ不要
}

# ------------------------------------------------------------------------------
# --- SQL User
# ------------------------------------------------------------------------------
resource "google_sql_user" "main" {
  for_each = local.users_map

  project  = var.environment.project_id
  instance = google_sql_database_instance.main.name
  name     = each.value.name
  password = random_password.main[each.key].result
}

# ------------------------------------------------------------------------------
# --- Secret Manager Secret
# --- ユーザー名とパスワードを JSON で保存する。
# ------------------------------------------------------------------------------
resource "google_secret_manager_secret" "main" {
  for_each = local.users_map

  project   = var.environment.project_id
  secret_id = local.secret_ids[each.key]

  labels = merge(var.database.settings.user_labels, {
    instance = var.database.instance_name
  })

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "main" {
  for_each = local.users_map

  secret  = google_secret_manager_secret.main[each.key].id
  enabled = true
  secret_data = sensitive(jsonencode({
    username = each.value.name
    password = random_password.main[each.key].result
  }))
}

# ------------------------------------------------------------------------------
# --- Secret Manager Secret IAM Member
# --- アプリケーションのサービスアカウントに資格情報の読み取りを許可する。
# ------------------------------------------------------------------------------
resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = {
    for pair in setproduct(keys(local.users_map), tolist(local.secret_accessor_members)) :
    "${pair[0]}:${pair[1]}" => {
      user   = pair[0]
      member = pair[1]
    }
  }

  project   = var.environment.project_id
  secret_id = google_secret_manager_secret.main[each.value.user].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}

# ------------------------------------------------------------------------------
# --- DNS
# --- Cloud SQL が払い出す DNS 名を、PSC の内部 IP に解決させる。
# ------------------------------------------------------------------------------
resource "google_dns_managed_zone" "main" {
  count = var.database.dns_config.create_zone ? 1 : 0

  project     = var.environment.project_id
  name        = local.dns_zone_name
  dns_name    = google_sql_database_instance.main.dns_name
  description = "Private zone for Cloud SQL - ${var.database.instance_name}"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = local.network_url
    }
  }

  labels = merge(var.database.settings.user_labels, {
    instance = var.database.instance_name
  })
}

resource "google_dns_record_set" "main" {
  count = var.database.dns_config.create_zone ? 1 : 0

  project      = var.environment.project_id
  managed_zone = google_dns_managed_zone.main[0].name
  name         = google_sql_database_instance.main.dns_name
  type         = "A"
  ttl          = var.database.dns_config.ttl
  rrdatas      = [google_compute_address.main.address]
}
