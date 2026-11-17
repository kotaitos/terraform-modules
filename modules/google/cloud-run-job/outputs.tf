output "job" {
  description = "作成された Cloud Run Job のリソース全体。"
  value       = google_cloud_run_v2_job.job
}

output "job_name" {
  description = "Cloud Run Job の名前。"
  value       = google_cloud_run_v2_job.job.name
}

output "job_id" {
  description = "Cloud Run Job の Terraform リソース ID。"
  value       = google_cloud_run_v2_job.job.id
}

output "job_uid" {
  description = "Cloud Run Job の一意な識別子 (UID)。"
  value       = google_cloud_run_v2_job.job.uid
}

output "job_location" {
  description = "Cloud Run Job を作成したリージョン。"
  value       = google_cloud_run_v2_job.job.location
}

output "execute_command" {
  description = "ジョブを手動実行するための gcloud コマンド。"
  value = format(
    "gcloud run jobs execute %s --region %s --project %s",
    google_cloud_run_v2_job.job.name,
    google_cloud_run_v2_job.job.location,
    google_cloud_run_v2_job.job.project,
  )
}
