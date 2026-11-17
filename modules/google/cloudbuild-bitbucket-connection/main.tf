# ------------------------------------------------------------------------------
# --- Project Number
# --- project_number が渡されなかった場合のみ API から解決する。
# ------------------------------------------------------------------------------
data "google_project" "main" {
  count      = var.project_number == null ? 1 : 0
  project_id = local.project_id
}

# ------------------------------------------------------------------------------
# --- Locals
# ------------------------------------------------------------------------------
locals {
  # environment (推奨) とフラットな project_id / region (非推奨) の両方を受け付ける。
  project_id = coalesce(try(var.environment.project_id, null), var.project_id)
  region     = coalesce(try(var.environment.region, null), var.region)

  project_number = var.project_number != null ? var.project_number : data.google_project.main[0].number

  # Cloud Build サービスエージェント。接続作成時にシークレットを読み取る。
  cloudbuild_service_agent = "serviceAccount:service-${local.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"

  secret_version = var.bitbucket_config.secret_version

  # 接続が参照するシークレットバージョンの完全修飾名。
  secret_versions = {
    admin_token = "projects/${local.project_number}/secrets/${var.bitbucket_config.admin_token_secret}/versions/${local.secret_version}"
    read_token  = "projects/${local.project_number}/secrets/${var.bitbucket_config.read_token_secret}/versions/${local.secret_version}"
    webhook     = "projects/${local.project_number}/secrets/${var.bitbucket_config.webhook_secret}/versions/${local.secret_version}"
  }

  # IAM ポリシーを適用する対象シークレット。
  managed_secret_ids = {
    admin_token = var.bitbucket_config.admin_token_secret
    read_token  = var.bitbucket_config.read_token_secret
    webhook     = var.bitbucket_config.webhook_secret
  }
}

# ------------------------------------------------------------------------------
# --- IAM Policy for Cloud Build Service Agent
# --- authoritative なポリシーを使い、接続が読むべきシークレットのアクセス権を厳密に定義する。
# --- ここに列挙されていないメンバーのバインディングは削除される点に注意。
# ------------------------------------------------------------------------------
data "google_iam_policy" "secret_accessor" {
  binding {
    role    = "roles/secretmanager.secretAccessor"
    members = concat([local.cloudbuild_service_agent], var.additional_secret_accessors)
  }
}

resource "google_secret_manager_secret_iam_policy" "main" {
  for_each = local.managed_secret_ids

  project     = local.project_id
  secret_id   = each.value
  policy_data = data.google_iam_policy.secret_accessor.policy_data
}

# ------------------------------------------------------------------------------
# --- Cloud Build Connection to Bitbucket
# ------------------------------------------------------------------------------
resource "google_cloudbuildv2_connection" "main" {
  project  = local.project_id
  location = local.region
  name     = var.bitbucket_config.connection_name

  bitbucket_cloud_config {
    workspace = var.bitbucket_config.workspace

    authorizer_credential {
      user_token_secret_version = local.secret_versions.admin_token
    }

    read_authorizer_credential {
      user_token_secret_version = local.secret_versions.read_token
    }

    webhook_secret_secret_version = local.secret_versions.webhook
  }

  # 接続の作成時点でサービスエージェントがシークレットを読める必要がある。
  depends_on = [google_secret_manager_secret_iam_policy.main]
}

# ------------------------------------------------------------------------------
# --- Cloud Build Repository
# --- repo_slug を指定した場合のみ、Bitbucket リポジトリを接続に紐付ける。
# --- これを作成しておくと、Cloud Build トリガーから repository で参照できる。
# ------------------------------------------------------------------------------
resource "google_cloudbuildv2_repository" "main" {
  count = var.bitbucket_config.repo_slug != null ? 1 : 0

  project           = local.project_id
  location          = local.region
  name              = var.bitbucket_config.repo_slug
  parent_connection = google_cloudbuildv2_connection.main.name
  remote_uri        = "https://bitbucket.org/${var.bitbucket_config.workspace}/${var.bitbucket_config.repo_slug}.git"
}
