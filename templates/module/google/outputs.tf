output "services" {
  description = "有効化した Google Cloud API のリスト。"
  value       = [for service in google_project_service.main : service.service]
}

output "project_id" {
  description = "リソースを作成した Google Cloud プロジェクト ID。"
  value       = var.environment.project_id
}
