# TODO: このモジュールが作るリソースを定義する。
# 以下は雛形に含まれるサンプル実装（Google Cloud API の有効化）なので、
# 実装を書いたら置き換える。サンプルのままでも make preflight は通る。

resource "google_project_service" "main" {
  for_each = toset(var.__MODULE_SNAKE__.services)

  project = var.environment.project_id
  service = each.value

  # 既定では destroy 時に API を無効化しない。
  # 同じプロジェクトにある他のリソースを巻き込んで壊さないため。
  disable_on_destroy = var.__MODULE_SNAKE__.disable_on_destroy
}
