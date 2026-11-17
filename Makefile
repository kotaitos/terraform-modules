# ------------------------------------------------------------------------------
# terraform-modules 開発用タスク
#
#   make preflight   # コミット前の一括チェック (fmt + policy + validate + test + lint)
#   make check       # CI と同じチェック (preflight + security)
#   make fmt-fix     # フォーマットを自動修正
#   make test        # terraform test のみ
#   make MODULE=modules/google/external-lb test   # 単一モジュールのみ
#   make new-module NAME=google/pubsub-topic      # モジュールの雛形を作る
# ------------------------------------------------------------------------------
SHELL := /bin/bash

# ターミナルが接続されていない（CI など）場合は色を無効化する
ifeq ($(TERM),)
  GREEN  :=
  RED    :=
  YELLOW :=
  BOLD   :=
  RESET  :=
else
  GREEN  := $(shell tput -Txterm setaf 2)
  RED    := $(shell tput -Txterm setaf 1)
  YELLOW := $(shell tput -Txterm setaf 3)
  BOLD   := $(shell tput -Txterm bold)
  RESET  := $(shell tput -Txterm sgr0)
endif

# main.tf を持つディレクトリをモジュールとみなす。モジュールが増えても設定を足す必要はない。
#   MODULE=<path>            単一モジュールだけを対象にする
#   MODULES="<path> <path>"  複数モジュールを対象にする（CI が変更分だけを検証するのに使う）
ifdef MODULE
  MODULES := $(MODULE)
else
  MODULES := $(shell find modules -mindepth 2 -type f -name main.tf -exec dirname {} \; | sort)
endif

# プロバイダーのダウンロードをモジュール間で共有する。
# これがないと 8 モジュール分のプロバイダーを個別にダウンロードすることになる。
PLUGIN_CACHE_DIR := $(CURDIR)/.terraform-plugin-cache
# terraform はキャッシュディレクトリが存在しないとどのコマンドでも警告/エラーになるため、
# Makefile のパース時点で作っておく。
_ := $(shell mkdir -p $(PLUGIN_CACHE_DIR))
export TF_PLUGIN_CACHE_DIR := $(PLUGIN_CACHE_DIR)
export TF_IN_AUTOMATION := 1

# 補助ツール (tflint / trivy / pre-commit) のバージョンは .tool-versions で固定し、
# mise (https://mise.jdx.dev/) が管理する。自前のインストーラーは持たない。
# mise が入っていればそれ経由で実行し、無ければ PATH 上のものを使う。
MISE_EXEC := $(if $(shell command -v mise 2>/dev/null),mise exec --,)
TFLINT    := $(MISE_EXEC) tflint
TRIVY     := $(MISE_EXEC) trivy
# tflint のプラグインはリポジトリ内に置き、CI でキャッシュできるようにする。
export TFLINT_PLUGIN_DIR := $(CURDIR)/.tools/tflint-plugins

# ツールが無いときに「command not found」ではなく導入手順を出して落ちる。
define require
	@$(1) --version >/dev/null 2>&1 || { \
	    printf "  $(RED)%s が見つかりません。$(RESET) 'make tools' を実行してください。\n" "$(2)"; \
	    exit 1; \
	 }
endef

PYTHON := python3

.PHONY: help preflight check fmt fmt-fix policy validate test lint security \
        tools hooks new-module test-scripts providers clean

help:
	@echo "$(BOLD)Available targets:$(RESET)"
	@echo "  preflight    fmt + policy + validate + test + lint（コミット前に実行）"
	@echo "  check        preflight + security（CI と同じ内容）"
	@echo "  fmt          terraform fmt -check (差分があれば失敗)"
	@echo "  fmt-fix      terraform fmt (自動修正)"
	@echo "  policy       リポジトリ規約のチェック（必須ファイル・README と実装の整合など）"
	@echo "  validate     各モジュールの terraform validate"
	@echo "  test         各モジュールの terraform test"
	@echo "  lint         tflint"
	@echo "  security     trivy による misconfiguration スキャン"
	@echo "  tools        .tool-versions のツールを mise でインストールする"
	@echo "  hooks        git フック（pre-commit / commit-msg）を有効にする"
	@echo "  new-module   モジュールの雛形を作る (make new-module NAME=google/pubsub-topic DESC=\"概要\")"
	@echo "  test-scripts scripts/ 自身のテスト"
	@echo "  providers    プロバイダーの最新版がバージョン制約の範囲内かを確認する"
	@echo "  clean        .terraform とキャッシュ、.tools を削除する"
	@echo ""
	@echo ""
	@echo "$(BOLD)対象モジュールの絞り込み:$(RESET)"
	@echo "  make MODULE=modules/google/external-lb test              単一モジュール"
	@echo "  make MODULES=\"\$$(scripts/changed-modules.sh origin/main)\" test     変更のあったモジュールのみ"
	@echo ""
	@echo "$(BOLD)Modules:$(RESET)"
	@for module in $(MODULES); do echo "  $$module"; done

preflight: fmt policy validate test lint
	@echo "$(GREEN)$(BOLD)✨ All preflight checks passed!$(RESET)"

check: preflight security
	@echo "$(GREEN)$(BOLD)✨ All checks passed!$(RESET)"

# ------------------------------------------------------------------------------
# フォーマット
# ------------------------------------------------------------------------------
fmt:
	@echo "$(YELLOW)==> Checking Terraform format...$(RESET)"
	@if output=$$(terraform fmt -check -recursive -diff modules templates 2>&1) && [ -z "$$output" ]; then \
	    echo "  $(GREEN)OK$(RESET)"; \
	 else \
	    echo "  $(RED)FAILED$(RESET) (run 'make fmt-fix')"; \
	    echo "$$output"; \
	    exit 1; \
	 fi

fmt-fix:
	@echo "$(YELLOW)==> Formatting Terraform files...$(RESET)"
	@terraform fmt -recursive modules templates

# ------------------------------------------------------------------------------
# 規約チェック
# ------------------------------------------------------------------------------
# docs/coding_standards.md と docs/module_contribution_guidelines.md のうち、
# 機械的に判定できるルール（必須ファイル、provider ブロックの禁止、バージョン制約、
# README と実装の整合、テストの構成）を検査する。
policy:
	@echo "$(YELLOW)==> Checking repository conventions...$(RESET)"
	@$(PYTHON) scripts/lint-modules.py $(MODULE)

# ------------------------------------------------------------------------------
# 検証
# ------------------------------------------------------------------------------
validate:
	@echo "$(YELLOW)==> Validating Terraform modules...$(RESET)"
	@failed=0; \
	 for module in $(MODULES); do \
	    printf "  %-56s " "$$module"; \
	    if ! init_output=$$(cd "$$module" && terraform init -backend=false -input=false -no-color 2>&1); then \
	        echo "$(RED)INIT FAILED$(RESET)"; echo "$$init_output" | sed 's/^/      /'; failed=1; continue; \
	    fi; \
	    if validate_output=$$(cd "$$module" && terraform validate -no-color 2>&1); then \
	        echo "$(GREEN)VALID$(RESET)"; \
	    else \
	        echo "$(RED)INVALID$(RESET)"; echo "$$validate_output" | sed 's/^/      /'; failed=1; \
	    fi; \
	 done; \
	 exit $$failed

# ------------------------------------------------------------------------------
# テスト
# ------------------------------------------------------------------------------
test:
	@echo "$(YELLOW)==> Testing Terraform modules...$(RESET)"
	@failed=0; \
	 for module in $(MODULES); do \
	    printf "$(YELLOW)▶ Module:$(RESET) %s\n" "$$module"; \
	    if ! init_output=$$(cd "$$module" && terraform init -backend=false -input=false -no-color 2>&1); then \
	        printf "    $(RED)❌ INIT FAILED$(RESET)\n"; echo "$$init_output" | sed 's/^/    /'; failed=1; continue; \
	    fi; \
	    if test_output=$$(cd "$$module" && terraform test -no-color 2>&1); then \
	        echo "$$test_output" | grep -E 'run "[^"]*"\.\.\. (pass|skip)|Success!' \
	          | sed -E 's/ *run "(.*)"\.\.\. pass/    ✅ \1/' \
	          | sed -E 's/ *run "(.*)"\.\.\. skip/    ⏭  \1/' \
	          | sed -E 's/Success! (.*)/    $(GREEN)⭐ \1$(RESET)/'; \
	    else \
	        printf "    $(RED)❌ FAILED$(RESET)\n"; echo "$$test_output" | sed 's/^/    /'; failed=1; \
	    fi; \
	 done; \
	 exit $$failed

# scripts/ 自身のテスト（規約チェッカーが本当に違反を検出できるかを確認する）
test-scripts:
	@echo "$(YELLOW)==> Testing repository scripts...$(RESET)"
	@$(PYTHON) scripts/test-lint-modules.py
	@$(PYTHON) scripts/test-check-provider-versions.py

# プロバイダーの最新版がバージョン制約の範囲内かを確認する（ネットワークが必要）
providers:
	@echo "$(YELLOW)==> Checking provider versions...$(RESET)"
	@$(PYTHON) scripts/check-provider-versions.py

# ------------------------------------------------------------------------------
# リント / セキュリティ
# ------------------------------------------------------------------------------
lint:
	$(call require,$(TFLINT),tflint)
	@echo "$(YELLOW)==> Linting Terraform modules (tflint)...$(RESET)"
	@$(TFLINT) --init --config=$(CURDIR)/.tflint.hcl >/dev/null
	@failed=0; \
	 for module in $(MODULES); do \
	    printf "  %-56s " "$$module"; \
	    if output=$$($(TFLINT) --chdir="$$module" --config=$(CURDIR)/.tflint.hcl --format=compact 2>&1) && [ -z "$$output" ]; then \
	        echo "$(GREEN)OK$(RESET)"; \
	    else \
	        echo "$(RED)ISSUES$(RESET)"; echo "$$output" | sed 's/^/      /'; failed=1; \
	    fi; \
	 done; \
	 exit $$failed

security:
	$(call require,$(TRIVY),trivy)
	@echo "$(YELLOW)==> Scanning for misconfigurations (trivy)...$(RESET)"
	@$(TRIVY) config --config $(CURDIR)/trivy.yaml --quiet . \
	  && echo "  $(GREEN)OK$(RESET)"

# ------------------------------------------------------------------------------
# ツール / 開発環境
# ------------------------------------------------------------------------------
tools:
	@echo "$(YELLOW)==> Installing tools from .tool-versions (mise)...$(RESET)"
	@command -v mise >/dev/null 2>&1 || { \
	    echo "  $(RED)mise が見つかりません。$(RESET)先にインストールしてください:"; \
	    echo "    curl https://mise.run | sh   # または brew install mise"; \
	    echo "    https://mise.jdx.dev/getting-started.html"; \
	    exit 1; \
	 }
	@mise install

# git フックは pre-commit (https://pre-commit.com/) が管理する。
# 何を実行するかは .pre-commit-config.yaml にある。
hooks:
	@echo "$(YELLOW)==> Enabling git hooks (pre-commit)...$(RESET)"
	$(call require,$(MISE_EXEC) pre-commit,pre-commit)
	@# 以前の make hooks が設定した core.hooksPath=.githooks を外す。
	@# 残っていると pre-commit が .git/hooks に入れたフックが無視される。
	@if [ "$$(git config --get core.hooksPath)" = ".githooks" ]; then \
	    git config --unset-all core.hooksPath; \
	    echo "  古い設定 (core.hooksPath=.githooks) を外しました。"; \
	 fi
	@$(MISE_EXEC) pre-commit install --install-hooks
	@echo "  $(GREEN)OK$(RESET) (無効化する場合は 'pre-commit uninstall')"

new-module:
	@if [ -z "$(NAME)" ]; then \
	    echo "$(RED)使い方: make new-module NAME=google/pubsub-topic DESC=\"モジュールの概要\"$(RESET)"; exit 1; \
	 fi
	@$(PYTHON) scripts/new-module.py $(NAME) $(if $(DESC),"$(DESC)")

# ------------------------------------------------------------------------------
# その他
# ------------------------------------------------------------------------------
clean:
	@echo "$(YELLOW)==> Cleaning...$(RESET)"
	@find modules -type d -name .terraform -prune -exec rm -rf {} +
	@rm -rf $(PLUGIN_CACHE_DIR) $(CURDIR)/.tools
	@echo "  $(GREEN)done$(RESET)"
