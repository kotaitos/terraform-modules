mock_provider "google" {}

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
    repository = {
      repository_id = "test-repo"
      format        = "DOCKER"
      location      = "asia-northeast1"
    }
  }

  assert {
    condition     = google_artifact_registry_repository.main.repository_id == "test-repo"
    error_message = "repository_id が期待値と一致しません。"
  }

  assert {
    condition     = length(google_artifact_registry_repository.main.cleanup_policies) == 0
    error_message = "cleanup_policies を省略した場合は空でなければなりません。"
  }

  assert {
    condition     = length(google_artifact_registry_repository_iam_member.main) == 0
    error_message = "iam_role_members を省略した場合は IAM メンバーが作られてはいけません。"
  }

  assert {
    condition     = output.docker_repository_url == "asia-northeast1-docker.pkg.dev/test-project-id/test-repo"
    error_message = "docker_repository_url が期待値と一致しません。"
  }
}

run "full" {
  command = plan

  module {
    source = "./"
  }

  variables {
    repository = {
      repository_id          = "test-repo"
      format                 = "DOCKER"
      location               = "asia-northeast1"
      description            = "Test Artifact Registry Repository"
      cleanup_policy_dry_run = true
      docker_config = {
        immutable_tags = true
      }
      cleanup_policies = [
        {
          id     = "keep-recent-releases"
          action = "KEEP"
          most_recent_versions = {
            keep_count = 5
          }
        },
        {
          id     = "delete-old-untagged"
          action = "DELETE"
          condition = {
            tag_state  = "UNTAGGED"
            older_than = "2592000s"
          }
        },
      ]
      iam_role_members = [
        {
          role    = "roles/artifactregistry.reader"
          members = ["serviceAccount:reader@test-project-id.iam.gserviceaccount.com", "group:devs@example.com"]
        },
        {
          role    = "roles/artifactregistry.writer"
          members = ["serviceAccount:writer@test-project-id.iam.gserviceaccount.com"]
        },
      ]
    }
    labels = {
      environment = "test"
    }
  }

  assert {
    condition     = google_artifact_registry_repository.main.docker_config[0].immutable_tags == true
    error_message = "immutable_tags が有効になっていません。"
  }

  assert {
    condition     = google_artifact_registry_repository.main.labels["environment"] == "test"
    error_message = "labels がリポジトリに反映されていません。"
  }

  assert {
    condition     = google_artifact_registry_repository.main.cleanup_policy_dry_run == true
    error_message = "cleanup_policy_dry_run が反映されていません。"
  }

  assert {
    condition     = length(google_artifact_registry_repository.main.cleanup_policies) == 2
    error_message = "cleanup_policies の数が期待値と一致しません。"
  }

  # condition だけを持つポリシー / most_recent_versions だけを持つポリシーの双方が書けること。
  assert {
    condition = alltrue([
      for policy in google_artifact_registry_repository.main.cleanup_policies :
      length(policy.most_recent_versions) == 1 && length(policy.condition) == 0
      if policy.id == "keep-recent-releases"
    ])
    error_message = "most_recent_versions のみのポリシーが正しく組み立てられていません。"
  }

  assert {
    condition = alltrue([
      for policy in google_artifact_registry_repository.main.cleanup_policies :
      length(policy.condition) == 1 && policy.condition[0].older_than == "2592000s"
      if policy.id == "delete-old-untagged"
    ])
    error_message = "condition のみのポリシーが正しく組み立てられていません。"
  }

  assert {
    condition     = length(google_artifact_registry_repository_iam_member.main) == 3
    error_message = "role x member の展開数が期待値と一致しません。"
  }
}

run "reject_policy_with_both_condition_and_most_recent_versions" {
  command = plan

  module {
    source = "./"
  }

  variables {
    repository = {
      repository_id = "test-repo"
      format        = "DOCKER"
      location      = "asia-northeast1"
      cleanup_policies = [
        {
          id                   = "invalid"
          action               = "KEEP"
          condition            = { tag_state = "ANY" }
          most_recent_versions = { keep_count = 1 }
        },
      ]
    }
  }

  expect_failures = [var.repository]
}

run "reject_invalid_format" {
  command = plan

  module {
    source = "./"
  }

  variables {
    repository = {
      repository_id = "test-repo"
      format        = "TARBALL"
      location      = "asia-northeast1"
    }
  }

  expect_failures = [var.repository]
}
