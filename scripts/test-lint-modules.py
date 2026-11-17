#!/usr/bin/env python3
"""scripts/lint-modules.py のテスト。

templates/module/ から「規約を満たしたモジュール」を一時ディレクトリに作り、
1 か所ずつ規約違反を混ぜて、期待したチェックが発火するかを確認する。

    python3 scripts/test-lint-modules.py
    make test-scripts

tflint に任せたルール（変数の description / type、出力の description など）はここでは
検査しない。重複した検査を持つと片方が腐るため。対応表は lint-modules.py の docstring にある。

チェッカーを直すたびに手で壊したモジュールを用意しなくて済むようにするためのもの。
テンプレートが規約を満たしていること（= make new-module 直後に make policy が通ること）も
最初のケースで確認している。
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TEMPLATES_ROOT = REPO_ROOT / "templates" / "module"
LINTER = REPO_ROOT / "scripts" / "lint-modules.py"
MODULE_NAME = "example"
MODULE_PATH = f"modules/google/{MODULE_NAME}"

ROOT_README = f"""# terraform-modules (fixture)

| モジュール | 概要 |
| :--- | :--- |
| [{MODULE_NAME}](./{MODULE_PATH}) | テスト用のモジュール |
"""


def templates() -> list[Path]:
    """プロバイダーごとの雛形ディレクトリを列挙する。"""
    return sorted(d for d in TEMPLATES_ROOT.iterdir() if d.is_dir())


def build_fixture(root: Path, template_dir: Path | None = None) -> Path:
    """規約を満たしたモジュールを 1 つ持つリポジトリを作る。"""
    template_dir = template_dir or (TEMPLATES_ROOT / "google")
    module_dir = root / MODULE_PATH
    module_dir.mkdir(parents=True)
    for src in sorted(template_dir.iterdir()):
        if not src.is_file():
            continue
        text = src.read_text(encoding="utf-8")
        text = (
            text.replace("__MODULE_SNAKE__", MODULE_NAME.replace("-", "_"))
            .replace("__MODULE_TITLE__", MODULE_NAME.capitalize())
            .replace("__MODULE_PATH__", MODULE_PATH)
            .replace("__MODULE_NAME__", MODULE_NAME)
        )
        (module_dir / src.name).write_text(text, encoding="utf-8")
    (root / "README.md").write_text(ROOT_README, encoding="utf-8")
    return module_dir


def run_linter(root: Path) -> tuple[int, str]:
    env = dict(os.environ, TFMODULES_LINT_ROOT=str(root), NO_COLOR="1")
    env.pop("GITHUB_ACTIONS", None)
    result = subprocess.run(
        [sys.executable, str(LINTER), "--format", "text"],
        cwd=root,
        env=env,
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout + result.stderr


# ------------------------------------------------------------------------------
# 壊し方（fixture のルートを受け取って 1 か所だけ規約違反にする）
# ------------------------------------------------------------------------------
def edit(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    assert old in text, f"{path.name} に置換対象が見つかりません: {old!r}"
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def append(path: Path, text: str) -> None:
    path.write_text(path.read_text(encoding="utf-8") + text, encoding="utf-8")


CASES: list[tuple[str, str, object]] = [
    ("M001", "必須ファイルがない", lambda m, r: (m / "main.tftest.hcl").unlink()),
    (
        "M002",
        "provider ブロックがある",
        lambda m, r: append(m / "main.tf", '\nprovider "google" {\n  project = var.environment.project_id\n}\n'),
    ),
    (
        "M003",
        "required_version が揃っていない",
        lambda m, r: edit(m / "versions.tf", '">= 1.10"', '">= 1.5"'),
    ),
    (
        "M004",
        "プロバイダーのバージョンに上限がない",
        lambda m, r: edit(m / "versions.tf", '">= 6.0.0, < 8.0.0"', '">= 6.0.0"'),
    ),
    (
        "M005",
        "宣言していないプロバイダーを使っている",
        lambda m, r: append(m / "main.tf", '\nresource "random_password" "main" {\n  length = 16\n}\n'),
    ),
    (
        "V003",
        "any 型を使っている",
        lambda m, r: append(
            m / "variables.tf",
            '\nvariable "loose" {\n  description = "any を含む変数。"\n  type        = map(any)\n  default     = {}\n}\n',
        ),
    ),
    (
        "T001",
        "正常系のテストが 1 つしかない",
        lambda m, r: (m / "main.tftest.hcl").write_text(
            re.sub(
                r'(?ms)^run "full" \{.*?^\}\n',
                "",
                (m / "main.tftest.hcl").read_text(encoding="utf-8"),
            ),
            encoding="utf-8",
        ),
    ),
    (
        "T002",
        "validation のテストがない",
        lambda m, r: (m / "main.tftest.hcl").write_text(
            re.sub(
                r'(?ms)^run "reject_.*',
                "",
                (m / "main.tftest.hcl").read_text(encoding="utf-8"),
            ),
            encoding="utf-8",
        ),
    ),
    (
        "T003",
        "mock_provider がない",
        lambda m, r: edit(m / "main.tftest.hcl", 'mock_provider "google" {}', ""),
    ),
    ("D001", "README のセクションが足りない", lambda m, r: edit(m / "README.md", "## Notes", "## その他")),
    (
        "D002",
        "Inputs の表に変数がない",
        lambda m, r: edit(m / "README.md", "| environment | 環境設定。 | `object` | n/a | yes |\n", ""),
    ),
    (
        "D003",
        "Outputs の表が実装と食い違っている",
        lambda m, r: edit(m / "README.md", "| project_id | リソースを作成した", "| project | リソースを作成した"),
    ),
    (
        "D004",
        "Requirements が versions.tf と食い違っている",
        lambda m, r: edit(m / "README.md", "| google | >= 6.0.0, < 8.0.0 |", "| google | >= 5.0.0, < 8.0.0 |"),
    ),
    (
        "D005",
        "使い方にコピー＆ペーストの例がない",
        lambda m, r: edit(m / "README.md", f'source = "./modules/{MODULE_NAME}"', 'source = "../x"'),
    ),
    (
        "D006",
        "object 型変数のネストした表がない",
        lambda m, r: edit(m / "README.md", "### `environment`", "### environment の説明"),
    ),
    (
        "D007",
        "ネストした表が型と食い違っている",
        lambda m, r: edit(
            m / "README.md",
            "| project_id | デプロイ先の Google Cloud プロジェクト ID。 | `string` | n/a | yes |",
            "| project | デプロイ先の Google Cloud プロジェクト ID。 | `string` | n/a | yes |",
        ),
    ),
    (
        "R001",
        "ルート README の一覧にモジュールがない",
        lambda m, r: (r / "README.md").write_text("# terraform-modules (fixture)\n", encoding="utf-8"),
    ),
    (
        "R002",
        "ルート README の概要が TODO のまま",
        lambda m, r: edit(r / "README.md", "テスト用のモジュール", "TODO: 概要を書く"),
    ),
]


def main() -> int:
    use_color = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None
    green = "\033[32m" if use_color else ""
    red = "\033[31m" if use_color else ""
    reset = "\033[0m" if use_color else ""

    failures = 0

    # 1. すべての雛形（プロバイダーごと）が規約を満たしていること。
    #    新しいプロバイダーの雛形を足すと、このテストが自動的にそれも検査する。
    for template_dir in templates():
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            build_fixture(root, template_dir)
            code, output = run_linter(root)
            ok = code == 0
            failures += 0 if ok else 1
            status = f"{green}PASS{reset}" if ok else f"{red}FAIL{reset}"
            print(f"  {template_dir.name + ' の雛形は規約を満たしている':<44} {status}")
            if not ok:
                print(output)

    # 2. 1 か所ずつ壊して、期待したチェックが発火すること
    for code_id, description, mutate in CASES:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            module_dir = build_fixture(root)
            mutate(module_dir, root)
            exit_code, output = run_linter(root)
            detected = f"[{code_id}]" in output and exit_code == 1
            failures += 0 if detected else 1
            status = f"{green}PASS{reset}" if detected else f"{red}FAIL{reset}"
            print(f"  {code_id} {description:<40} {status}")
            if not detected:
                print(f"      期待したコード {code_id} が検出されませんでした (exit={exit_code}):")
                print("\n".join(f"      {line}" for line in output.splitlines()))

    if failures:
        print(f"  {red}{failures} 件のテストが失敗しました。{reset}")
        return 1
    print(f"  {green}すべてのチェックが期待どおりに動作しています。{reset}")
    return 0


if __name__ == "__main__":
    if not shutil.which("python3"):
        print("python3 が必要です。", file=sys.stderr)
        sys.exit(1)
    sys.exit(main())
