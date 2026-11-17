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
    service = {
      service_name          = "test-cloud-run-service"
      image                 = "gcr.io/cloudrun/hello"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"
    }
  }

  assert {
    condition     = google_cloud_run_v2_service.main.name == "test-cloud-run-service"
    error_message = "サービス名が期待値と一致しません。"
  }

  assert {
    condition     = google_cloud_run_v2_service.main.location == "asia-northeast1"
    error_message = "サービスのリージョンが期待値と一致しません。"
  }

  assert {
    condition     = google_cloud_run_v2_service.main.template[0].containers[0].image == "gcr.io/cloudrun/hello"
    error_message = "コンテナイメージが期待値と一致しません。"
  }

  assert {
    condition     = google_cloud_run_v2_service.main.template[0].service_account == "test-sa@test-project-id.iam.gserviceaccount.com"
    error_message = "サービスアカウントが期待値と一致しません。"
  }

  assert {
    condition     = google_cloud_run_v2_service.main.template[0].timeout == "300s"
    error_message = "timeout のデフォルト値が適用されていません。"
  }

  # 既定では非公開。IAM メンバーは 1 つも作られない。
  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invoker) == 0
    error_message = "既定でサービスが公開されてはいけません。"
  }

  assert {
    condition     = output.is_public == false
    error_message = "is_public が false でなければなりません。"
  }

  assert {
    condition     = length(google_secret_manager_secret.env_vars) == 0
    error_message = "secret_env_vars を省略した場合はシークレットが作られてはいけません。"
  }

  assert {
    condition     = length(google_cloud_run_v2_service.main.template[0].volumes) == 0
    error_message = "cloud_sql_instances を省略した場合はボリュームが作られてはいけません。"
  }
}

run "existing_secret_is_referenced_not_created" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service = {
      service_name          = "test-cloud-run-service"
      image                 = "gcr.io/cloudrun/hello"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"
      secret_env_vars = {
        # secret_data を省略 → 既存シークレットを参照するだけ
        DB_PASSWORD = { secret_id = "db-password" }
      }
    }
  }

  assert {
    condition     = length(google_secret_manager_secret.env_vars) == 0
    error_message = "secret_data を省略した場合はシークレットを作成してはいけません。"
  }

  assert {
    condition     = length(google_secret_manager_secret_iam_member.existing_accessor) == 1
    error_message = "既存シークレットへの secretAccessor 付与が行われていません。"
  }

  assert {
    condition     = length(google_secret_manager_secret_iam_member.accessor) == 0
    error_message = "作成シークレット向けの IAM 付与が誤って行われています。"
  }

  assert {
    condition = length([
      for env in google_cloud_run_v2_service.main.template[0].containers[0].env :
      env if env.name == "DB_PASSWORD" && try(env.value_source[0].secret_key_ref[0].secret, null) == "db-password"
    ]) == 1
    error_message = "secret_env_vars が環境変数として参照されていません。"
  }
}

run "managed_secret_is_created" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service = {
      service_name          = "test-cloud-run-service"
      image                 = "gcr.io/cloudrun/hello"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"
      secret_env_vars = {
        API_KEY = { secret_id = "api-key", secret_data = "s3cr3t" }
      }
    }
  }

  assert {
    condition     = length(google_secret_manager_secret.env_vars) == 1
    error_message = "secret_data を指定した場合はシークレットを作成しなければなりません。"
  }

  assert {
    condition     = google_secret_manager_secret.env_vars["API_KEY"].secret_id == "api-key"
    error_message = "作成されたシークレットの secret_id が期待値と一致しません。"
  }

  assert {
    condition     = length(google_secret_manager_secret_iam_member.existing_accessor) == 0
    error_message = "作成シークレットが既存扱いになっています。"
  }

  assert {
    condition     = output.managed_secret_ids["API_KEY"] == "api-key"
    error_message = "managed_secret_ids が期待値と一致しません。"
  }
}

run "full" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service = {
      service_name          = "test-cloud-run-service"
      image                 = "gcr.io/cloudrun/hello"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"
      cpu                   = "2000m"
      memory                = "1Gi"
      cpu_idle              = false
      min_instances         = 1
      max_instances         = 10
      timeout_seconds       = 60
      session_affinity      = true
      ingress               = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
      allow_unauthenticated = true
      invoker_members       = ["serviceAccount:caller@test-project-id.iam.gserviceaccount.com"]
      use_http2             = true
      env_vars = {
        LOG_LEVEL = { value = "debug" }
      }
      cloud_sql_instances = ["test-project-id:asia-northeast1:main"]
      startup_probe = {
        path                  = "/healthz"
        initial_delay_seconds = 5
        failure_threshold     = 10
      }
      liveness_probe = {
        period_seconds = 30
      }
      vpc_access = {
        egress = "PRIVATE_RANGES_ONLY"
        network_interfaces = [{
          network    = "projects/test-project-id/global/networks/main"
          subnetwork = "projects/test-project-id/regions/asia-northeast1/subnetworks/main"
        }]
      }
      labels = { app = "web" }
    }
  }

  assert {
    condition     = google_cloud_run_v2_service.main.template[0].containers[0].resources[0].cpu_idle == false
    error_message = "cpu_idle が反映されていません。"
  }

  assert {
    condition     = google_cloud_run_v2_service.main.template[0].scaling[0].min_instance_count == 1
    error_message = "min_instances が反映されていません。"
  }

  assert {
    condition     = google_cloud_run_v2_service.main.template[0].containers[0].ports[0].name == "h2c"
    error_message = "use_http2 が反映されていません。"
  }

  # startup_probe は path を指定したので HTTP GET になる。
  assert {
    condition     = google_cloud_run_v2_service.main.template[0].containers[0].startup_probe[0].http_get[0].path == "/healthz"
    error_message = "startup_probe が HTTP GET になっていません。"
  }

  assert {
    condition     = length(google_cloud_run_v2_service.main.template[0].containers[0].startup_probe[0].tcp_socket) == 0
    error_message = "path 指定時に tcp_socket が生成されてはいけません。"
  }

  # liveness_probe は path を省略したので TCP ソケットになる。
  assert {
    condition     = length(google_cloud_run_v2_service.main.template[0].containers[0].liveness_probe[0].tcp_socket) == 1
    error_message = "path 省略時は tcp_socket にならなければなりません。"
  }

  assert {
    condition     = contains(google_cloud_run_v2_service.main.template[0].volumes[0].cloud_sql_instance[0].instances, "test-project-id:asia-northeast1:main")
    error_message = "Cloud SQL ボリュームが反映されていません。"
  }

  assert {
    condition     = google_cloud_run_v2_service.main.template[0].containers[0].volume_mounts[0].mount_path == "/cloudsql"
    error_message = "Cloud SQL ボリュームのマウントパスが期待値と一致しません。"
  }

  assert {
    condition     = google_cloud_run_v2_service.main.template[0].vpc_access[0].network_interfaces[0].subnetwork == "projects/test-project-id/regions/asia-northeast1/subnetworks/main"
    error_message = "Direct VPC egress の subnetwork が反映されていません。"
  }

  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invoker) == 2
    error_message = "allow_unauthenticated と invoker_members の両方が付与されていません。"
  }

  assert {
    condition     = output.is_public == true
    error_message = "is_public が true でなければなりません。"
  }
}

run "reject_min_greater_than_max_instances" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service = {
      service_name          = "test-cloud-run-service"
      image                 = "gcr.io/cloudrun/hello"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"
      min_instances         = 5
      max_instances         = 2
    }
  }

  expect_failures = [var.service]
}

run "reject_connector_and_direct_vpc_together" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service = {
      service_name          = "test-cloud-run-service"
      image                 = "gcr.io/cloudrun/hello"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"
      vpc_access = {
        connector          = "projects/test-project-id/locations/asia-northeast1/connectors/main"
        network_interfaces = [{ network = "main", subnetwork = "main" }]
      }
    }
  }

  expect_failures = [var.service]
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
    service = {
      service_name          = "test-service"
      image                 = "gcr.io/test/image:latest"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"

      # ハイフンは Cloud Run の環境変数名に使えない。
      env_vars = {
        "MY-VAR" = { value = "x" }
      }
    }
  }

  expect_failures = [var.service]
}

run "reject_duplicated_env_var_name_across_maps" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service = {
      service_name          = "test-service"
      image                 = "gcr.io/test/image:latest"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"

      # env_vars と secret_env_vars で同じ名前になる（name で上書きしているためキーは違う）。
      env_vars = {
        plain = { name = "DB_PASSWORD", value = "x" }
      }
      secret_env_vars = {
        from_secret = { name = "DB_PASSWORD", secret_id = "db-password" }
      }
    }
  }

  expect_failures = [var.service]
}

run "reject_invalid_secret_id" {
  command = plan

  module {
    source = "./"
  }

  variables {
    service = {
      service_name          = "test-service"
      image                 = "gcr.io/test/image:latest"
      service_account_email = "test-sa@test-project-id.iam.gserviceaccount.com"

      # ドットは Secret Manager のシークレット ID に使えない。
      secret_env_vars = {
        DB_PASSWORD = { secret_id = "db.password" }
      }
    }
  }

  expect_failures = [var.service]
}
