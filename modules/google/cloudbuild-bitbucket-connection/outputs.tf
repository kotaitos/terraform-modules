output "connection" {
  description = "作成された Cloud Build 接続のリソース全体。"
  value       = google_cloudbuildv2_connection.main
}

output "connection_id" {
  description = "Cloud Build 接続の Terraform リソース ID。"
  value       = google_cloudbuildv2_connection.main.id
}

output "connection_name" {
  description = "Cloud Build 接続の名前。"
  value       = google_cloudbuildv2_connection.main.name
}

output "installation_state" {
  description = "接続のインストール状態。Bitbucket 側で追加操作が必要な場合はここに指示が入る。"
  value       = google_cloudbuildv2_connection.main.installation_state
}

output "repository" {
  description = "作成された Cloud Build リポジトリ。repo_slug を指定しなかった場合は null。"
  value       = one(google_cloudbuildv2_repository.main)
}

output "repository_id" {
  description = "Cloud Build リポジトリの Terraform リソース ID。トリガーの repository に指定する。repo_slug 未指定時は null。"
  value       = try(google_cloudbuildv2_repository.main[0].id, null)
}

output "cloudbuild_service_agent" {
  description = "シークレットへのアクセスを許可した Cloud Build サービスエージェント。"
  value       = local.cloudbuild_service_agent
}

output "project_number" {
  description = "解決されたプロジェクト番号。"
  value       = local.project_number
}
