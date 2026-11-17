# ------------------------------------------------------------------------------
# --- Locals
# ------------------------------------------------------------------------------
locals {
  # このモジュールがシークレット本体まで作成するキー。
  # secret_data に sensitive な値が渡されても for_each のキー計算に使えるよう、
  # 「値が指定されているか」だけを見てマーキングを外す。
  managed_secret_keys = toset([
    for key, config in var.service.secret_env_vars : key
    if config.create_secret != null ? config.create_secret : try(nonsensitive(config.secret_data), config.secret_data) != null
  ])

  # 既存のシークレットを参照するだけのキー。
  referenced_secret_keys = setsubtract(keys(var.service.secret_env_vars), local.managed_secret_keys)

  # Cloud SQL を Unix ソケット経由で使う場合のボリューム名。
  cloud_sql_volume_name = "cloudsql"
  use_cloud_sql_volume  = length(var.service.cloud_sql_instances) > 0
}

# ------------------------------------------------------------------------------
# --- Secret Manager Secret (このモジュールが作成するシークレット)
# ------------------------------------------------------------------------------
resource "google_secret_manager_secret" "env_vars" {
  for_each = local.managed_secret_keys

  project   = var.environment.project_id
  secret_id = var.service.secret_env_vars[each.key].secret_id
  labels = merge(var.service.labels, {
    service = var.service.service_name
  })

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "env_vars" {
  for_each = local.managed_secret_keys

  secret      = google_secret_manager_secret.env_vars[each.key].name
  secret_data = var.service.secret_env_vars[each.key].secret_data
}

# ------------------------------------------------------------------------------
# --- Secret Manager Secret IAM Member
# --- サービスアカウントがシークレットを読めるようにする。Cloud Run はリビジョン作成時に
# --- シークレットを解決するため、Service より先に付与されている必要がある。
# ------------------------------------------------------------------------------
resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = local.managed_secret_keys

  project   = var.environment.project_id
  secret_id = google_secret_manager_secret.env_vars[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service.service_account_email}"
}

resource "google_secret_manager_secret_iam_member" "existing_accessor" {
  for_each = local.referenced_secret_keys

  project   = var.environment.project_id
  secret_id = var.service.secret_env_vars[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service.service_account_email}"
}

# ------------------------------------------------------------------------------
# --- Cloud Run v2 Service
# ------------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "main" {
  project             = var.environment.project_id
  location            = var.environment.region
  name                = var.service.service_name
  description         = var.service.description
  ingress             = var.service.ingress
  deletion_protection = var.service.deletion_protection
  labels              = var.service.labels
  annotations         = var.service.annotations
  custom_audiences    = var.service.custom_audiences

  template {
    service_account                  = var.service.service_account_email
    timeout                          = "${var.service.timeout_seconds}s"
    max_instance_request_concurrency = var.service.max_instance_request_concurrency
    session_affinity                 = var.service.session_affinity
    execution_environment            = var.service.execution_environment
    encryption_key                   = var.service.encryption_key

    scaling {
      min_instance_count = var.service.min_instances
      max_instance_count = var.service.max_instances
    }

    containers {
      image = var.service.image

      resources {
        limits = {
          cpu    = var.service.cpu
          memory = var.service.memory
        }
        startup_cpu_boost = var.service.startup_cpu_boost
        cpu_idle          = var.service.cpu_idle
      }

      dynamic "env" {
        for_each = var.service.env_vars
        content {
          name  = coalesce(env.value.name, env.key)
          value = env.value.value
        }
      }

      dynamic "env" {
        for_each = var.service.secret_env_vars
        content {
          name = coalesce(env.value.name, env.key)
          value_source {
            secret_key_ref {
              secret  = env.value.secret_id
              version = env.value.version
            }
          }
        }
      }

      dynamic "ports" {
        for_each = var.service.container_ports
        content {
          container_port = ports.value
          name           = var.service.use_http2 ? "h2c" : null
        }
      }

      dynamic "startup_probe" {
        for_each = var.service.startup_probe != null ? [var.service.startup_probe] : []
        content {
          initial_delay_seconds = startup_probe.value.initial_delay_seconds
          timeout_seconds       = startup_probe.value.timeout_seconds
          period_seconds        = startup_probe.value.period_seconds
          failure_threshold     = startup_probe.value.failure_threshold

          dynamic "http_get" {
            for_each = startup_probe.value.path != null ? [startup_probe.value] : []
            content {
              path = http_get.value.path
              port = http_get.value.port
            }
          }

          dynamic "tcp_socket" {
            for_each = startup_probe.value.path == null ? [startup_probe.value] : []
            content {
              port = tcp_socket.value.port
            }
          }
        }
      }

      dynamic "liveness_probe" {
        for_each = var.service.liveness_probe != null ? [var.service.liveness_probe] : []
        content {
          initial_delay_seconds = liveness_probe.value.initial_delay_seconds
          timeout_seconds       = liveness_probe.value.timeout_seconds
          period_seconds        = liveness_probe.value.period_seconds
          failure_threshold     = liveness_probe.value.failure_threshold

          dynamic "http_get" {
            for_each = liveness_probe.value.path != null ? [liveness_probe.value] : []
            content {
              path = http_get.value.path
              port = http_get.value.port
            }
          }

          dynamic "tcp_socket" {
            for_each = liveness_probe.value.path == null ? [liveness_probe.value] : []
            content {
              # liveness_probe の tcp_socket.port はプロバイダー側で必須のため、
              # 省略された場合はコンテナポートを既定値として補う。
              port = coalesce(tcp_socket.value.port, one(var.service.container_ports))
            }
          }
        }
      }

      dynamic "volume_mounts" {
        for_each = local.use_cloud_sql_volume ? [1] : []
        content {
          name       = local.cloud_sql_volume_name
          mount_path = "/cloudsql"
        }
      }
    }

    dynamic "volumes" {
      for_each = local.use_cloud_sql_volume ? [1] : []
      content {
        name = local.cloud_sql_volume_name
        cloud_sql_instance {
          instances = var.service.cloud_sql_instances
        }
      }
    }

    dynamic "vpc_access" {
      for_each = var.service.vpc_access != null ? [var.service.vpc_access] : []
      content {
        connector = vpc_access.value.connector
        egress    = vpc_access.value.egress

        dynamic "network_interfaces" {
          for_each = coalesce(vpc_access.value.network_interfaces, [])
          content {
            network    = network_interfaces.value.network
            subnetwork = network_interfaces.value.subnetwork
            tags       = network_interfaces.value.tags
          }
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  # シークレットの読み取り権限が無いままリビジョンを作成すると起動に失敗するため、
  # IAM 付与とシークレットバージョンの作成を待つ。
  depends_on = [
    google_secret_manager_secret_version.env_vars,
    google_secret_manager_secret_iam_member.accessor,
    google_secret_manager_secret_iam_member.existing_accessor,
  ]

  lifecycle {
    ignore_changes = [
      # gcloud / Console からデプロイした際に書き換わるため無視する。
      client,
      client_version,
      # コンテナ名を指定していないため Cloud Run 側が自動命名する。
      template[0].containers[0].name,
    ]
  }
}

# ------------------------------------------------------------------------------
# --- IAM Member (サービスの呼び出し権限)
# ------------------------------------------------------------------------------
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = toset(concat(
    var.service.allow_unauthenticated ? ["allUsers"] : [],
    var.service.invoker_members,
  ))

  project  = google_cloud_run_v2_service.main.project
  location = google_cloud_run_v2_service.main.location
  name     = google_cloud_run_v2_service.main.name
  role     = "roles/run.invoker"
  member   = each.value
}
