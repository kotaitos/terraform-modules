output "service" {
  description = "作成された Cloud Run サービスのリソース全体。"
  value       = google_cloud_run_v2_service.main
}

output "service_url" {
  description = "Cloud Run が払い出したサービスの URL。"
  value       = google_cloud_run_v2_service.main.uri
}

output "service_name" {
  description = "Cloud Run サービスの名前。"
  value       = google_cloud_run_v2_service.main.name
}

output "service_id" {
  description = "Cloud Run サービスの Terraform リソース ID。"
  value       = google_cloud_run_v2_service.main.id
}

output "service_location" {
  description = "Cloud Run サービスを作成したリージョン。"
  value       = google_cloud_run_v2_service.main.location
}

output "latest_ready_revision" {
  description = "トラフィックを受け付けている最新リビジョンの名前。"
  value       = google_cloud_run_v2_service.main.latest_ready_revision
}

output "managed_secret_ids" {
  description = "このモジュールが作成した Secret Manager シークレットの ID (環境変数キー => secret_id)。"
  value       = { for key, secret in google_secret_manager_secret.env_vars : key => secret.secret_id }
}

output "is_public" {
  description = "allUsers に roles/run.invoker が付与されているか。"
  value       = contains(keys(google_cloud_run_v2_service_iam_member.invoker), "allUsers")
}
