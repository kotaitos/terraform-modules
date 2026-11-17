#!/usr/bin/env python3
"""新しいモジュールの雛形を作る。

    python3 scripts/new-module.py google/pubsub-topic "Pub/Sub トピック + IAM"
    make new-module NAME=google/pubsub-topic DESC="Pub/Sub トピック + IAM"

templates/module/ をコピーしてプレースホルダーを置換し、ルート README の
モジュール一覧にも行を追加する。生成直後の状態で make preflight が通るので、
そこから実装を差し替えていく。
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
# 雛形はプロバイダーごとに用意する（templates/module/google など）。
# 新しいプロバイダーを追加する手順は templates/module/README.md を参照。
TEMPLATES_ROOT = REPO_ROOT / "templates" / "module"

NAME_PATTERN = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")


def render(text: str, module_name: str, module_path: str) -> str:
    snake = module_name.replace("-", "_")
    title = " ".join(word.capitalize() for word in module_name.split("-"))
    return (
        text.replace("__MODULE_SNAKE__", snake)
        .replace("__MODULE_TITLE__", title)
        .replace("__MODULE_PATH__", module_path)
        .replace("__MODULE_NAME__", module_name)
    )


def add_to_root_readme(module_path: str, module_name: str, description: str) -> bool:
    """ルート README のモジュール一覧に行を追加する。追加したら True。"""
    readme = REPO_ROOT / "README.md"
    md = readme.read_text(encoding="utf-8")
    link = f"./{module_path}"
    if link in md:
        return False

    row = f"| [{module_name}]({link}) | {description} |"
    lines = md.splitlines()
    table_rows = [
        i for i, line in enumerate(lines) if re.match(r"^\| \[[a-z0-9-]+\]\(\./modules/", line)
    ]
    if not table_rows:
        return False

    # パス順に挿入する。プロバイダーが増えても同じプロバイダーのモジュールが
    # まとまり、その中でアルファベット順になる。
    insert_at = table_rows[-1] + 1
    for i in table_rows:
        existing = re.match(r"^\| \[[a-z0-9-]+\]\((\./modules/[^)]+)\)", lines[i])
        if existing and link < existing.group(1):
            insert_at = i
            break
    lines.insert(insert_at, row)
    readme.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="モジュールの雛形を作成する")
    parser.add_argument("name", help="<provider>/<module-name> 形式 (例: google/pubsub-topic)")
    parser.add_argument(
        "description",
        nargs="?",
        default="TODO: 概要を書く",
        help="ルート README のモジュール一覧に載せる 1 行の概要",
    )
    args = parser.parse_args()

    if args.name.count("/") != 1:
        print("エラー: <provider>/<module-name> の形式で指定してください (例: google/pubsub-topic)", file=sys.stderr)
        return 1
    provider, module_name = args.name.split("/")
    for value, label in ((provider, "プロバイダー名"), (module_name, "モジュール名")):
        if not NAME_PATTERN.match(value):
            print(f"エラー: {label} '{value}' は小文字英数字とハイフンで指定してください。", file=sys.stderr)
            return 1

    target = REPO_ROOT / "modules" / provider / module_name
    if target.exists():
        print(f"エラー: {target.relative_to(REPO_ROOT)} は既に存在します。", file=sys.stderr)
        return 1

    template_dir = TEMPLATES_ROOT / provider
    if not template_dir.is_dir():
        available = sorted(d.name for d in TEMPLATES_ROOT.iterdir() if d.is_dir())
        print(
            f"エラー: {provider} の雛形 ({template_dir.relative_to(REPO_ROOT)}) がありません。\n"
            f"  用意されている雛形: {', '.join(available) if available else 'なし'}\n"
            f"  新しいプロバイダーに対応する手順は templates/module/README.md を参照してください。",
            file=sys.stderr,
        )
        return 1

    module_path = f"modules/{provider}/{module_name}"
    target.mkdir(parents=True)
    for src in sorted(template_dir.iterdir()):
        if not src.is_file():
            continue
        (target / src.name).write_text(
            render(src.read_text(encoding="utf-8"), module_name, module_path), encoding="utf-8"
        )
        print(f"  作成: {module_path}/{src.name}")

    if add_to_root_readme(module_path, module_name, args.description):
        print("  更新: README.md (モジュール一覧に追加)")

    subprocess.run(["terraform", "fmt", "-recursive", str(target)], check=False)

    print(
        "\n".join(
            [
                "",
                f"{module_path} を作成しました。次の手順で進めてください。",
                "",
                "  1. main.tf / variables.tf / outputs.tf を実装する（サンプルの google_project_service は置き換える）",
                "  2. main.tftest.hcl のテストを実装に合わせて書き直す（正常系 2 つ以上 + reject_*）",
                "  3. README.md の TODO を埋める（Inputs / Outputs は実装と一致させる。make policy が検査する）",
                *(
                    []
                    if args.description != "TODO: 概要を書く"
                    else ["  4. ルート README.md のモジュール一覧の概要を書く（make policy が TODO のままだと落とす）"]
                ),
                f"  {5 if args.description == 'TODO: 概要を書く' else 4}. make MODULE={module_path} preflight を実行する",
                "",
            ]
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
