#!/usr/bin/env python3
"""前回のリリースタグ以降のコミットから、次のバージョンを算出する。

    python3 scripts/next-version.py                      # HEAD を対象に算出して表示する
    python3 scripts/next-version.py --ref origin/develop # 対象を指定する
    python3 scripts/next-version.py --json               # ワークフローから使う形式で出力する
    python3 scripts/next-version.py --level minor        # 判定を上書きする

リリース作業を自動化するために、「何を上げるか」の判断を人からコミットメッセージに移す。
判定は docs/commit_message.md の `<type>(<scope>): <subject>` 形式を前提とする。

| 判定 | 条件 |
| :--- | :--- |
| MAJOR | `feat(scope)!: ...` のように type の後ろに `!` が付く／本文に `BREAKING CHANGE:` がある |
| MINOR | `feat` のコミットが 1 つ以上ある |
| PATCH | それ以外のコミットがある（fix / docs / chore など） |
| なし   | 前回のリリース以降にコミットが無い |

タグが 1 つも無い場合は初回リリースとして v1.0.0 を返す。

終了コード: リリース対象のコミットがあれば 0、無ければ 1（ワークフローの分岐に使う）。
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

FIRST_VERSION = "v1.0.0"

# 判定の根拠として表示するコミットの最大件数
MAX_REASONS = 5

# v1.2.3 だけを「リリース済みのバージョン」として扱う（v1.2.3-rc.1 のようなプレリリースは無視する）
TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")

# <type>(<scope>): <subject> / 破壊的変更は type と `:` の間に `!` を付ける
SUBJECT_RE = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]*)\))?(?P<breaking>!)?:\s*(?P<subject>.+)$")

BREAKING_FOOTER_RE = re.compile(r"^BREAKING[ -]CHANGE:", re.MULTILINE)


def parse_tag(tag: str) -> tuple[int, int, int] | None:
    """`v1.2.3` を (1, 2, 3) にする。形式が違えば None。"""
    m = TAG_RE.match(tag.strip())
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else None


def latest_release_tag(tags: list[str]) -> str | None:
    """タグの一覧から、いちばん新しいリリースタグを返す。"""
    releases = [(parse_tag(tag), tag) for tag in tags]
    releases = [(version, tag) for version, tag in releases if version is not None]
    if not releases:
        return None
    return max(releases)[1]


def classify(message: str) -> tuple[str, str]:
    """1 コミットの内容から (判定, 理由) を返す。"""
    subject = message.strip().splitlines()[0] if message.strip() else ""
    if BREAKING_FOOTER_RE.search(message):
        return "major", subject
    m = SUBJECT_RE.match(subject)
    if not m:
        # 規約に沿わないコミット（過去の履歴や手作業のコミット）は PATCH 扱いにする
        return "patch", subject
    if m.group("breaking"):
        return "major", subject
    if m.group("type") == "feat":
        return "minor", subject
    return "patch", subject


def bump_level(messages: list[str]) -> tuple[str, list[str]]:
    """コミットの一覧から (判定, 判定の根拠になったコミットの subject) を返す。"""
    if not messages:
        return "none", []
    levels = [classify(message) for message in messages]
    for level in ("major", "minor"):
        reasons = [subject for found, subject in levels if found == level]
        if reasons:
            return level, reasons
    return "patch", [subject for _, subject in levels]


def next_version(previous: tuple[int, int, int] | None, level: str) -> str:
    """前回のバージョンと判定から、次のバージョン文字列を返す。"""
    if previous is None:
        return FIRST_VERSION
    major, minor, patch = previous
    if level == "major":
        return f"v{major + 1}.0.0"
    if level == "minor":
        return f"v{major}.{minor + 1}.0"
    return f"v{major}.{minor}.{patch + 1}"


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], check=True, capture_output=True, text=True
    ).stdout


def commit_messages(previous_tag: str | None, ref: str) -> list[str]:
    """前回のリリース以降のコミットメッセージを新しい順に返す（マージコミットは除く）。"""
    revision_range = f"{previous_tag}..{ref}" if previous_tag else ref
    # -z は各コミットを NUL 区切りで出力する（メッセージ中の改行と区別するため）
    output = git("log", "-z", "--no-merges", "--format=%B", revision_range)
    return [message for message in output.split("\0") if message.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default="HEAD", help="対象の ref（既定: HEAD）")
    parser.add_argument("--json", action="store_true", help="JSON で出力する")
    parser.add_argument(
        "--level",
        choices=["major", "minor", "patch"],
        help="コミットからの判定を上書きする",
    )
    args = parser.parse_args()

    tags = git("tag", "--list", "v*").splitlines()
    previous_tag = latest_release_tag(tags)
    messages = commit_messages(previous_tag, args.ref)
    level, reasons = bump_level(messages)

    if args.level:
        reasons = [f"--level {args.level} で指定されました"] if level == "none" else reasons
        level = args.level

    version = next_version(parse_tag(previous_tag) if previous_tag else None, level)
    releasable = level != "none"
    # 根拠は判定を追えるだけの件数で十分（詳細はリリースノートに載る）
    shown, omitted = reasons[:MAX_REASONS], max(0, len(reasons) - MAX_REASONS)

    if args.json:
        print(
            json.dumps(
                {
                    "previous": previous_tag or "",
                    "next": version if releasable else "",
                    "level": level,
                    "commits": len(messages),
                    "reasons": shown,
                    "omitted_reasons": omitted,
                    "first_release": previous_tag is None,
                },
                ensure_ascii=False,
            )
        )
    else:
        print(f"  前回のリリース : {previous_tag or 'なし（初回リリース）'}")
        print(f"  対象コミット   : {len(messages)} 件 ({previous_tag or '最初のコミット'}..{args.ref})")
        if releasable:
            print(f"  次のバージョン : {version} ({level.upper()})")
            print("  判定の根拠     :")
            for reason in shown:
                print(f"    - {reason}")
            if omitted:
                print(f"    - ほか {omitted} 件")
        else:
            print("  次のバージョン : なし（リリースする変更がありません）")

    return 0 if releasable else 1


if __name__ == "__main__":
    sys.exit(main())
