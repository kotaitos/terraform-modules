# ------------------------------------------------------------------------------
# --- Locals
# ------------------------------------------------------------------------------
locals {
  # environment (推奨) とフラットな project_id (非推奨) の両方を受け付ける。
  project_id = coalesce(try(var.environment.project_id, null), var.project_id)

  # domain_name (非推奨) と domain_names のどちらでも受け付ける。
  domains = length(var.domain_names) > 0 ? var.domain_names : compact([var.domain_name])

  manage_certificate = length(local.domains) > 0
  manage_dns_records = local.manage_certificate && var.dns_managed_zone_name != null

  # is_https_enabled は count / for_each の判定に使うため、リソース属性ではなく
  # 変数だけから決まるようにする。証明書の self_link は apply 時にしか確定しないため、
  # ここで参照すると "count value depends on resource attributes" エラーになる。
  is_https_enabled = local.manage_certificate || var.ssl_certificate_self_link != null

  effective_ssl_certificate_self_link = local.manage_certificate ? google_compute_managed_ssl_certificate.main[0].self_link : var.ssl_certificate_self_link

  # ドメインを変更すると証明書は差し替えになる。名前にドメインのハッシュを含めることで、
  # create_before_destroy と組み合わせて名前衝突なく入れ替えられるようにする。
  certificate_name_suffix = substr(sha256(join(",", local.domains)), 0, 8)

  # Cloud Armor を有効にしたバックエンドのみポリシーを作る。
  armor_backends = {
    for key, backend in var.neg_backends : key => backend
    if backend.cloud_armor_config != null && try(backend.cloud_armor_config.enabled, false)
  }
}

# ------------------------------------------------------------------------------
# --- Global IP Address
# ------------------------------------------------------------------------------
resource "google_compute_global_address" "main" {
  project = local.project_id
  name    = "${var.lb_name}-ip"
}

resource "google_compute_global_address" "ipv6" {
  count        = var.enable_ipv6 ? 1 : 0
  project      = local.project_id
  name         = "${var.lb_name}-ipv6"
  address_type = "EXTERNAL"
  ip_version   = "IPV6"
}

# ------------------------------------------------------------------------------
# --- Managed SSL Certificate
# ------------------------------------------------------------------------------
resource "google_compute_managed_ssl_certificate" "main" {
  count   = local.manage_certificate ? 1 : 0
  project = local.project_id
  name    = "${var.lb_name}-ssl-cert-${local.certificate_name_suffix}"

  managed {
    domains = local.domains
  }

  # 証明書はプロキシから参照されているため、先に新しい証明書を作ってから差し替える。
  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# --- DNS Records
# ------------------------------------------------------------------------------
resource "google_dns_record_set" "a" {
  for_each = local.manage_dns_records ? toset(local.domains) : []

  project      = local.project_id
  managed_zone = var.dns_managed_zone_name
  name         = "${each.value}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.main.address]
}

resource "google_dns_record_set" "aaaa" {
  for_each = local.manage_dns_records && var.enable_ipv6 ? toset(local.domains) : []

  project      = local.project_id
  managed_zone = var.dns_managed_zone_name
  name         = "${each.value}."
  type         = "AAAA"
  ttl          = 300
  rrdatas      = [google_compute_global_address.ipv6[0].address]
}

# ------------------------------------------------------------------------------
# --- Cloud Armor Security Policy
# ------------------------------------------------------------------------------
resource "google_compute_security_policy" "backend" {
  for_each = local.armor_backends

  project     = local.project_id
  name        = "${var.lb_name}-${each.key}-security-policy"
  description = try(each.value.cloud_armor_config.description, null)
  type        = "CLOUD_ARMOR"

  # 既定ルール。priority 2147483647 は Cloud Armor が予約している最低優先度。
  rule {
    action      = each.value.cloud_armor_config.default_rule_action
    priority    = 2147483647
    description = "Default rule"
    preview     = false
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  dynamic "rule" {
    for_each = { for rule_key, rule in each.value.cloud_armor_config.rules : rule_key => rule if rule.src_ip_ranges != null }
    content {
      action      = rule.value.action
      priority    = rule.value.priority
      description = rule.value.description
      preview     = rule.value.preview
      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = rule.value.src_ip_ranges
        }
      }
    }
  }

  dynamic "rule" {
    for_each = { for rule_key, rule in each.value.cloud_armor_config.rules : rule_key => rule if rule.expression != null }
    content {
      action      = rule.value.action
      priority    = rule.value.priority
      description = rule.value.description
      preview     = rule.value.preview
      match {
        expr {
          expression = rule.value.expression
        }
      }
    }
  }
}

# ------------------------------------------------------------------------------
# --- Serverless NEG & Backend Service
# ------------------------------------------------------------------------------
resource "google_compute_region_network_endpoint_group" "neg" {
  for_each = var.neg_backends

  project               = local.project_id
  name                  = "${var.lb_name}-${each.key}-neg"
  region                = each.value.region
  network_endpoint_type = "SERVERLESS"

  dynamic "cloud_run" {
    for_each = each.value.type == "cloud-run" ? [1] : []
    content {
      service = each.value.service_name
    }
  }

  dynamic "cloud_function" {
    for_each = each.value.type == "cloud-function" ? [1] : []
    content {
      function = each.value.service_name
    }
  }

  dynamic "app_engine" {
    for_each = each.value.type == "app-engine" ? [1] : []
    content {
      service = each.value.service_name
      version = each.value.app_engine_version
    }
  }
}

resource "google_compute_backend_service" "neg" {
  for_each = var.neg_backends

  project               = local.project_id
  name                  = "${var.lb_name}-${each.key}-backend-service"
  description           = each.value.description
  protocol              = each.value.protocol
  port_name             = each.value.port_name
  timeout_sec           = each.value.timeout_sec
  enable_cdn            = each.value.enable_cdn
  load_balancing_scheme = var.load_balancing_scheme

  # Cloud Armor を有効にしたバックエンドにのみポリシーを紐付ける。
  security_policy = contains(keys(local.armor_backends), each.key) ? google_compute_security_policy.backend[each.key].id : null

  backend {
    group = google_compute_region_network_endpoint_group.neg[each.key].id
  }

  dynamic "log_config" {
    for_each = each.value.log_config != null ? [each.value.log_config] : []
    content {
      enable      = log_config.value.enable
      sample_rate = log_config.value.sample_rate
    }
  }
}

# ------------------------------------------------------------------------------
# --- URL Map
# ------------------------------------------------------------------------------
resource "google_compute_url_map" "main" {
  project         = local.project_id
  name            = "${var.lb_name}-url-map"
  default_service = google_compute_backend_service.neg[var.default_backend_key].id

  host_rule {
    hosts        = ["*"]
    path_matcher = "all-paths"
  }

  path_matcher {
    name            = "all-paths"
    default_service = google_compute_backend_service.neg[var.default_backend_key].id

    dynamic "path_rule" {
      for_each = var.neg_backends
      content {
        paths   = path_rule.value.paths
        service = google_compute_backend_service.neg[path_rule.key].id
      }
    }
  }
}

# ------------------------------------------------------------------------------
# --- HTTP (HTTPS を使わない場合)
# ------------------------------------------------------------------------------
resource "google_compute_target_http_proxy" "main" {
  count   = local.is_https_enabled ? 0 : 1
  project = local.project_id
  name    = "${var.lb_name}-http-proxy"
  url_map = google_compute_url_map.main.id
}

resource "google_compute_global_forwarding_rule" "http" {
  count                 = local.is_https_enabled ? 0 : 1
  project               = local.project_id
  name                  = "${var.lb_name}-http-forwarding-rule"
  target                = google_compute_target_http_proxy.main[0].id
  ip_address            = google_compute_global_address.main.address
  port_range            = "80"
  load_balancing_scheme = var.load_balancing_scheme
}

resource "google_compute_global_forwarding_rule" "http_ipv6" {
  count                 = !local.is_https_enabled && var.enable_ipv6 ? 1 : 0
  project               = local.project_id
  name                  = "${var.lb_name}-http-forwarding-rule-ipv6"
  target                = google_compute_target_http_proxy.main[0].id
  ip_address            = google_compute_global_address.ipv6[0].address
  port_range            = "80"
  load_balancing_scheme = var.load_balancing_scheme
}

# ------------------------------------------------------------------------------
# --- HTTPS
# ------------------------------------------------------------------------------
resource "google_compute_target_https_proxy" "main" {
  count            = local.is_https_enabled ? 1 : 0
  project          = local.project_id
  name             = "${var.lb_name}-https-proxy"
  url_map          = google_compute_url_map.main.id
  ssl_certificates = [local.effective_ssl_certificate_self_link]
  ssl_policy       = var.ssl_policy
}

resource "google_compute_global_forwarding_rule" "https" {
  count                 = local.is_https_enabled ? 1 : 0
  project               = local.project_id
  name                  = "${var.lb_name}-https-forwarding-rule"
  target                = google_compute_target_https_proxy.main[0].id
  ip_address            = google_compute_global_address.main.address
  port_range            = "443"
  load_balancing_scheme = var.load_balancing_scheme
}

resource "google_compute_global_forwarding_rule" "https_ipv6" {
  count                 = local.is_https_enabled && var.enable_ipv6 ? 1 : 0
  project               = local.project_id
  name                  = "${var.lb_name}-https-forwarding-rule-ipv6"
  target                = google_compute_target_https_proxy.main[0].id
  ip_address            = google_compute_global_address.ipv6[0].address
  port_range            = "443"
  load_balancing_scheme = var.load_balancing_scheme
}

# ------------------------------------------------------------------------------
# --- HTTP to HTTPS Redirect
# ------------------------------------------------------------------------------
resource "google_compute_url_map" "redirect" {
  count   = local.is_https_enabled ? 1 : 0
  project = local.project_id
  name    = "${var.lb_name}-redirect-url-map"

  default_url_redirect {
    https_redirect         = true
    strip_query            = false
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  count   = local.is_https_enabled ? 1 : 0
  project = local.project_id
  name    = "${var.lb_name}-redirect-http-proxy"
  url_map = google_compute_url_map.redirect[0].id
}

resource "google_compute_global_forwarding_rule" "redirect" {
  count                 = local.is_https_enabled ? 1 : 0
  project               = local.project_id
  name                  = "${var.lb_name}-redirect-http-forwarding-rule"
  target                = google_compute_target_http_proxy.redirect[0].id
  ip_address            = google_compute_global_address.main.address
  port_range            = "80"
  load_balancing_scheme = var.load_balancing_scheme
}

resource "google_compute_global_forwarding_rule" "redirect_ipv6" {
  count                 = local.is_https_enabled && var.enable_ipv6 ? 1 : 0
  project               = local.project_id
  name                  = "${var.lb_name}-redirect-http-forwarding-rule-ipv6"
  target                = google_compute_target_http_proxy.redirect[0].id
  ip_address            = google_compute_global_address.ipv6[0].address
  port_range            = "80"
  load_balancing_scheme = var.load_balancing_scheme
}
