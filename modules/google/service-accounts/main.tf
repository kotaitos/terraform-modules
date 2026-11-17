# ------------------------------------------------------------------------------
# --- Locals
# ------------------------------------------------------------------------------
locals {
  service_accounts = { for sa in var.service_accounts : sa.account_id => sa }

  # キーを発行して Secret Manager に保存するサービスアカウント。
  key_managed_accounts = {
    for account_id, sa in local.service_accounts : account_id => sa.secret_manager
    if sa.secret_manager != null
  }

  # for_each のキーには入力値をそのまま使う。接頭辞を補ってからキーにすると、
  # 既存利用者の state アドレスが変わり、IAM バインディングの再作成が発生してしまう。
  wi_user_service_accounts = flatten([
    for account_id, sa in local.service_accounts : [
      for member in sa.wi_user_service_accounts : {
        account_id        = account_id
        member            = member
        normalized_member = startswith(member, "serviceAccount:") ? member : "serviceAccount:${member}"
      }
    ]
  ])

  iam_roles = flatten([
    for account_id, sa in local.service_accounts : [
      for role in sa.iam_roles : {
        account_id = account_id
        role       = role
      }
    ]
  ])

  secret_iam_role_members = flatten([
    for account_id, secret_manager in local.key_managed_accounts : [
      for role, members in secret_manager.iam_role_members : [
        for member in members : {
          account_id = account_id
          secret_id  = secret_manager.secret_id
          role       = role
          member     = member
          normalized_member = anytrue([
            for prefix in ["serviceAccount:", "user:", "group:", "domain:", "principal:", "principalSet:"] :
            startswith(member, prefix)
          ]) ? member : "serviceAccount:${member}"
        }
      ]
    ]
  ])
}

# ------------------------------------------------------------------------------
# --- Service Account
# ------------------------------------------------------------------------------
resource "google_service_account" "main" {
  for_each = local.service_accounts

  project      = var.environment.project_id
  account_id   = each.key
  display_name = each.value.display_name
  description  = each.value.description
}

# ------------------------------------------------------------------------------
# --- Service Account IAM Member
# --- 他のサービスアカウント (GKE の Workload Identity など) からのなりすましを許可する。
# ------------------------------------------------------------------------------
resource "google_service_account_iam_member" "workload_identity_user" {
  for_each = {
    for entry in local.wi_user_service_accounts :
    "${entry.account_id}_${entry.member}" => entry
  }

  service_account_id = google_service_account.main[each.value.account_id].name
  role               = "roles/iam.workloadIdentityUser"
  member             = each.value.normalized_member
}

# ------------------------------------------------------------------------------
# --- Project IAM Member
# ------------------------------------------------------------------------------
resource "google_project_iam_member" "main" {
  for_each = {
    for entry in local.iam_roles :
    "${entry.account_id}_${entry.role}" => entry
  }

  project = var.environment.project_id
  role    = each.value.role
  member  = google_service_account.main[each.value.account_id].member
}

# ------------------------------------------------------------------------------
# --- Service Account Key
# --- 外部システムからの利用など、Workload Identity 連携が使えない場合の逃げ道。
# --- 発行した秘密鍵は Terraform の state にも平文で残る点に注意。
# ------------------------------------------------------------------------------
resource "google_service_account_key" "main" {
  for_each = local.key_managed_accounts

  service_account_id = google_service_account.main[each.key].name
}

# ------------------------------------------------------------------------------
# --- Secret Manager Secret
# ------------------------------------------------------------------------------
resource "google_secret_manager_secret" "main" {
  for_each = local.key_managed_accounts

  provider  = google-beta
  project   = var.environment.project_id
  secret_id = each.value.secret_id
  labels    = each.value.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "main" {
  for_each = local.key_managed_accounts

  secret      = google_secret_manager_secret.main[each.key].id
  secret_data = base64decode(google_service_account_key.main[each.key].private_key)
}

# ------------------------------------------------------------------------------
# --- Secret Manager Secret IAM Member
# ------------------------------------------------------------------------------
resource "google_secret_manager_secret_iam_member" "main" {
  for_each = {
    for entry in local.secret_iam_role_members :
    "${entry.secret_id}_${entry.role}_${entry.member}" => entry
  }

  provider  = google-beta
  project   = var.environment.project_id
  secret_id = google_secret_manager_secret.main[each.value.account_id].id
  role      = each.value.role
  member    = each.value.normalized_member
}
