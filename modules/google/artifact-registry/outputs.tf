output "repository" {
  description = "作成された Artifact Registry リポジトリのリソース全体。"
  value       = google_artifact_registry_repository.main
}

output "repository_id" {
  description = "リポジトリ ID (例: my-docker-repo)。"
  value       = google_artifact_registry_repository.main.repository_id
}

output "id" {
  description = "リポジトリの Terraform リソース ID。"
  value       = google_artifact_registry_repository.main.id
}

output "name" {
  description = "リポジトリの完全修飾名 (projects/../locations/../repositories/..)。"
  value       = google_artifact_registry_repository.main.name
}

output "location" {
  description = "リポジトリのロケーション。"
  value       = google_artifact_registry_repository.main.location
}

output "docker_repository_url" {
  description = "DOCKER フォーマットの場合の `docker push` 用ホスト付きパス。それ以外のフォーマットでは null。"
  value = upper(google_artifact_registry_repository.main.format) == "DOCKER" ? format(
    "%s-docker.pkg.dev/%s/%s",
    google_artifact_registry_repository.main.location,
    google_artifact_registry_repository.main.project,
    google_artifact_registry_repository.main.repository_id,
  ) : null
}
