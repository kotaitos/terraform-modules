# ------------------------------------------------------------------------------
# --- Locals
# ------------------------------------------------------------------------------
locals {
  # environment (推奨) とフラットな project_id (非推奨) の両方を受け付ける。
  project_id = coalesce(try(var.environment.project_id, null), var.project_id)

  # repository (単一) と repositories (複数) の両方を受け付ける。
  repositories = distinct(concat(
    var.github_oidc_config.repository != null ? [var.github_oidc_config.repository] : [],
    var.github_oidc_config.repositories,
  ))

  # リポジトリが 1 つの場合は等価比較、複数の場合は in 演算子を使う。
  repository_condition = length(local.repositories) == 1 ? "assertion.repository == \"${local.repositories[0]}\"" : "assertion.repository in [${join(", ", [for repository in local.repositories : "\"${repository}\""])}]"

  # 追加条件は AND で結合する。指定が無い場合は括弧を付けず、既存構成との差分を出さない。
  attribute_condition = (
    var.github_oidc_config.extra_attribute_condition == null
    ? local.repository_condition
    : "(${local.repository_condition}) && (${var.github_oidc_config.extra_attribute_condition})"
  )

  attribute_mapping = merge(
    {
      "google.subject"       = "assertion.sub"
      "attribute.repository" = "assertion.repository"
    },
    var.github_oidc_config.extra_attribute_mapping,
  )
}

# ------------------------------------------------------------------------------
# --- Workload Identity Pool
# ------------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "main" {
  provider = google-beta

  project                   = local.project_id
  workload_identity_pool_id = var.github_oidc_config.pool_id
  display_name              = var.github_oidc_config.pool_display_name
  description               = var.github_oidc_config.description
  disabled                  = var.github_oidc_config.disabled
}

# ------------------------------------------------------------------------------
# --- Workload Identity Pool Provider
# --- attribute_condition で許可するリポジトリを制限する。これが無いと、
# --- 任意の GitHub リポジトリからトークンを取得できてしまう。
# ------------------------------------------------------------------------------
resource "google_iam_workload_identity_pool_provider" "main" {
  provider = google-beta

  project                            = local.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.main.workload_identity_pool_id
  workload_identity_pool_provider_id = var.github_oidc_config.provider_id
  display_name                       = var.github_oidc_config.provider_display_name
  description                        = var.github_oidc_config.description
  disabled                           = var.github_oidc_config.disabled

  attribute_condition = local.attribute_condition
  attribute_mapping   = local.attribute_mapping

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ------------------------------------------------------------------------------
# --- Service Account
# ------------------------------------------------------------------------------
resource "google_service_account" "main" {
  project      = local.project_id
  account_id   = var.service_account_config.account_id
  display_name = var.service_account_config.display_name
  description  = var.service_account_config.description
}

# ------------------------------------------------------------------------------
# --- Project IAM Member
# ------------------------------------------------------------------------------
resource "google_project_iam_member" "project_roles" {
  for_each = toset(var.service_account_config.roles)

  project = local.project_id
  role    = each.value
  member  = google_service_account.main.member
}

# ------------------------------------------------------------------------------
# --- Service Account IAM Member
# --- 許可したリポジトリごとに、このサービスアカウントへのなりすましを許可する。
# ------------------------------------------------------------------------------
resource "google_service_account_iam_member" "workload_identity_user" {
  for_each = toset(local.repositories)

  service_account_id = google_service_account.main.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.main.name}/attribute.repository/${each.value}"
}
