mock_provider "google" {
  # policy_data はプロバイダー側で JSON として検証されるため、モック値を明示する。
  mock_data "google_iam_policy" {
    defaults = {
      policy_data = "{\"bindings\":[]}"
    }
  }
}

variables {
  environment = {
    project_id = "test-project-id"
    region     = "asia-northeast1"
  }
  project_number = "123456789012"
}

run "minimal" {
  command = plan

  module {
    source = "./"
  }

  variables {
    bitbucket_config = {
      workspace          = "my-workspace"
      connection_name    = "bitbucket-connection"
      admin_token_secret = "bitbucket-admin-token"
      read_token_secret  = "bitbucket-read-token"
      webhook_secret     = "bitbucket-webhook-secret"
    }
  }

  assert {
    condition     = google_cloudbuildv2_connection.main.name == "bitbucket-connection"
    error_message = "接続名が期待値と一致しません。"
  }

  assert {
    condition     = google_cloudbuildv2_connection.main.location == "asia-northeast1"
    error_message = "接続のリージョンが期待値と一致しません。"
  }

  assert {
    condition     = google_cloudbuildv2_connection.main.bitbucket_cloud_config[0].authorizer_credential[0].user_token_secret_version == "projects/123456789012/secrets/bitbucket-admin-token/versions/latest"
    error_message = "admin token のシークレットバージョンが期待値と一致しません。"
  }

  assert {
    condition     = google_cloudbuildv2_connection.main.bitbucket_cloud_config[0].webhook_secret_secret_version == "projects/123456789012/secrets/bitbucket-webhook-secret/versions/latest"
    error_message = "webhook のシークレットバージョンが期待値と一致しません。"
  }

  assert {
    condition     = length(google_secret_manager_secret_iam_policy.main) == 3
    error_message = "3 つのシークレットすべてに IAM ポリシーが適用されていません。"
  }

  # project_number を渡した場合は API を叩かない。
  assert {
    condition     = length(data.google_project.main) == 0
    error_message = "project_number 指定時に google_project データソースを参照してはいけません。"
  }

  # repo_slug を省略した場合はリポジトリを作らない。
  assert {
    condition     = length(google_cloudbuildv2_repository.main) == 0
    error_message = "repo_slug 未指定時にリポジトリを作成してはいけません。"
  }

  assert {
    condition     = output.repository == null
    error_message = "repo_slug 未指定時の repository 出力は null でなければなりません。"
  }

  assert {
    condition     = output.cloudbuild_service_agent == "serviceAccount:service-123456789012@gcp-sa-cloudbuild.iam.gserviceaccount.com"
    error_message = "Cloud Build サービスエージェントが期待値と一致しません。"
  }
}

run "with_repository_and_additional_accessors" {
  command = plan

  module {
    source = "./"
  }

  variables {
    bitbucket_config = {
      workspace          = "my-workspace"
      connection_name    = "bitbucket-connection"
      admin_token_secret = "bitbucket-admin-token"
      read_token_secret  = "bitbucket-read-token"
      webhook_secret     = "bitbucket-webhook-secret"
      repo_slug          = "my-repo"
      secret_version     = "3"
    }
    additional_secret_accessors = [
      "serviceAccount:deployer@test-project-id.iam.gserviceaccount.com",
    ]
  }

  assert {
    condition     = google_cloudbuildv2_repository.main[0].remote_uri == "https://bitbucket.org/my-workspace/my-repo.git"
    error_message = "リポジトリの remote_uri が期待値と一致しません。"
  }

  assert {
    condition     = google_cloudbuildv2_repository.main[0].parent_connection == "bitbucket-connection"
    error_message = "リポジトリが接続に紐付いていません。"
  }

  assert {
    condition     = google_cloudbuildv2_connection.main.bitbucket_cloud_config[0].read_authorizer_credential[0].user_token_secret_version == "projects/123456789012/secrets/bitbucket-read-token/versions/3"
    error_message = "secret_version の指定が反映されていません。"
  }

  # authoritative なポリシーなので、追加メンバーは同じ binding に含める必要がある。
  assert {
    condition = length([
      for binding in data.google_iam_policy.secret_accessor.binding : binding
      if contains(binding.members, "serviceAccount:deployer@test-project-id.iam.gserviceaccount.com")
      && contains(binding.members, "serviceAccount:service-123456789012@gcp-sa-cloudbuild.iam.gserviceaccount.com")
    ]) == 1
    error_message = "additional_secret_accessors がサービスエージェントと同じ binding に含まれていません。"
  }
}

run "reject_fully_qualified_secret_name" {
  command = plan

  module {
    source = "./"
  }

  variables {
    bitbucket_config = {
      workspace          = "my-workspace"
      connection_name    = "bitbucket-connection"
      admin_token_secret = "projects/123456789012/secrets/bitbucket-admin-token"
      read_token_secret  = "bitbucket-read-token"
      webhook_secret     = "bitbucket-webhook-secret"
    }
  }

  expect_failures = [var.bitbucket_config]
}

run "reject_duplicated_secrets" {
  command = plan

  module {
    source = "./"
  }

  variables {
    bitbucket_config = {
      workspace          = "my-workspace"
      connection_name    = "bitbucket-connection"
      admin_token_secret = "same-secret"
      read_token_secret  = "same-secret"
      webhook_secret     = "bitbucket-webhook-secret"
    }
  }

  expect_failures = [var.bitbucket_config]
}

run "project_number_resolved_from_data_source" {
  command = plan

  module {
    source = "./"
  }

  variables {
    project_number = null
    bitbucket_config = {
      workspace          = "my-workspace"
      connection_name    = "bitbucket-connection"
      admin_token_secret = "bitbucket-admin-token"
      read_token_secret  = "bitbucket-read-token"
      webhook_secret     = "bitbucket-webhook-secret"
    }
  }

  assert {
    condition     = length(data.google_project.main) == 1
    error_message = "project_number 省略時は google_project データソースから解決しなければなりません。"
  }
}

# ------------------------------------------------------------------------------
# environment（推奨）と project_id / region（非推奨）の両方を受け付ける
# ------------------------------------------------------------------------------
run "deprecated_flat_project_and_region_still_work" {
  command = plan

  module {
    source = "./"
  }

  variables {
    environment = null
    project_id  = "legacy-project-id"
    region      = "us-central1"

    bitbucket_config = {
      workspace          = "my-workspace"
      connection_name    = "bitbucket-connection"
      admin_token_secret = "bitbucket-admin-token"
      read_token_secret  = "bitbucket-read-token"
      webhook_secret     = "bitbucket-webhook-secret"
    }
  }

  assert {
    condition     = google_cloudbuildv2_connection.main.project == "legacy-project-id"
    error_message = "非推奨の project_id 変数からプロジェクトを解決できていません。"
  }

  assert {
    condition     = google_cloudbuildv2_connection.main.location == "us-central1"
    error_message = "非推奨の region 変数からリージョンを解決できていません。"
  }
}

run "reject_environment_and_flat_variables_together" {
  command = plan

  module {
    source = "./"
  }

  variables {
    environment = {
      project_id = "test-project-id"
      region     = "asia-northeast1"
    }
    project_id = "legacy-project-id"

    bitbucket_config = {
      workspace          = "my-workspace"
      connection_name    = "bitbucket-connection"
      admin_token_secret = "bitbucket-admin-token"
      read_token_secret  = "bitbucket-read-token"
      webhook_secret     = "bitbucket-webhook-secret"
    }
  }

  expect_failures = [var.environment]
}

run "reject_missing_project_and_region" {
  command = plan

  module {
    source = "./"
  }

  variables {
    environment = null
    project_id  = null
    region      = null

    bitbucket_config = {
      workspace          = "my-workspace"
      connection_name    = "bitbucket-connection"
      admin_token_secret = "bitbucket-admin-token"
      read_token_secret  = "bitbucket-read-token"
      webhook_secret     = "bitbucket-webhook-secret"
    }
  }

  expect_failures = [var.environment]
}
