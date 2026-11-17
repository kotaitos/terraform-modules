output "load_balancer_ip" {
  description = "ロードバランサーの IPv4 アドレス。DNS の A レコードに設定する値。"
  value       = google_compute_global_address.main.address
}

output "load_balancer_ipv6_address" {
  description = "ロードバランサーの IPv6 アドレス。enable_ipv6 が false の場合は null。"
  value       = one(google_compute_global_address.ipv6[*].address)
}

output "is_https_enabled" {
  description = "HTTPS が有効か（SSL 証明書が設定されているか）。"
  value       = local.is_https_enabled
}

output "domains" {
  description = "Google 管理 SSL 証明書と DNS レコードの対象ドメイン。"
  value       = local.domains
}

output "ssl_certificate_self_link" {
  description = "HTTPS プロキシに設定した SSL 証明書の self_link。HTTP のみの場合は null。"
  value       = local.effective_ssl_certificate_self_link
}

output "managed_ssl_certificate" {
  description = "このモジュールが作成した Google 管理 SSL 証明書。外部証明書を使う場合は null。"
  value       = one(google_compute_managed_ssl_certificate.main)
}

output "url_map_id" {
  description = "リクエストを振り分ける URL マップの ID。"
  value       = google_compute_url_map.main.id
}

output "backend_service_ids" {
  description = "バックエンドサービスの ID（neg_backends のキー => ID）。"
  value       = { for key, backend in google_compute_backend_service.neg : key => backend.id }
}

output "backend_service_names" {
  description = "バックエンドサービスの名前（neg_backends のキー => 名前）。"
  value       = { for key, backend in google_compute_backend_service.neg : key => backend.name }
}

output "network_endpoint_group_ids" {
  description = "サーバーレス NEG の ID（neg_backends のキー => ID）。"
  value       = { for key, neg in google_compute_region_network_endpoint_group.neg : key => neg.id }
}

output "security_policy_ids" {
  description = "Cloud Armor セキュリティポリシーの ID（neg_backends のキー => ID）。有効にしたバックエンドのみ。"
  value       = { for key, policy in google_compute_security_policy.backend : key => policy.id }
}

output "forwarding_rule_names" {
  description = "作成された転送ルールの名前一覧。"
  value = compact(concat(
    google_compute_global_forwarding_rule.http[*].name,
    google_compute_global_forwarding_rule.http_ipv6[*].name,
    google_compute_global_forwarding_rule.https[*].name,
    google_compute_global_forwarding_rule.https_ipv6[*].name,
    google_compute_global_forwarding_rule.redirect[*].name,
    google_compute_global_forwarding_rule.redirect_ipv6[*].name,
  ))
}
