# ------------------------------------------------------------------------------
# --- State Migration
# --- DNS ゾーンとレコードを dns_config.create_zone で切り替えられるようにしたため、
# --- count 付きのアドレスに変わった。既存の state を自動で引き継ぐため、
# --- 利用者が terraform state mv を実行する必要はない。
# --- 次のメジャーバージョンで削除する。
# ------------------------------------------------------------------------------
moved {
  from = google_dns_managed_zone.main
  to   = google_dns_managed_zone.main[0]
}

moved {
  from = google_dns_record_set.main
  to   = google_dns_record_set.main[0]
}
