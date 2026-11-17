output "workload_identity_pool_id" {
  description = "Workload Identity Pool の Terraform リソース ID。"
  value       = google_iam_workload_identity_pool.main.id
}

output "workload_identity_pool_name" {
  description = "Workload Identity Pool の完全修飾名 (projects/<番号>/locations/global/workloadIdentityPools/<id>)。"
  value       = google_iam_workload_identity_pool.main.name
}

output "workload_identity_pool_provider_id" {
  description = "Workload Identity Pool Provider の Terraform リソース ID。"
  value       = google_iam_workload_identity_pool_provider.main.id
}

output "workload_identity_provider" {
  description = "GitHub Actions の google-github-actions/auth に渡す workload_identity_provider の値。"
  value       = google_iam_workload_identity_pool_provider.main.name
}

output "service_account_email" {
  description = "作成されたサービスアカウントのメールアドレス。"
  value       = google_service_account.main.email
}

output "service_account_id" {
  description = "作成されたサービスアカウントの完全修飾名。"
  value       = google_service_account.main.name
}

output "service_account_member" {
  description = "IAM バインディングで使う 'serviceAccount:<email>' 形式のメンバー文字列。"
  value       = google_service_account.main.member
}

output "repositories" {
  description = "この Provider からの認証を許可した GitHub リポジトリ。"
  value       = local.repositories
}

output "attribute_condition" {
  description = "Provider に設定された attribute_condition。意図した制限になっているか確認するために出力する。"
  value       = google_iam_workload_identity_pool_provider.main.attribute_condition
}

output "github_actions_auth_step" {
  description = "GitHub Actions のワークフローにそのまま貼り付けられる認証ステップ。"
  value       = <<-EOT
    - uses: google-github-actions/auth@v2
      with:
        project_id: ${local.project_id}
        workload_identity_provider: ${google_iam_workload_identity_pool_provider.main.name}
        service_account: ${google_service_account.main.email}
  EOT
}
