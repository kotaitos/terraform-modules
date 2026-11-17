# ------------------------------------------------------------------------------
# --- State Migration
# --- リソースアドレスの整理に伴う移動。既存の state を自動で引き継ぐため、
# --- 利用者が terraform state mv を実行する必要はない。
# --- 次のメジャーバージョンで削除する。
# ------------------------------------------------------------------------------
moved {
  from = google_cloudbuildv2_connection.bitbucket_connection
  to   = google_cloudbuildv2_connection.main
}

moved {
  from = google_secret_manager_secret_iam_policy.admin_token_policy
  to   = google_secret_manager_secret_iam_policy.main["admin_token"]
}

moved {
  from = google_secret_manager_secret_iam_policy.read_token_policy
  to   = google_secret_manager_secret_iam_policy.main["read_token"]
}

moved {
  from = google_secret_manager_secret_iam_policy.webhook_secret_policy
  to   = google_secret_manager_secret_iam_policy.main["webhook"]
}
