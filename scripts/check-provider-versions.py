#!/usr/bin/env python3
"""各モジュールの required_providers と、Terraform Registry の最新版を突き合わせる。

    python3 scripts/check-provider-versions.py            # 表を出力する
    python3 scripts/check-provider-versions.py --markdown # Markdown の表で出力する

このリポジトリはプロバイダーのバージョンに上限（`< 8.0.0` など）を付けている。
上限を超えるメジャーバージョンが出ていることに気付かないと、利用者が新しい
プロバイダーを使えないまま取り残されるので、定期的に検出して知らせる。

終了コード: 上限を超える安定版が出ていれば 1、そうでなければ 0。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
REGISTRY = "https://registry.terraform.io/v1/providers/{source}/versions"

VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def parse_version(value: str) -> tuple[int, int, int] | None:
    m = VERSION_RE.match(value.strip())
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else None


def satisfies(version: tuple[int, int, int], constraint: str) -> bool:
    """`>= 6.0.0, < 8.0.0` 形式の制約を満たすかどうかを返す。"""
    for part in constraint.split(","):
        part = part.strip()
        m = re.match(r"^(>=|<=|>|<|=|~>)?\s*(\d+(?:\.\d+){0,2})$", part)
        if not m:
            continue
        operator = m.group(1) or "="
        numbers = [int(n) for n in m.group(2).split(".")]
        bound = tuple(numbers + [0] * (3 - len(numbers)))
        if operator == ">=" and not version >= bound:
            return False
        if operator == ">" and not version > bound:
            return False
        if operator == "<=" and not version <= bound:
            return False
        if operator == "<" and not version < bound:
            return False
        if operator == "=" and version != bound:
            return False
        if operator == "~>":
            # ~> 3.5.0 は >= 3.5.0, < 3.6.0 / ~> 3.5 は >= 3.5.0, < 4.0.0
            if not version >= bound:
                return False
            upper = (bound[0], bound[1] + 1, 0) if len(numbers) == 3 else (bound[0] + 1, 0, 0)
            if not version < upper:
                return False
    return True


def collect_constraints() -> dict[str, dict[str, set[str]]]:
    """{source: {constraint: {モジュール名, ...}}} を返す。"""
    found: dict[str, dict[str, set[str]]] = {}
    for versions_tf in sorted((REPO_ROOT / "modules").glob("*/*/versions.tf")):
        module = str(versions_tf.parent.relative_to(REPO_ROOT))
        text = versions_tf.read_text(encoding="utf-8")
        for m in re.finditer(
            r'(?ms)^\s*[A-Za-z0-9_-]+\s*=\s*\{\s*source\s*=\s*"([^"]+)"\s*version\s*=\s*"([^"]+)"',
            text,
        ):
            source, constraint = m.group(1), m.group(2)
            found.setdefault(source, {}).setdefault(constraint, set()).add(module)
    return found


def latest_stable(source: str) -> str | None:
    url = REGISTRY.format(source=source)
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            payload = json.load(response)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        print(f"警告: {source} のバージョン取得に失敗しました: {error}", file=sys.stderr)
        return None
    versions = [v["version"] for v in payload.get("versions", [])]
    stable = sorted((p for v in versions if (p := parse_version(v))), reverse=True)
    return ".".join(str(n) for n in stable[0]) if stable else None


def main() -> int:
    parser = argparse.ArgumentParser(description="プロバイダーのバージョン制約と最新版を比較する")
    parser.add_argument("--markdown", action="store_true", help="Markdown の表で出力する")
    args = parser.parse_args()

    rows: list[tuple[str, str, str, bool, str]] = []
    outdated = False
    for source, constraints in sorted(collect_constraints().items()):
        latest = latest_stable(source)
        for constraint, modules in sorted(constraints.items()):
            if latest is None:
                rows.append((source, constraint, "取得失敗", True, ", ".join(sorted(modules))))
                continue
            allowed = satisfies(parse_version(latest), constraint)
            outdated = outdated or not allowed
            rows.append((source, constraint, latest, allowed, ", ".join(sorted(modules))))

    if args.markdown:
        print("| プロバイダー | 制約 | 最新版 | 状態 | モジュール |")
        print("| :--- | :--- | :--- | :---: | :--- |")
        for source, constraint, latest, allowed, modules in rows:
            status = "✅" if allowed else "⚠️ 上限超過"
            print(f"| `{source}` | `{constraint}` | `{latest}` | {status} | {modules} |")
        if outdated:
            print("")
            print("制約の上限を超える安定版が出ています。破壊的変更を確認したうえで、")
            print("`versions.tf` の上限（と各モジュールの README の Requirements）を上げてください。")
    else:
        for source, constraint, latest, allowed, modules in rows:
            status = "OK" if allowed else "上限超過"
            print(f"  {source:<28} 制約: {constraint:<22} 最新: {latest:<10} {status}")
            if not allowed:
                print(f"      対象モジュール: {modules}")

    return 1 if outdated else 0


if __name__ == "__main__":
    sys.exit(main())
