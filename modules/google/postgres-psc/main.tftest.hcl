mock_provider "google" {}
mock_provider "random" {}

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
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      psc_config = {
        network_config = {
          network_name    = "test-network"
          subnetwork_name = "test-subnetwork"
        }
      }
    }
  }

  # 名前を省略した場合は instance_name から自動生成する。
  assert {
    condition     = google_compute_address.main.name == "test-sql-instance-psc-address"
    error_message = "Compute Address 名の自動生成が期待値と一致しません。"
  }

  assert {
    condition     = google_compute_forwarding_rule.main.name == "test-sql-instance-psc-forwarding-rule"
    error_message = "転送ルール名の自動生成が期待値と一致しません。"
  }

  # PSC エンドポイントの転送ルールは load_balancing_scheme を空文字にしなければならない。
  # subnetwork を指定してはいけない理由は main.tf のコメントを参照
  # （subnetwork は computed 属性のため plan 時には未知で、assert では検査できない）。
  assert {
    condition     = google_compute_forwarding_rule.main.load_balancing_scheme == ""
    error_message = "PSC の転送ルールでは load_balancing_scheme は空文字でなければなりません。"
  }

  # サブネットは予約済み内部 IP 側で決まる。
  assert {
    condition     = google_compute_address.main.subnetwork == "test-subnetwork"
    error_message = "Compute Address の subnetwork が psc_config.network_config.subnetwork_name と一致しません。"
  }

  assert {
    condition     = google_sql_database_instance.main.database_version == "POSTGRES_17"
    error_message = "database.version の既定値が変わっています。"
  }

  assert {
    condition     = google_sql_database_instance.main.settings[0].ip_configuration[0].ipv4_enabled == false
    error_message = "パブリック IP が無効になっていません。"
  }

  # 既定で TLS を強制する。緩めるには明示的な指定が必要。
  assert {
    condition     = google_sql_database_instance.main.settings[0].ip_configuration[0].ssl_mode == "ENCRYPTED_ONLY"
    error_message = "ssl_mode を省略した場合は ENCRYPTED_ONLY でなければなりません。"
  }

  assert {
    condition = alltrue([
      for psc in google_sql_database_instance.main.settings[0].ip_configuration[0].psc_config :
      contains(psc.allowed_consumer_projects, "test-project-id") && psc.psc_enabled
    ])
    error_message = "allowed_consumer_projects に自プロジェクトが含まれていません。"
  }

  # users を省略しても壊れないこと (以前は connection_url でクラッシュしていた)。
  assert {
    condition     = output.connection_url == null
    error_message = "users を省略した場合の connection_url は null でなければなりません。"
  }

  assert {
    condition     = length(google_sql_user.main) == 0
    error_message = "users を省略した場合はユーザーを作ってはいけません。"
  }

  assert {
    condition     = length(google_secret_manager_secret.main) == 0
    error_message = "users を省略した場合はシークレットを作ってはいけません。"
  }

  # dns_config の既定はゾーン作成。ゾーン名は後方互換のため network 名由来。
  assert {
    condition     = google_dns_managed_zone.main[0].name == "test-network-private-zone"
    error_message = "DNS ゾーン名の既定値が変わっています。"
  }
}

run "with_users_and_settings" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      version       = "POSTGRES_16"
      tier          = "db-custom-2-7680"
      users = [
        # secret_id は省略して既定命名を確認する
        { name = "app" },
        { name = "readonly", secret_id = "readonly-credentials" },
      ]
      secret_accessor_members = [
        "serviceAccount:app@test-project-id.iam.gserviceaccount.com",
      ]
      settings = {
        deletion_protection   = true
        availability_type     = "REGIONAL"
        disk_size             = 20
        disk_autoresize       = true
        disk_autoresize_limit = 100
        user_labels           = { env = "test" }
        ssl_mode              = "ENCRYPTED_ONLY"
        backup_configuration = {
          enabled                        = true
          start_time                     = "18:00"
          point_in_time_recovery_enabled = true
          retained_backups               = 14
        }
        maintenance_window = {
          day  = 7
          hour = 19
        }
        insights_config = {
          query_insights_enabled = true
        }
        database_flags = [
          { name = "max_connections", value = "200" },
        ]
      }
      psc_config = {
        network_config = {
          network_name         = "test-network"
          subnetwork_name      = "test-subnetwork"
          forwarding_rule_name = "test-forwarding-rule"
          address_name         = "test-psc-address"
        }
        allowed_consumer_projects = ["test-project-id", "other-project-id"]
      }
      dns_config = {
        zone_name = "test-sql-instance-psc-zone"
        ttl       = 60
      }
    }
  }

  assert {
    condition     = google_sql_user.main["app"].name == "app"
    error_message = "SQL ユーザー名が期待値と一致しません。"
  }

  assert {
    condition     = google_secret_manager_secret.main["app"].secret_id == "test-sql-instance-app-credentials"
    error_message = "secret_id の既定命名が期待値と一致しません。"
  }

  assert {
    condition     = google_secret_manager_secret.main["readonly"].secret_id == "readonly-credentials"
    error_message = "secret_id の明示指定が反映されていません。"
  }

  # ユーザー数 x アクセサー数 の IAM バインディングが作られる。
  assert {
    condition     = length(google_secret_manager_secret_iam_member.accessor) == 2
    error_message = "secretAccessor のバインディング数が期待値と一致しません。"
  }

  assert {
    condition     = google_sql_database_instance.main.settings[0].availability_type == "REGIONAL"
    error_message = "availability_type が反映されていません。"
  }

  assert {
    condition     = google_sql_database_instance.main.settings[0].disk_autoresize_limit == 100
    error_message = "disk_autoresize_limit が反映されていません。"
  }

  assert {
    condition     = google_sql_database_instance.main.settings[0].backup_configuration[0].backup_retention_settings[0].retained_backups == 14
    error_message = "retained_backups が反映されていません。"
  }

  assert {
    condition     = google_sql_database_instance.main.settings[0].insights_config[0].query_insights_enabled == true
    error_message = "insights_config が反映されていません。"
  }

  assert {
    condition     = google_sql_database_instance.main.settings[0].ip_configuration[0].ssl_mode == "ENCRYPTED_ONLY"
    error_message = "ssl_mode が反映されていません。"
  }

  assert {
    condition = alltrue([
      for psc in google_sql_database_instance.main.settings[0].ip_configuration[0].psc_config :
      length(psc.allowed_consumer_projects) == 2
    ])
    error_message = "allowed_consumer_projects の指定が反映されていません。"
  }

  assert {
    condition     = google_dns_managed_zone.main[0].name == "test-sql-instance-psc-zone"
    error_message = "dns_config.zone_name が反映されていません。"
  }

  assert {
    condition     = google_dns_record_set.main[0].ttl == 60
    error_message = "dns_config.ttl が反映されていません。"
  }

  assert {
    condition     = output.user_credentials_secret_ids["readonly"] == "readonly-credentials"
    error_message = "user_credentials_secret_ids が期待値と一致しません。"
  }
}

run "deprecated_address_field_still_works" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      psc_config = {
        network_config = {
          network_name    = "test-network"
          subnetwork_name = "test-subnetwork"
          address         = "legacy-address-name"
        }
      }
    }
  }

  assert {
    condition     = google_compute_address.main.name == "legacy-address-name"
    error_message = "非推奨の address フィールドが引き続き機能していません。"
  }
}

run "dns_zone_can_be_disabled" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      psc_config = {
        network_config = {
          network_name    = "test-network"
          subnetwork_name = "test-subnetwork"
        }
      }
      dns_config = {
        create_zone = false
      }
    }
  }

  assert {
    condition     = length(google_dns_managed_zone.main) == 0
    error_message = "create_zone = false のときゾーンを作ってはいけません。"
  }

  assert {
    condition     = length(google_dns_record_set.main) == 0
    error_message = "create_zone = false のときレコードを作ってはいけません。"
  }

  assert {
    condition     = output.dns_managed_zone_name == null
    error_message = "create_zone = false のとき dns_managed_zone_name は null でなければなりません。"
  }
}

run "ssl_mode_can_be_relaxed" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      psc_config = {
        network_config = {
          network_name    = "test-network"
          subnetwork_name = "test-subnetwork"
        }
      }
      settings = {
        # TLS 非対応のクライアントがある場合の逃げ道。
        ssl_mode = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
      }
    }
  }

  assert {
    condition     = google_sql_database_instance.main.settings[0].ip_configuration[0].ssl_mode == "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
    error_message = "ssl_mode に指定した値が反映されていません。"
  }
}

# optional() の既定値は「省略」だけでなく「明示的な null」にも適用される。
# 利用者が変数を組み立てて null を渡してしまっても、TLS 強制が外れないことを保証する。
run "ssl_mode_null_falls_back_to_default" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      psc_config = {
        network_config = {
          network_name    = "test-network"
          subnetwork_name = "test-subnetwork"
        }
      }
      settings = {
        ssl_mode = null
      }
    }
  }

  assert {
    condition     = google_sql_database_instance.main.settings[0].ip_configuration[0].ssl_mode == "ENCRYPTED_ONLY"
    error_message = "ssl_mode に null を渡した場合も既定の ENCRYPTED_ONLY でなければなりません。"
  }
}

run "reject_invalid_ssl_mode" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      psc_config = {
        network_config = {
          network_name    = "test-network"
          subnetwork_name = "test-subnetwork"
        }
      }
      settings = {
        ssl_mode = "ENCRYPTED"
      }
    }
  }

  expect_failures = [var.database]
}

run "reject_non_postgres_version" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      version       = "MYSQL_8_0"
      psc_config = {
        network_config = {
          network_name    = "test-network"
          subnetwork_name = "test-subnetwork"
        }
      }
    }
  }

  expect_failures = [var.database]
}

run "reject_pitr_without_backup" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      psc_config = {
        network_config = {
          network_name    = "test-network"
          subnetwork_name = "test-subnetwork"
        }
      }
      settings = {
        backup_configuration = {
          enabled                        = false
          point_in_time_recovery_enabled = true
        }
      }
    }
  }

  expect_failures = [var.database]
}

run "reject_duplicated_user_names" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      users         = [{ name = "app" }, { name = "app" }]
      psc_config = {
        network_config = {
          network_name    = "test-network"
          subnetwork_name = "test-subnetwork"
        }
      }
    }
  }

  expect_failures = [var.database]
}

# ------------------------------------------------------------------------------
# apply でしか落ちない名前の制約を plan で落とす
# ------------------------------------------------------------------------------
run "reject_user_name_that_breaks_secret_id" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      # ドットは Secret Manager のシークレット ID に使えないため、
      # 自動生成される "<instance>-app.user-credentials" が不正になる。
      users = [{ name = "app.user" }]
      psc_config = {
        network_config = {
          network_name    = "test-network"
          subnetwork_name = "test-subnetwork"
        }
      }
    }
  }

  expect_failures = [var.database]
}

run "reject_dns_zone_name_too_long" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      psc_config = {
        network_config = {
          # "<network_name>-private-zone" が 63 文字を超える。
          network_name    = "this-is-a-very-long-vpc-network-name-that-exceeds-the-limit"
          subnetwork_name = "test-subnetwork"
        }
      }
    }
  }

  expect_failures = [var.database]
}

run "reject_invalid_forwarding_rule_name" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      psc_config = {
        network_config = {
          network_name    = "test-network"
          subnetwork_name = "test-subnetwork"
          # 大文字は Compute のリソース名に使えない。
          forwarding_rule_name = "Invalid_Name"
        }
      }
    }
  }

  expect_failures = [var.database]
}

# create_zone = false のときは自動生成のゾーン名を使わないので、長い network_name でも通る。
run "long_network_name_is_allowed_without_dns_zone" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      dns_config = {
        create_zone = false
      }
      psc_config = {
        network_config = {
          network_name    = "this-is-a-very-long-vpc-network-name-that-exceeds-the-limit"
          subnetwork_name = "test-subnetwork"
        }
      }
    }
  }

  assert {
    condition     = length(google_dns_managed_zone.main) == 0
    error_message = "create_zone = false でも DNS ゾーンが作られています。"
  }
}

# ユーザー名にドットがあっても、secret_id を明示すれば通る。
run "explicit_secret_id_allows_dotted_user_name" {
  command = plan

  module {
    source = "./"
  }

  variables {
    database = {
      instance_name = "test-sql-instance"
      database_name = "test-database"
      users = [{
        name      = "app.user"
        secret_id = "test-sql-instance-app-user-credentials"
      }]
      psc_config = {
        network_config = {
          network_name    = "test-network"
          subnetwork_name = "test-subnetwork"
        }
      }
    }
  }

  assert {
    condition     = google_secret_manager_secret.main["app.user"].secret_id == "test-sql-instance-app-user-credentials"
    error_message = "明示指定した secret_id が使われていません。"
  }
}
