# ------------------------------------------------------------------------------
# --- Cloud Run v2 Job
# ------------------------------------------------------------------------------
resource "google_cloud_run_v2_job" "job" {
  project             = var.environment.project_id
  location            = var.environment.region
  name                = var.job.name
  deletion_protection = var.job.deletion_protection
  labels              = var.job.labels
  annotations         = var.job.annotations

  template {
    # 1 実行あたりのタスク数と、その同時実行数。
    task_count  = var.job.task_count
    parallelism = var.job.parallelism

    template {
      service_account       = var.job.service_account_email
      timeout               = var.job.timeout
      max_retries           = var.job.max_retries
      execution_environment = var.job.execution_environment
      encryption_key        = var.job.encryption_key

      containers {
        name    = var.job.container_name
        image   = var.job.image
        command = var.job.command
        args    = var.job.args

        dynamic "env" {
          for_each = var.job.env_vars
          content {
            name  = coalesce(env.value.name, env.key)
            value = env.value.value
          }
        }

        dynamic "env" {
          for_each = var.job.secret_env_vars
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

        resources {
          limits = {
            cpu    = var.job.resources.cpu
            memory = var.job.resources.memory
          }
        }
      }

      dynamic "vpc_access" {
        for_each = var.job.vpc_access != null ? [var.job.vpc_access] : []
        content {
          connector = vpc_access.value.connector
          egress    = vpc_access.value.egress

          dynamic "network_interfaces" {
            for_each = vpc_access.value.network != null ? [vpc_access.value] : []
            content {
              network    = network_interfaces.value.network
              subnetwork = network_interfaces.value.subnetwork
              tags       = network_interfaces.value.network_tags
            }
          }
        }
      }
    }
  }
}

# ------------------------------------------------------------------------------
# --- IAM Member (ジョブの実行権限)
# --- Cloud Scheduler / Workflows などから実行させる場合に使用する。
# ------------------------------------------------------------------------------
resource "google_cloud_run_v2_job_iam_member" "invoker" {
  for_each = toset(var.job.invoker_members)

  project  = google_cloud_run_v2_job.job.project
  location = google_cloud_run_v2_job.job.location
  name     = google_cloud_run_v2_job.job.name
  role     = "roles/run.invoker"
  member   = each.value
}
