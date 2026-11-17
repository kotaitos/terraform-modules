# ------------------------------------------------------------------------------
# tflint の設定
#
#   make lint   # 全モジュールに対して実行する（tflint が無ければ自動でインストールする）
#
# terraform fmt / validate では見つからない問題（未使用の宣言、命名規則違反、
# プロバイダー固有の無効な値など）を検出する。
# バージョンは .tool-versions で固定している。
# ------------------------------------------------------------------------------
config {
  # 各モジュールを単体で検査する。子モジュールの呼び出しは持たないので解析しない。
  call_module_type = "none"
}

plugin "terraform" {
  enabled = true
  # 公式ルールセットのすべてのルールを有効にする。
  # docs/coding_standards.md の規約（命名、description、type、バージョン固定など）と
  # 重なる部分は tflint 側に任せる。
  preset = "all"
}

plugin "google" {
  enabled = true
  version = "0.34.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

# 別のプロバイダー（aws など）のモジュールを追加するときは、
# 対応するルールセットをここに追加する。
# plugin "aws" {
#   enabled = true
#   version = "0.44.0"
#   source  = "github.com/terraform-linters/tflint-ruleset-aws"
# }
