# ------------------------------------------------------------------------------
# --- State Migration
# --- allow_unauthenticated 専用のリソースを、任意のメンバーを扱える invoker に統合した。
# --- 既存の state を自動で引き継ぐため、利用者の操作は不要。
# --- 次のメジャーバージョンで削除する。
# ------------------------------------------------------------------------------
moved {
  from = google_cloud_run_v2_service_iam_member.allow_unauthenticated[0]
  to   = google_cloud_run_v2_service_iam_member.invoker["allUsers"]
}
