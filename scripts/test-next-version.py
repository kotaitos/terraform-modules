#!/usr/bin/env python3
"""scripts/next-version.py のバージョン算出のテスト。

    python3 scripts/test-next-version.py
    make test-scripts

git にはアクセスしない（コミットメッセージからの判定と、バージョンの計算だけを検査する）。
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "next-version.py"

spec = importlib.util.spec_from_file_location("next_version", MODULE_PATH)
nv = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(nv)

# (説明, コミットメッセージの一覧, 期待する判定)
LEVEL_CASES: list[tuple[str, list[str], str]] = [
    ("コミットが無ければリリースしない", [], "none"),
    ("feat は MINOR", ["feat(modules/google/pubsub-topic): トピックを追加"], "minor"),
    ("fix は PATCH", ["fix(modules/google/external-lb): 証明書の依存順序を修正"], "patch"),
    ("docs は PATCH", ["docs: リリース手順を更新"], "patch"),
    ("chore は PATCH", ["chore(ci): actions のバージョンを更新"], "patch"),
    ("`!` 付きは MAJOR", ["feat(modules/google/postgres-psc)!: 変数名を変更"], "major"),
    ("scope なしの `!` も MAJOR", ["refactor!: 変数を必須にする"], "major"),
    (
        "本文の BREAKING CHANGE も MAJOR",
        ["fix(modules/google/external-lb): 変数を整理\n\nBREAKING CHANGE: dns 変数を削除しました。"],
        "major",
    ),
    ("BREAKING-CHANGE 表記も MAJOR", ["fix(x): y\n\nBREAKING-CHANGE: z"], "major"),
    ("MAJOR は MINOR より優先される", ["feat(a): b", "feat(c)!: d"], "major"),
    ("MINOR は PATCH より優先される", ["fix(a): b", "feat(c): d", "docs: e"], "minor"),
    ("規約に沿わないコミットは PATCH", ["いろいろ整備", "Update README.md"], "patch"),
    ("本文に BREAKING CHANGE を含む単語があっても誤判定しない", ["docs: BREAKING CHANGE の書き方を説明"], "patch"),
]

# (前回のバージョン, 判定, 期待する次のバージョン)
VERSION_CASES: list[tuple[tuple[int, int, int] | None, str, str]] = [
    (None, "minor", "v1.0.0"),
    (None, "patch", "v1.0.0"),
    ((1, 2, 3), "major", "v2.0.0"),
    ((1, 2, 3), "minor", "v1.3.0"),
    ((1, 2, 3), "patch", "v1.2.4"),
    ((1, 9, 9), "minor", "v1.10.0"),
]

# (タグの一覧, 期待するいちばん新しいリリースタグ)
TAG_CASES: list[tuple[list[str], str | None]] = [
    ([], None),
    (["v1.0.0"], "v1.0.0"),
    # 文字列比較では v1.10.0 < v1.9.0 になってしまうため、数値で比較できていることを確認する
    (["v1.9.0", "v1.10.0", "v1.2.0"], "v1.10.0"),
    (["v1.0.0", "v2.0.0", "v1.5.3"], "v2.0.0"),
    # プレリリースと形式違いのタグは無視する
    (["v1.0.0", "v1.1.0-rc.1", "latest", "v1.0"], "v1.0.0"),
    (["v1.1.0-rc.1"], None),
]


def main() -> int:
    failures = 0

    for description, messages, expected in LEVEL_CASES:
        actual, _ = nv.bump_level(messages)
        ok = actual == expected
        failures += 0 if ok else 1
        print(f"  {'PASS' if ok else 'FAIL'}  {description}: 期待 {expected} / 実際 {actual}")

    for previous, level, expected in VERSION_CASES:
        actual = nv.next_version(previous, level)
        ok = actual == expected
        failures += 0 if ok else 1
        print(f"  {'PASS' if ok else 'FAIL'}  {previous} + {level} -> 期待 {expected} / 実際 {actual}")

    for tags, expected in TAG_CASES:
        actual = nv.latest_release_tag(tags)
        ok = actual == expected
        failures += 0 if ok else 1
        print(f"  {'PASS' if ok else 'FAIL'}  {tags} -> 期待 {expected} / 実際 {actual}")

    if failures:
        print(f"  {failures} 件のテストが失敗しました。")
        return 1
    print("  バージョンの算出は期待どおりです。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
