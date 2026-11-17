output "this_google_sql_database_instance" {
  description = "作成された Cloud SQL インスタンスのリソース全体。"
  value       = google_sql_database_instance.main
  sensitive   = true
}

output "instance_name" {
  description = "Cloud SQL インスタンスの名前。"
  value       = google_sql_database_instance.main.name
}

output "instance_connection_name" {
  description = "`<project>:<region>:<instance>` 形式の接続名。Cloud SQL Auth Proxy や Cloud Run の cloud_sql_instances に指定する。"
  value       = google_sql_database_instance.main.connection_name
}

output "instance_self_link" {
  description = "Cloud SQL インスタンスの self_link。"
  value       = google_sql_database_instance.main.self_link
}

output "dns_name" {
  description = "Cloud SQL が払い出した DNS 名。PSC 経由の接続先ホストとして使える。"
  value       = google_sql_database_instance.main.dns_name
}

output "psc_service_attachment_link" {
  description = "PSC のサービスアタッチメントのリンク。"
  value       = google_sql_database_instance.main.psc_service_attachment_link
}

output "private_ip_address" {
  description = "PSC 用に予約した内部 IP アドレス。DNS 名の代わりにこの IP でも接続できる。"
  value       = google_compute_address.main.address
}

output "database_name" {
  description = "作成したデータベースの名前。"
  value       = google_sql_database.main.name
}

output "user_credentials_secrets" {
  description = "ユーザーの資格情報 (username / password の JSON) を格納した Secret Manager シークレット。"
  value       = { for name, secret in google_secret_manager_secret.main : name => secret }
  sensitive   = true
}

output "user_credentials_secret_ids" {
  description = "ユーザー名 => シークレット ID のマップ。アプリ側から参照する名前を組み立てるのに使う。"
  value       = { for name, secret in google_secret_manager_secret.main : name => secret.secret_id }
}

output "dns_managed_zone_name" {
  description = "作成したプライベート DNS ゾーンの名前。create_zone = false の場合は null。"
  value       = one(google_dns_managed_zone.main[*].name)
}

output "connection_url" {
  description = <<-EOT
    users の先頭ユーザーで接続する PostgreSQL の接続 URL (Prisma などで利用)。
    users を指定していない場合は null。
  EOT
  value = local.primary_user == null ? null : format(
    "postgresql://%s:%s@%s:5432/%s?schema=public",
    local.primary_user,
    random_password.main[local.primary_user].result,
    google_compute_address.main.address,
    google_sql_database.main.name,
  )
  sensitive = true
}
