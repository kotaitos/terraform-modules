#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# 変更のあったモジュールだけを列挙する（CI で validate / test / lint の対象を絞るため）。
#
#   scripts/changed-modules.sh origin/main        # 指定した ref との差分
#   scripts/changed-modules.sh origin/main HEAD   # 比較対象を明示する
#
# Makefile / scripts / 雛形 / ツール設定のように「全モジュールに影響する変更」の場合は、
# 全モジュールを出力する。モジュール数が増えても CI 時間が線形に伸びないようにするための
# 仕組みなので、影響範囲を取りこぼさないほうを優先する。
# ------------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

base="${1:-}"
head="${2:-HEAD}"

all_modules() {
  find modules -mindepth 2 -type f -name main.tf -exec dirname {} \; | sort
}

# 比較対象がない場合（初回 push など）は全モジュールを対象にする
if [ -z "${base}" ] || ! git rev-parse --verify --quiet "${base}" >/dev/null; then
  all_modules
  exit 0
fi

changed="$(git diff --name-only "${base}...${head}")"

# 全モジュールに影響する変更かどうか
if echo "${changed}" | grep -qE '^(Makefile|\.tool-versions|\.tflint\.hcl|trivy\.yaml|\.trivyignore\.yaml|scripts/|templates/|\.github/workflows/)'; then
  all_modules
  exit 0
fi

echo "${changed}" \
  | grep -E '^modules/[^/]+/[^/]+/' \
  | sed -E 's#^(modules/[^/]+/[^/]+)/.*#\1#' \
  | sort -u \
  | while read -r module; do
      # 削除されたモジュールは対象にしない
      [ -f "${module}/main.tf" ] && echo "${module}"
    done
