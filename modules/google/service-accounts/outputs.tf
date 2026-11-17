output "service_accounts" {
  description = "作成されたサービスアカウントのリソース（account_id => リソース）。"
  value       = google_service_account.main
}

output "service_account_emails" {
  description = "account_id => メールアドレスのマップ。"
  value       = { for account_id, sa in google_service_account.main : account_id => sa.email }
}

output "service_account_names" {
  description = "account_id => 完全修飾名 (projects/../serviceAccounts/..) のマップ。"
  value       = { for account_id, sa in google_service_account.main : account_id => sa.name }
}

output "service_account_ids" {
  description = "account_id => 一意な数値 ID (unique_id) のマップ。"
  value       = { for account_id, sa in google_service_account.main : account_id => sa.unique_id }
}

output "service_account_members" {
  description = "account_id => IAM バインディング用の 'serviceAccount:<email>' 文字列のマップ。"
  value       = { for account_id, sa in google_service_account.main : account_id => sa.member }
}

output "key_secret_ids" {
  description = "サービスアカウントキーを保存した Secret Manager シークレットの ID（account_id => secret_id）。"
  value       = { for account_id, secret in google_secret_manager_secret.main : account_id => secret.secret_id }
}

output "key_secret_names" {
  description = "サービスアカウントキーを保存したシークレットの完全修飾名（account_id => name）。"
  value       = { for account_id, secret in google_secret_manager_secret.main : account_id => secret.name }
}
