mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  environment = {
    project_id = "test-project-id"
  }
}

run "minimal" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service_accounts = [
      # account_id 以外はすべて省略できること。
      { account_id = "minimal-sa" },
    ]
  }

  assert {
    condition     = google_service_account.main["minimal-sa"].account_id == "minimal-sa"
    error_message = "サービスアカウント ID が期待値と一致しません。"
  }

  assert {
    condition     = length(google_project_iam_member.main) == 0
    error_message = "iam_roles を省略した場合はロールを付与してはいけません。"
  }

  assert {
    condition     = length(google_service_account_iam_member.workload_identity_user) == 0
    error_message = "wi_user_service_accounts を省略した場合はバインディングを作ってはいけません。"
  }

  # secret_manager を省略した場合はキーを発行しない (最も重要な既定動作)。
  assert {
    condition     = length(google_service_account_key.main) == 0
    error_message = "secret_manager を省略した場合はサービスアカウントキーを発行してはいけません。"
  }

  assert {
    condition     = length(google_secret_manager_secret.main) == 0
    error_message = "secret_manager を省略した場合はシークレットを作ってはいけません。"
  }
}

run "full" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service_accounts = [
      {
        account_id   = "app-runner"
        display_name = "Application Runner"
        description  = "Runs the application on Cloud Run"
        iam_roles    = ["roles/secretmanager.secretAccessor", "roles/cloudsql.client"]
        wi_user_service_accounts = [
          # 接頭辞ありでもなしでも受け付ける
          "serviceAccount:deployer@test-project-id.iam.gserviceaccount.com",
          "ci@test-project-id.iam.gserviceaccount.com",
        ]
      },
      {
        account_id   = "external-system"
        display_name = "External System"
        secret_manager = {
          secret_id = "external-system-key"
          labels    = { managed_by = "terraform" }
          iam_role_members = {
            "roles/secretmanager.secretAccessor" = [
              "group:ops@example.com",
              "reader@test-project-id.iam.gserviceaccount.com",
            ]
          }
        }
      },
    ]
  }

  assert {
    condition     = length(google_service_account.main) == 2
    error_message = "サービスアカウント数が期待値と一致しません。"
  }

  assert {
    condition     = google_project_iam_member.main["app-runner_roles/cloudsql.client"].role == "roles/cloudsql.client"
    error_message = "プロジェクト IAM ロールが期待値と一致しません。"
  }

  assert {
    condition     = length(google_service_account_iam_member.workload_identity_user) == 2
    error_message = "workloadIdentityUser のバインディング数が期待値と一致しません。"
  }

  # 接頭辞なしで渡したメンバーには serviceAccount: が補われる。
  assert {
    condition = length([
      for key, binding in google_service_account_iam_member.workload_identity_user :
      binding if binding.member == "serviceAccount:ci@test-project-id.iam.gserviceaccount.com"
    ]) == 1
    error_message = "接頭辞なしのメンバーに serviceAccount: が補われていません。"
  }

  # キーを発行するのは secret_manager を指定したサービスアカウントのみ。
  assert {
    condition     = length(google_service_account_key.main) == 1
    error_message = "キーを発行するサービスアカウント数が期待値と一致しません。"
  }

  assert {
    condition     = google_secret_manager_secret.main["external-system"].secret_id == "external-system-key"
    error_message = "シークレット ID が期待値と一致しません。"
  }

  assert {
    condition     = google_secret_manager_secret.main["external-system"].labels["managed_by"] == "terraform"
    error_message = "シークレットのラベルが反映されていません。"
  }

  assert {
    condition     = length(google_secret_manager_secret_iam_member.main) == 2
    error_message = "シークレットの IAM バインディング数が期待値と一致しません。"
  }

  # group: はそのまま、接頭辞なしは serviceAccount: 補完。
  assert {
    condition = length([
      for key, binding in google_secret_manager_secret_iam_member.main :
      binding if binding.member == "group:ops@example.com"
    ]) == 1
    error_message = "group: 接頭辞のメンバーがそのまま扱われていません。"
  }

  assert {
    condition = length([
      for key, binding in google_secret_manager_secret_iam_member.main :
      binding if binding.member == "serviceAccount:reader@test-project-id.iam.gserviceaccount.com"
    ]) == 1
    error_message = "接頭辞なしのメンバーに serviceAccount: が補われていません。"
  }

  assert {
    condition     = output.key_secret_ids["external-system"] == "external-system-key"
    error_message = "key_secret_ids が期待値と一致しません。"
  }

  assert {
    condition     = !contains(keys(output.key_secret_ids), "app-runner")
    error_message = "キーを発行していないサービスアカウントが key_secret_ids に含まれています。"
  }
}

run "reject_duplicated_account_id" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service_accounts = [
      { account_id = "duplicated-sa" },
      { account_id = "duplicated-sa" },
    ]
  }

  expect_failures = [var.service_accounts]
}

run "reject_invalid_account_id" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service_accounts = [
      { account_id = "Invalid_SA" },
    ]
  }

  expect_failures = [var.service_accounts]
}

run "reject_duplicated_secret_id" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service_accounts = [
      { account_id = "first-sa", secret_manager = { secret_id = "shared-key" } },
      { account_id = "second-sa", secret_manager = { secret_id = "shared-key" } },
    ]
  }

  expect_failures = [var.service_accounts]
}

run "reject_invalid_role" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service_accounts = [
      { account_id = "some-sa", iam_roles = ["editor"] },
    ]
  }

  expect_failures = [var.service_accounts]
}

# ------------------------------------------------------------------------------
# apply でしか落ちない名前の制約を plan で落とす
# ------------------------------------------------------------------------------
run "reject_invalid_secret_id" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service_accounts = [
      # ドットは Secret Manager のシークレット ID に使えない。
      { account_id = "app-runner", secret_manager = { secret_id = "app.runner.key" } },
    ]
  }

  expect_failures = [var.service_accounts]
}
