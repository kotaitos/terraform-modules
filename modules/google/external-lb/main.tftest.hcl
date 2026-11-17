mock_provider "google" {}

variables {
  environment = {
    project_id = "test-project-id"
  }
  lb_name             = "test-lb"
  default_backend_key = "main"
}

run "http_only" {
  command = plan

  module {
    source = "./"
  }

  variables {
    neg_backends = {
      main = {
        type         = "cloud-run"
        service_name = "web"
        region       = "asia-northeast1"
        paths        = ["/*"]
      }
    }
  }

  assert {
    condition     = output.is_https_enabled == false
    error_message = "証明書を渡していない場合は HTTP のみでなければなりません。"
  }

  assert {
    condition     = length(google_compute_target_http_proxy.main) == 1
    error_message = "HTTP プロキシが作成されていません。"
  }

  assert {
    condition     = length(google_compute_target_https_proxy.main) == 0
    error_message = "HTTPS プロキシが作成されてはいけません。"
  }

  assert {
    condition     = length(google_compute_url_map.redirect) == 0
    error_message = "HTTP のみの場合はリダイレクト用 URL マップを作ってはいけません。"
  }

  assert {
    condition     = length(google_compute_global_address.ipv6) == 0
    error_message = "enable_ipv6 が false の場合は IPv6 アドレスを作ってはいけません。"
  }

  assert {
    condition     = google_compute_backend_service.neg["main"].load_balancing_scheme == "EXTERNAL_MANAGED"
    error_message = "load_balancing_scheme の既定値が EXTERNAL_MANAGED になっていません。"
  }

  assert {
    condition     = google_compute_backend_service.neg["main"].name == "test-lb-main-backend-service"
    error_message = "バックエンドサービス名が期待値と一致しません。"
  }

  assert {
    condition     = google_compute_region_network_endpoint_group.neg["main"].cloud_run[0].service == "web"
    error_message = "Cloud Run サービスが NEG に紐付いていません。"
  }

  assert {
    condition     = length(google_compute_security_policy.backend) == 0
    error_message = "Cloud Armor を有効にしていない場合はポリシーを作ってはいけません。"
  }
}

# enable_ipv6 かつ HTTP のみでも IPv6 の転送ルールが作られること (以前は作られていなかった)。
run "http_only_with_ipv6" {
  command = plan

  module {
    source = "./"
  }

  variables {
    enable_ipv6 = true
    neg_backends = {
      main = {
        type         = "cloud-run"
        service_name = "web"
        region       = "asia-northeast1"
        paths        = ["/*"]
      }
    }
  }

  assert {
    condition     = length(google_compute_global_address.ipv6) == 1
    error_message = "IPv6 アドレスが作成されていません。"
  }

  assert {
    condition     = length(google_compute_global_forwarding_rule.http_ipv6) == 1
    error_message = "HTTP のみの構成でも IPv6 の転送ルールが必要です。"
  }

  assert {
    condition     = contains(output.forwarding_rule_names, "test-lb-http-forwarding-rule-ipv6")
    error_message = "IPv6 の転送ルールが出力に含まれていません。"
  }
}

run "https_with_managed_certificate_and_dns" {
  command = plan

  module {
    source = "./"
  }

  variables {
    domain_names          = ["app.example.com", "www.example.com"]
    dns_managed_zone_name = "example-zone"
    enable_ipv6           = true
    neg_backends = {
      main = {
        type         = "cloud-run"
        service_name = "web"
        region       = "asia-northeast1"
        paths        = ["/*"]
      }
      api = {
        type         = "cloud-run"
        service_name = "api"
        region       = "asia-northeast1"
        paths        = ["/api/*"]
        timeout_sec  = 60
        log_config   = { enable = true, sample_rate = 0.5 }
      }
    }
  }

  assert {
    condition     = output.is_https_enabled == true
    error_message = "domain_names を指定した場合は HTTPS でなければなりません。"
  }

  # 複数ドメインを 1 枚の証明書にまとめる。
  assert {
    condition     = length(google_compute_managed_ssl_certificate.main[0].managed[0].domains) == 2
    error_message = "証明書に 2 つのドメインが含まれていません。"
  }

  # ドメインを変えたときに差し替えられるよう、名前にハッシュを含める。
  assert {
    condition     = startswith(google_compute_managed_ssl_certificate.main[0].name, "test-lb-ssl-cert-")
    error_message = "証明書名の接頭辞が期待値と一致しません。"
  }

  assert {
    condition     = length(google_dns_record_set.a) == 2
    error_message = "ドメインごとに A レコードが必要です。"
  }

  assert {
    condition     = length(google_dns_record_set.aaaa) == 2
    error_message = "IPv6 有効時はドメインごとに AAAA レコードが必要です。"
  }

  assert {
    condition     = google_dns_record_set.a["app.example.com"].name == "app.example.com."
    error_message = "A レコードの名前が FQDN になっていません。"
  }

  assert {
    condition     = length(google_compute_url_map.redirect) == 1
    error_message = "HTTPS 有効時は HTTP からのリダイレクトが必要です。"
  }

  assert {
    condition     = length(google_compute_global_forwarding_rule.http) == 0
    error_message = "HTTPS 有効時に素の HTTP 転送ルールを作ってはいけません。"
  }

  assert {
    condition     = length(google_compute_global_forwarding_rule.redirect_ipv6) == 1
    error_message = "IPv6 のリダイレクト転送ルールが必要です。"
  }

  assert {
    condition     = google_compute_backend_service.neg["api"].log_config[0].sample_rate == 0.5
    error_message = "log_config が反映されていません。"
  }

  assert {
    condition     = length(google_compute_url_map.main.path_matcher[0].path_rule) == 2
    error_message = "バックエンドごとの path_rule が作成されていません。"
  }
}

run "external_certificate" {
  command = plan

  module {
    source = "./"
  }

  variables {
    ssl_certificate_self_link = "https://www.googleapis.com/compute/v1/projects/test-project-id/global/sslCertificates/existing"
    ssl_policy                = "https://www.googleapis.com/compute/v1/projects/test-project-id/global/sslPolicies/modern"
    neg_backends = {
      main = {
        type         = "cloud-run"
        service_name = "web"
        region       = "asia-northeast1"
        paths        = ["/*"]
      }
    }
  }

  assert {
    condition     = length(google_compute_managed_ssl_certificate.main) == 0
    error_message = "外部証明書を指定した場合は Google 管理証明書を作ってはいけません。"
  }

  assert {
    condition     = google_compute_target_https_proxy.main[0].ssl_policy == "https://www.googleapis.com/compute/v1/projects/test-project-id/global/sslPolicies/modern"
    error_message = "ssl_policy が HTTPS プロキシに適用されていません。"
  }

  assert {
    condition     = length(google_dns_record_set.a) == 0
    error_message = "domain_names を指定していない場合は DNS レコードを作ってはいけません。"
  }
}

run "cloud_armor" {
  command = plan

  module {
    source = "./"
  }

  variables {
    neg_backends = {
      main = {
        type         = "cloud-run"
        service_name = "web"
        region       = "asia-northeast1"
        paths        = ["/*"]
        cloud_armor_config = {
          enabled             = true
          default_rule_action = "deny(403)"
          rules = {
            allow_office = {
              action        = "allow"
              priority      = 1000
              src_ip_ranges = ["203.0.113.0/24"]
              description   = "Allow office IP"
            }
            block_bad_ua = {
              action     = "deny(403)"
              priority   = 2000
              expression = "request.headers['user-agent'].contains('BadBot')"
            }
          }
        }
      }
      api = {
        type         = "cloud-run"
        service_name = "api"
        region       = "asia-northeast1"
        paths        = ["/api/*"]
      }
    }
  }

  # Cloud Armor を有効にしたバックエンドのみポリシーが作られる。
  assert {
    condition     = length(google_compute_security_policy.backend) == 1
    error_message = "Cloud Armor ポリシーの数が期待値と一致しません。"
  }

  assert {
    condition     = google_compute_security_policy.backend["main"].name == "test-lb-main-security-policy"
    error_message = "セキュリティポリシー名が期待値と一致しません（キーを切り詰めずに使うこと）。"
  }

  assert {
    condition     = google_compute_security_policy.backend["main"].type == "CLOUD_ARMOR"
    error_message = "セキュリティポリシーの種別が CLOUD_ARMOR になっていません。"
  }

  # security_policy の値そのものは apply 時に確定するため、
  # ポリシーが作られたバックエンドの集合で検証する。
  assert {
    condition     = length(google_compute_security_policy.backend) == 1 && contains(keys(google_compute_security_policy.backend), "main")
    error_message = "Cloud Armor ポリシーが紐付くバックエンドが期待値と一致しません。"
  }

  assert {
    condition     = contains(keys(output.security_policy_ids), "main")
    error_message = "security_policy_ids に main が含まれていません。"
  }

  assert {
    condition     = !contains(keys(output.security_policy_ids), "api")
    error_message = "Cloud Armor 未設定のバックエンドがポリシー出力に含まれています。"
  }
}

run "cloud_function_and_app_engine_backends" {
  command = plan

  module {
    source = "./"
  }

  variables {
    default_backend_key = "func"
    neg_backends = {
      func = {
        type         = "cloud-function"
        service_name = "my-function"
        region       = "asia-northeast1"
        paths        = ["/*"]
      }
      legacy = {
        type               = "app-engine"
        service_name       = "default"
        region             = "asia-northeast1"
        paths              = ["/legacy/*"]
        app_engine_version = "v1"
      }
    }
  }

  assert {
    condition     = google_compute_region_network_endpoint_group.neg["func"].cloud_function[0].function == "my-function"
    error_message = "Cloud Functions バックエンドが NEG に紐付いていません。"
  }

  assert {
    condition     = google_compute_region_network_endpoint_group.neg["legacy"].app_engine[0].version == "v1"
    error_message = "App Engine バックエンドのバージョンが反映されていません。"
  }

  assert {
    condition     = length(google_compute_region_network_endpoint_group.neg["func"].cloud_run) == 0
    error_message = "cloud-function 指定時に cloud_run ブロックが生成されてはいけません。"
  }
}

run "reject_unknown_default_backend_key" {
  command = plan

  module {
    source = "./"
  }

  variables {
    default_backend_key = "does-not-exist"
    neg_backends = {
      main = {
        type         = "cloud-run"
        service_name = "web"
        region       = "asia-northeast1"
        paths        = ["/*"]
      }
    }
  }

  expect_failures = [var.default_backend_key]
}

run "reject_duplicated_paths" {
  command = plan

  module {
    source = "./"
  }

  variables {
    neg_backends = {
      main = {
        type         = "cloud-run"
        service_name = "web"
        region       = "asia-northeast1"
        paths        = ["/*"]
      }
      api = {
        type         = "cloud-run"
        service_name = "api"
        region       = "asia-northeast1"
        paths        = ["/*"]
      }
    }
  }

  expect_failures = [var.neg_backends]
}

run "reject_armor_rule_with_both_match_types" {
  command = plan

  module {
    source = "./"
  }

  variables {
    neg_backends = {
      main = {
        type         = "cloud-run"
        service_name = "web"
        region       = "asia-northeast1"
        paths        = ["/*"]
        cloud_armor_config = {
          enabled = true
          rules = {
            invalid = {
              action        = "deny(403)"
              priority      = 1000
              src_ip_ranges = ["203.0.113.0/24"]
              expression    = "true"
            }
          }
        }
      }
    }
  }

  expect_failures = [var.neg_backends]
}

run "reject_both_domain_name_and_domain_names" {
  command = plan

  module {
    source = "./"
  }

  variables {
    domain_name  = "app.example.com"
    domain_names = ["www.example.com"]
    neg_backends = {
      main = {
        type         = "cloud-run"
        service_name = "web"
        region       = "asia-northeast1"
        paths        = ["/*"]
      }
    }
  }

  expect_failures = [var.domain_name]
}

# 非推奨の domain_name も引き続き動くこと。
run "deprecated_domain_name_still_works" {
  command = plan

  module {
    source = "./"
  }

  variables {
    domain_name           = "app.example.com"
    dns_managed_zone_name = "example-zone"
    neg_backends = {
      main = {
        type         = "cloud-run"
        service_name = "web"
        region       = "asia-northeast1"
        paths        = ["/*"]
      }
    }
  }

  assert {
    condition     = length(output.domains) == 1 && contains(output.domains, "app.example.com")
    error_message = "domain_name から domains が組み立てられていません。"
  }

  assert {
    condition     = length(google_dns_record_set.a) == 1
    error_message = "domain_name 指定時も A レコードを作成しなければなりません。"
  }
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

    neg_backends = {
      main = {
        type         = "cloud-run"
        service_name = "web"
        region       = "asia-northeast1"
        paths        = ["/*"]
      }
    }
  }

  assert {
    condition     = google_compute_global_address.main.project == "legacy-project-id"
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

    neg_backends = {
      main = {
        type         = "cloud-run"
        service_name = "web"
        region       = "asia-northeast1"
        paths        = ["/*"]
      }
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

    neg_backends = {
      main = {
        type         = "cloud-run"
        service_name = "web"
        region       = "asia-northeast1"
        paths        = ["/*"]
      }
    }
  }

  expect_failures = [var.environment]
}
