variable "environment" {
  description = "環境設定。このモジュールは project_id のみを使用しますが、他モジュールとインターフェースを揃えるため同じ形を受け取ります。"
  type = object({
    project_id   = string
    project_name = optional(string)
    region       = optional(string)
    stack_name   = optional(string)
  })
}

variable "repository" {
  description = "Artifact Registry リポジトリの設定。"
  type = object({
    repository_id = string
    format        = string
    location      = string
    description   = optional(string)

    # true の場合、クリーンアップポリシーは削除を行わず対象のログ出力のみ行う。
    cleanup_policy_dry_run = optional(bool, false)
    kms_key_name           = optional(string)

    docker_config = optional(object({
      immutable_tags = optional(bool, false)
    }))

    # condition と most_recent_versions はどちらか一方のみを指定する。
    cleanup_policies = optional(list(object({
      id     = string
      action = string
      condition = optional(object({
        tag_state             = optional(string)
        tag_prefixes          = optional(list(string))
        version_name_prefixes = optional(list(string))
        package_name_prefixes = optional(list(string))
        older_than            = optional(string)
        newer_than            = optional(string)
      }))
      most_recent_versions = optional(object({
        package_name_prefixes = optional(list(string))
        keep_count            = optional(number)
      }))
    })), [])

    iam_role_members = optional(list(object({
      role    = string
      members = list(string)
    })), [])
  })

  validation {
    condition = contains(
      ["DOCKER", "MAVEN", "NPM", "PYTHON", "APT", "YUM", "KFP", "GO", "GENERIC"],
      upper(var.repository.format)
    )
    error_message = "repository.format は DOCKER, MAVEN, NPM, PYTHON, APT, YUM, KFP, GO, GENERIC のいずれかを指定してください。"
  }

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.repository.repository_id))
    error_message = "repository.repository_id は小文字英数字とハイフンのみ、63文字以内で指定してください。"
  }

  validation {
    condition = length(var.repository.cleanup_policies) == length(distinct([
      for policy in var.repository.cleanup_policies : policy.id
    ]))
    error_message = "repository.cleanup_policies の id は一意でなければなりません。"
  }

  validation {
    condition = alltrue([
      for policy in var.repository.cleanup_policies :
      contains(["KEEP", "DELETE"], upper(policy.action))
    ])
    error_message = "cleanup_policies.action は KEEP または DELETE を指定してください。"
  }

  # API 側の制約: 1 ポリシーに condition と most_recent_versions を同時指定できない。
  validation {
    condition = alltrue([
      for policy in var.repository.cleanup_policies :
      !(policy.condition != null && policy.most_recent_versions != null)
    ])
    error_message = "cleanup_policies では condition と most_recent_versions を同時に指定できません。ポリシーを分割してください。"
  }

  validation {
    condition = alltrue([
      for policy in var.repository.cleanup_policies :
      policy.condition != null || policy.most_recent_versions != null
    ])
    error_message = "cleanup_policies では condition または most_recent_versions のいずれかを指定してください。"
  }

  validation {
    condition = alltrue(flatten([
      for iam_role_member in var.repository.iam_role_members : [
        for member in iam_role_member.members :
        can(regex("^(user|group|serviceAccount|domain|principal|principalSet|projectOwner|projectEditor|projectViewer|allUsers|allAuthenticatedUsers)", member))
      ]
    ]))
    error_message = "iam_role_members.members は 'serviceAccount:...' のように IAM プリンシパルの接頭辞付きで指定してください。"
  }
}

variable "labels" {
  description = "リポジトリに適用するラベル。"
  type        = map(string)
  default     = {}
}
