# ------------------------------------------------------------------------------
# --- Artifact Registry Repository
# ------------------------------------------------------------------------------
resource "google_artifact_registry_repository" "main" {
  project = var.environment.project_id

  repository_id          = var.repository.repository_id
  format                 = var.repository.format
  location               = var.repository.location
  description            = var.repository.description
  kms_key_name           = var.repository.kms_key_name
  cleanup_policy_dry_run = var.repository.cleanup_policy_dry_run
  labels                 = var.labels

  dynamic "docker_config" {
    for_each = var.repository.docker_config != null ? [var.repository.docker_config] : []
    content {
      immutable_tags = docker_config.value.immutable_tags
    }
  }

  dynamic "cleanup_policies" {
    for_each = { for policy in var.repository.cleanup_policies : policy.id => policy }
    content {
      id     = cleanup_policies.value.id
      action = upper(cleanup_policies.value.action)

      dynamic "condition" {
        for_each = cleanup_policies.value.condition != null ? [cleanup_policies.value.condition] : []
        content {
          tag_state             = condition.value.tag_state
          tag_prefixes          = condition.value.tag_prefixes
          version_name_prefixes = condition.value.version_name_prefixes
          package_name_prefixes = condition.value.package_name_prefixes
          older_than            = condition.value.older_than
          newer_than            = condition.value.newer_than
        }
      }

      dynamic "most_recent_versions" {
        for_each = cleanup_policies.value.most_recent_versions != null ? [cleanup_policies.value.most_recent_versions] : []
        content {
          package_name_prefixes = most_recent_versions.value.package_name_prefixes
          keep_count            = most_recent_versions.value.keep_count
        }
      }
    }
  }
}

# ------------------------------------------------------------------------------
# --- IAM Member
# --- authoritative ではない google_..._iam_member を使い、モジュール外で付与された
# --- バインディングを破壊しないようにしている。
# ------------------------------------------------------------------------------
resource "google_artifact_registry_repository_iam_member" "main" {
  for_each = {
    for entry in flatten([
      for iam_role_member in var.repository.iam_role_members : [
        for member in iam_role_member.members : {
          role   = iam_role_member.role
          member = member
        }
      ]
    ]) : "${entry.role}:${entry.member}" => entry
  }

  project    = google_artifact_registry_repository.main.project
  location   = google_artifact_registry_repository.main.location
  repository = google_artifact_registry_repository.main.repository_id
  role       = each.value.role
  member     = each.value.member
}
