mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  environment = {
    project_id = "test-project-id"
  }
  service_account_config = {
    account_id   = "github-actions-sa"
    display_name = "Test Service Account"
    roles = [
      "roles/storage.objectViewer",
      "roles/storage.objectCreator",
    ]
  }
}

run "single_repository" {
  command = plan

  module {
    source = "./"
  }

  variables {
    github_oidc_config = {
      repository = "test-owner/test-repo"
    }
  }

  assert {
    condition     = google_iam_workload_identity_pool.main.workload_identity_pool_id == "github-actions"
    error_message = "Pool ID の既定値が変わっています。"
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.main.workload_identity_pool_provider_id == "github-actions-provider"
    error_message = "Provider ID の既定値が変わっています。"
  }

  # 単一リポジトリの場合は等価比較になること (既存構成と差分が出ないようにするため)。
  assert {
    condition     = google_iam_workload_identity_pool_provider.main.attribute_condition == "assertion.repository == \"test-owner/test-repo\""
    error_message = "attribute_condition が期待値と一致しません。"
  }

  assert {
    condition     = google_service_account.main.account_id == "github-actions-sa"
    error_message = "サービスアカウント ID が期待値と一致しません。"
  }

  assert {
    condition     = length(google_project_iam_member.project_roles) == 2
    error_message = "付与されたロール数が期待値と一致しません。"
  }

  assert {
    condition     = length(google_service_account_iam_member.workload_identity_user) == 1
    error_message = "workloadIdentityUser のバインディング数が期待値と一致しません。"
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.main.attribute_mapping["attribute.repository"] == "assertion.repository"
    error_message = "既定の attribute_mapping が失われています。"
  }
}

run "multiple_repositories_and_custom_ids" {
  command = plan

  module {
    source = "./"
  }

  variables {
    github_oidc_config = {
      repositories = ["test-owner/app", "test-owner/infra"]
      pool_id      = "github-actions-ci"
      provider_id  = "github-actions-ci-provider"
    }
  }

  assert {
    condition     = google_iam_workload_identity_pool.main.workload_identity_pool_id == "github-actions-ci"
    error_message = "pool_id の指定が反映されていません。"
  }

  # 複数リポジトリの場合は in 演算子を使う。
  assert {
    condition     = google_iam_workload_identity_pool_provider.main.attribute_condition == "assertion.repository in [\"test-owner/app\", \"test-owner/infra\"]"
    error_message = "複数リポジトリの attribute_condition が期待値と一致しません。"
  }

  assert {
    condition     = length(google_service_account_iam_member.workload_identity_user) == 2
    error_message = "リポジトリごとに workloadIdentityUser を付与しなければなりません。"
  }

  assert {
    condition     = length(output.repositories) == 2
    error_message = "repositories 出力が期待値と一致しません。"
  }
}

run "extra_attribute_condition_and_mapping" {
  command = plan

  module {
    source = "./"
  }

  variables {
    github_oidc_config = {
      repository                = "test-owner/test-repo"
      extra_attribute_condition = "assertion.ref == 'refs/heads/main'"
      extra_attribute_mapping = {
        "attribute.ref" = "assertion.ref"
      }
    }
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.main.attribute_condition == "(assertion.repository == \"test-owner/test-repo\") && (assertion.ref == 'refs/heads/main')"
    error_message = "追加条件が AND で結合されていません。"
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.main.attribute_mapping["attribute.ref"] == "assertion.ref"
    error_message = "追加の attribute_mapping が反映されていません。"
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.main.attribute_mapping["google.subject"] == "assertion.sub"
    error_message = "既定の google.subject マッピングが失われています。"
  }
}

run "no_roles_is_allowed" {
  command = plan

  module {
    source = "./"
  }

  variables {
    github_oidc_config = {
      repository = "test-owner/test-repo"
    }
    service_account_config = {
      account_id   = "github-actions-sa"
      display_name = "Test Service Account"
    }
  }

  assert {
    condition     = length(google_project_iam_member.project_roles) == 0
    error_message = "roles を省略した場合はロールを付与してはいけません。"
  }
}

run "reject_missing_repository" {
  command = plan

  module {
    source = "./"
  }

  variables {
    github_oidc_config = {}
  }

  expect_failures = [var.github_oidc_config]
}

run "reject_invalid_repository_format" {
  command = plan

  module {
    source = "./"
  }

  variables {
    github_oidc_config = {
      repository = "test-repo"
    }
  }

  expect_failures = [var.github_oidc_config]
}

run "reject_invalid_account_id" {
  command = plan

  module {
    source = "./"
  }

  variables {
    github_oidc_config = {
      repository = "test-owner/test-repo"
    }
    service_account_config = {
      account_id   = "sa"
      display_name = "Too short"
    }
  }

  expect_failures = [var.service_account_config]
}

# ------------------------------------------------------------------------------
# environment（推奨）と project_id（非推奨）の両方を受け付ける
# ------------------------------------------------------------------------------
run "deprecated_flat_project_id_still_works" {
  command = plan

  module {
    source = "./"
  }

  variables {
    environment = null
    project_id  = "legacy-project-id"

    github_oidc_config = {
      repository = "test-owner/test-repo"
    }
  }

  assert {
    condition     = google_iam_workload_identity_pool.main.project == "legacy-project-id"
    error_message = "非推奨の project_id 変数からプロジェクトを解決できていません。"
  }
}

run "reject_environment_and_project_id_together" {
  command = plan

  module {
    source = "./"
  }

  variables {
    environment = {
      project_id = "test-project-id"
    }
    project_id = "legacy-project-id"

    github_oidc_config = {
      repository = "test-owner/test-repo"
    }
  }

  expect_failures = [var.environment]
}

run "reject_missing_project_id" {
  command = plan

  module {
    source = "./"
  }

  variables {
    environment = null
    project_id  = null

    github_oidc_config = {
      repository = "test-owner/test-repo"
    }
  }

  expect_failures = [var.environment]
}
