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
    __MODULE_SNAKE__ = {
      services = ["run.googleapis.com"]
    }
  }

  assert {
    condition     = length(google_project_service.main) == 1
    error_message = "services に指定した数だけ API が有効化されなければなりません。"
  }

  assert {
    condition     = google_project_service.main["run.googleapis.com"].disable_on_destroy == false
    error_message = "disable_on_destroy を省略した場合は false でなければなりません。"
  }
}

run "full" {
  command = plan

  module {
    source = "./"
  }

  variables {
    __MODULE_SNAKE__ = {
      services           = ["run.googleapis.com", "artifactregistry.googleapis.com"]
      disable_on_destroy = true
    }
  }

  assert {
    condition     = length(google_project_service.main) == 2
    error_message = "services に指定した数だけ API が有効化されなければなりません。"
  }

  assert {
    condition     = google_project_service.main["run.googleapis.com"].disable_on_destroy == true
    error_message = "disable_on_destroy が設定に反映されていません。"
  }
}

run "reject_empty_services" {
  command = plan

  module {
    source = "./"
  }

  variables {
    __MODULE_SNAKE__ = {
      services = []
    }
  }

  expect_failures = [var.__MODULE_SNAKE__]
}

run "reject_duplicated_services" {
  command = plan

  module {
    source = "./"
  }

  variables {
    __MODULE_SNAKE__ = {
      services = ["run.googleapis.com", "run.googleapis.com"]
    }
  }

  expect_failures = [var.__MODULE_SNAKE__]
}
