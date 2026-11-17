#!/usr/bin/env python3
"""scripts/check-provider-versions.py のバージョン制約判定のテスト。

    python3 scripts/test-check-provider-versions.py
    make test-scripts

ネットワークにはアクセスしない（制約の解釈だけを検査する）。
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "check-provider-versions.py"

spec = importlib.util.spec_from_file_location("check_provider_versions", MODULE_PATH)
checker = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(checker)

CASES: list[tuple[str, str, bool]] = [
    # (バージョン, 制約, 満たすか)
    ("7.45.0", ">= 6.0.0, < 8.0.0", True),
    ("8.0.0", ">= 6.0.0, < 8.0.0", False),
    ("8.1.2", ">= 6.0.0, < 8.0.0", False),
    ("5.9.9", ">= 6.0.0, < 8.0.0", False),
    ("6.0.0", ">= 6.0.0, < 8.0.0", True),
    ("3.9.0", ">= 3.5.0, < 4.0.0", True),
    ("4.0.0", ">= 3.5.0, < 4.0.0", False),
    ("3.5.9", "~> 3.5.0", True),
    ("3.6.0", "~> 3.5.0", False),
    ("3.6.0", "~> 3.5", True),
    ("4.0.0", "~> 3.5", False),
    ("7.0.0", ">= 6.0.0", True),
]


def main() -> int:
    failures = 0
    for version, constraint, expected in CASES:
        actual = checker.satisfies(checker.parse_version(version), constraint)
        ok = actual == expected
        failures += 0 if ok else 1
        status = "PASS" if ok else "FAIL"
        print(f"  {version:<8} vs {constraint:<22} 期待: {str(expected):<5} {status}")

    if failures:
        print(f"  {failures} 件のテストが失敗しました。")
        return 1
    print("  バージョン制約の判定は期待どおりです。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
