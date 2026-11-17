mock_provider "google" {}

variables {
  environment = {
    project_id = "test-project-id"
    region     = "asia-northeast1"
  }
}

run "minimal" {
  command = plan

  module {
    source = "./"
  }

  variables {
    job = {
      name                  = "test-job"
      image                 = "asia-northeast1-docker.pkg.dev/test-project-id/repo/app:v1"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"
    }
  }

  assert {
    condition     = google_cloud_run_v2_job.job.name == "test-job"
    error_message = "ジョブ名が期待値と一致しません。"
  }

  assert {
    condition     = google_cloud_run_v2_job.job.location == "asia-northeast1"
    error_message = "ジョブのリージョンが期待値と一致しません。"
  }

  # command / args を省略した場合はイメージの ENTRYPOINT / CMD に委ねる。
  assert {
    condition     = google_cloud_run_v2_job.job.template[0].template[0].containers[0].command == null
    error_message = "command を省略した場合は空でなければなりません。"
  }

  assert {
    condition     = google_cloud_run_v2_job.job.template[0].template[0].containers[0].resources[0].limits["cpu"] == "1000m"
    error_message = "resources のデフォルト値が適用されていません。"
  }

  assert {
    condition     = length(google_cloud_run_v2_job.job.template[0].template[0].vpc_access) == 0
    error_message = "vpc_access を省略した場合はブロックが生成されてはいけません。"
  }

  assert {
    condition     = length(google_cloud_run_v2_job_iam_member.invoker) == 0
    error_message = "invoker_members を省略した場合は IAM メンバーが作られてはいけません。"
  }
}

run "full" {
  command = plan

  module {
    source = "./"
  }

  variables {
    job = {
      name                  = "test-job"
      image                 = "asia-northeast1-docker.pkg.dev/test-project-id/repo/app:v1"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"
      timeout               = "1800s"
      max_retries           = 3
      task_count            = 4
      parallelism           = 2
      command               = ["python"]
      args                  = ["-m", "batch"]
      resources = {
        cpu    = "2000m"
        memory = "2Gi"
      }
      env_vars = {
        # キーが環境変数名になる
        LOG_LEVEL = { value = "info" }
        # name を明示した場合はそちらが優先される
        stage = { name = "STAGE", value = "prod" }
      }
      secret_env_vars = {
        DB_PASSWORD = { secret_id = "db-password" }
      }
      vpc_access = {
        network    = "projects/test-project-id/global/networks/main"
        subnetwork = "projects/test-project-id/regions/asia-northeast1/subnetworks/main"
        egress     = "PRIVATE_RANGES_ONLY"
      }
      labels          = { app = "batch" }
      invoker_members = ["serviceAccount:scheduler@test-project-id.iam.gserviceaccount.com"]
    }
  }

  assert {
    condition     = google_cloud_run_v2_job.job.template[0].task_count == 4
    error_message = "task_count が反映されていません。"
  }

  assert {
    condition     = google_cloud_run_v2_job.job.template[0].template[0].max_retries == 3
    error_message = "max_retries が反映されていません。"
  }

  assert {
    condition = length([
      for env in google_cloud_run_v2_job.job.template[0].template[0].containers[0].env :
      env if env.name == "LOG_LEVEL" && env.value == "info"
    ]) == 1
    error_message = "env_vars のキーが環境変数名として使われていません。"
  }

  assert {
    condition = length([
      for env in google_cloud_run_v2_job.job.template[0].template[0].containers[0].env :
      env if env.name == "STAGE"
    ]) == 1
    error_message = "env_vars の name 指定が優先されていません。"
  }

  assert {
    condition = length([
      for env in google_cloud_run_v2_job.job.template[0].template[0].containers[0].env :
      env if env.name == "DB_PASSWORD" && try(env.value_source[0].secret_key_ref[0].version, null) == "latest"
    ]) == 1
    error_message = "secret_env_vars が正しく組み立てられていません。"
  }

  assert {
    condition     = google_cloud_run_v2_job.job.template[0].template[0].vpc_access[0].network_interfaces[0].subnetwork == "projects/test-project-id/regions/asia-northeast1/subnetworks/main"
    error_message = "Direct VPC egress の subnetwork が反映されていません。"
  }

  assert {
    condition     = length(google_cloud_run_v2_job_iam_member.invoker) == 1
    error_message = "invoker_members の数が期待値と一致しません。"
  }

  assert {
    condition     = output.execute_command == "gcloud run jobs execute test-job --region asia-northeast1 --project test-project-id"
    error_message = "execute_command が期待値と一致しません。"
  }
}

run "vpc_access_with_connector" {
  command = plan

  module {
    source = "./"
  }

  variables {
    job = {
      name                  = "test-job"
      image                 = "gcr.io/example/app:v1"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"
      vpc_access = {
        connector = "projects/test-project-id/locations/asia-northeast1/connectors/main"
        egress    = "ALL_TRAFFIC"
      }
    }
  }

  assert {
    condition     = length(google_cloud_run_v2_job.job.template[0].template[0].vpc_access[0].network_interfaces) == 0
    error_message = "connector 指定時に network_interfaces が生成されてはいけません。"
  }
}

run "reject_connector_and_direct_vpc_together" {
  command = plan

  module {
    source = "./"
  }

  variables {
    job = {
      name                  = "test-job"
      image                 = "gcr.io/example/app:v1"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"
      vpc_access = {
        connector  = "projects/test-project-id/locations/asia-northeast1/connectors/main"
        network    = "projects/test-project-id/global/networks/main"
        subnetwork = "projects/test-project-id/regions/asia-northeast1/subnetworks/main"
      }
    }
  }

  expect_failures = [var.job]
}

run "reject_invalid_job_name" {
  command = plan

  module {
    source = "./"
  }

  variables {
    job = {
      name                  = "Test_Job"
      image                 = "gcr.io/example/app:v1"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"
    }
  }

  expect_failures = [var.job]
}

# ------------------------------------------------------------------------------
# apply でしか落ちない名前の制約を plan で落とす
# ------------------------------------------------------------------------------
run "reject_env_var_name_with_hyphen" {
  command = plan

  module {
    source = "./"
  }

  variables {
    job = {
      name                  = "test-job"
      image                 = "gcr.io/test/image:latest"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"

      # ハイフンは Cloud Run の環境変数名に使えない。
      env_vars = {
        "MY-VAR" = { value = "x" }
      }
    }
  }

  expect_failures = [var.job]
}

run "reject_duplicated_env_var_name_across_maps" {
  command = plan

  module {
    source = "./"
  }

  variables {
    job = {
      name                  = "test-job"
      image                 = "gcr.io/test/image:latest"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"

      env_vars = {
        plain = { name = "DB_PASSWORD", value = "x" }
      }
      secret_env_vars = {
        from_secret = { name = "DB_PASSWORD", secret_id = "db-password" }
      }
    }
  }

  expect_failures = [var.job]
}
