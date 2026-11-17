#!/usr/bin/env python3
"""terraform-modules リポジトリの規約チェッカー。

docs/coding_standards.md と docs/module_contribution_guidelines.md に書かれているルールの
うち、機械的に判定できるものを検査する。担当するのは terraform fmt / validate / test や
tflint では検出できない「このリポジトリ固有の約束事」（README と実装の整合、provider
ブロックの禁止、テストの構成など）だけ。

    python3 scripts/lint-modules.py                     # 全モジュール
    python3 scripts/lint-modules.py modules/google/xxx  # 単一モジュール
    python3 scripts/lint-modules.py --format github     # GitHub Actions のアノテーション付き

終了コード: 違反が 1 件でもあれば 1、なければ 0。

一般的な Terraform の作法は tflint の公式ルールセット（.tflint.hcl の `preset = "all"`）に
任せているので、ここでは検査しない。二重に検査すると必ず片方が腐るため、重複させない。

| tflint のルール | 任せている内容 |
| :--- | :--- |
| terraform_standard_module_structure | main.tf / variables.tf / outputs.tf があること |
| terraform_documented_variables | 変数に description があること |
| terraform_typed_variables | 変数に type があること |
| terraform_documented_outputs | 出力に description があること |
| terraform_required_version | required_version があること（値が `>= 1.10` かは M003 で見る） |
| terraform_required_providers | プロバイダーに source / version があること（上下限は M004 で見る） |
| terraform_unused_required_providers | 宣言したのに使っていないプロバイダー（逆は M005 で見る） |
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# 検査対象のリポジトリルート。テスト（scripts/test-lint-modules.py）から
# 一時ディレクトリを差し込めるように環境変数で上書きできるようにしている。
REPO_ROOT = Path(os.environ.get("TFMODULES_LINT_ROOT", Path(__file__).resolve().parent.parent)).resolve()

# tflint の terraform_standard_module_structure が見る main.tf / variables.tf / outputs.tf は
# ここでは検査しない。このリポジトリ固有で要求しているものだけを並べる。
REQUIRED_FILES = (
    "versions.tf",
    "README.md",
    "main.tftest.hcl",
)

REQUIRED_TERRAFORM_VERSION = ">= 1.10"

# README に必ず置く見出し（docs/module_contribution_guidelines.md「7. ドキュメント」）
REQUIRED_README_SECTIONS = (
    "なぜこのモジュールを使うのか",
    "構成リソース",
    "使い方",
    "Inputs",
    "Outputs",
    "Requirements",
    "Notes",
)

# terraform test に最低限求める正常系 run ブロックの数（同「6. テスト」）
MIN_SUCCESS_RUNS = 2


# ------------------------------------------------------------------------------
# HCL の最小限のパース
# ------------------------------------------------------------------------------
def _skip_string(text: str, i: int) -> int:
    """text[i] が `"` のとき、対応する閉じ引用符の次の位置を返す。

    `${...}` の中にネストした文字列も正しく読み飛ばす。
    """
    i += 1  # 開き引用符
    n = len(text)
    while i < n:
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == '"':
            return i + 1
        if c == "$" and text.startswith("${", i):
            i = _skip_interpolation(text, i + 2)
            continue
        if c == "\n":  # 閉じられていない文字列。壊れた入力なのでここで打ち切る。
            return i
        i += 1
    return n


def _skip_interpolation(text: str, i: int) -> int:
    """`${` の直後から、対応する `}` の次の位置を返す。"""
    depth = 1
    n = len(text)
    while i < n:
        c = text[i]
        if c == '"':
            i = _skip_string(text, i)
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def mask(text: str) -> str:
    """コメント・文字列・ヒアドキュメントを空白に潰した、同じ長さの文字列を返す。

    波括弧の対応や属性行の検出を、コメントや文字列リテラルに惑わされずに行うために使う。
    行番号と桁位置を保つため、改行だけはそのまま残す。
    """
    out = list(text)
    i, n = 0, len(text)

    def blank(start: int, end: int) -> None:
        for k in range(start, min(end, n)):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        c = text[i]
        if c == "#" or (c == "/" and text.startswith("//", i)):
            end = text.find("\n", i)
            end = n if end == -1 else end
            blank(i, end)
            i = end
        elif c == "/" and text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = n if end == -1 else end + 2
            blank(i, end)
            i = end
        elif c == '"':
            end = _skip_string(text, i)
            blank(i, end)
            i = end
        elif c == "<" and text.startswith("<<", i):
            m = re.match(r"<<-?([A-Za-z_][A-Za-z0-9_]*)", text[i:])
            if not m:
                i += 1
                continue
            tag = m.group(1)
            body_start = text.find("\n", i)
            if body_start == -1:
                blank(i, n)
                return "".join(out)
            end_re = re.compile(r"^\s*" + re.escape(tag) + r"\s*$", re.M)
            m_end = end_re.search(text, body_start)
            end = m_end.end() if m_end else n
            blank(i, end)
            i = end
        else:
            i += 1
    return "".join(out)


@dataclass
class Block:
    """トップレベルのブロック（resource / variable / output など）。"""

    type: str
    labels: list[str]
    body: str  # 元テキストの本文（波括弧の中身）
    masked_body: str  # 同じ範囲のマスク済みテキスト
    line: int  # 1 始まりの開始行

    @property
    def name(self) -> str:
        return self.labels[0] if self.labels else ""

    def attributes(self) -> dict[str, str]:
        """本文直下（インデント 2）の属性を {名前: 値のテキスト} で返す。

        terraform fmt が通っている前提のインデント依存パースだが、fmt は CI で
        強制しているので実用上は十分。
        """
        attrs: dict[str, str] = {}
        positions: list[tuple[int, str, int]] = []
        for m in re.finditer(r"(?m)^  ([A-Za-z_][\w-]*)\s*=", self.masked_body):
            positions.append((m.start(), m.group(1), m.end()))
        for idx, (_, key, value_start) in enumerate(positions):
            end = positions[idx + 1][0] if idx + 1 < len(positions) else len(self.body)
            # 次の属性より前に「インデント 2 のブロック」が来ていたらそこで切る
            nested = re.search(r"(?m)^  [A-Za-z_][\w-]*[^=\n]*\{\s*$", self.masked_body[value_start:end])
            if nested:
                end = value_start + nested.start()
            attrs[key] = self.body[value_start:end].strip()
        return attrs

    def nested_block_names(self) -> list[str]:
        """本文直下のネストしたブロック名（validation など）を返す。"""
        return re.findall(r"(?m)^  ([A-Za-z_][\w-]*)[^=\n]*\{\s*$", self.masked_body)


def parse_blocks(text: str) -> list[Block]:
    """トップレベル（桁 0 から始まる）のブロックを列挙する。"""
    masked = mask(text)
    blocks: list[Block] = []
    header = re.compile(r'(?m)^([A-Za-z_][\w-]*)((?:\s+"[^"\n]*")*)\s*\{')
    # ラベルは文字列なのでマスク後には消えている。ヘッダー自体は元テキストから読む。
    for m in header.finditer(text):
        start = m.start()
        # マスク後のテキストで見て、その位置が本当にコード（コメント/文字列の中でない）か
        if masked[start] == " ":
            continue
        depth = 0
        i = m.end() - 1  # 開き波括弧の位置
        n = len(masked)
        while i < n:
            if masked[i] == "{":
                depth += 1
            elif masked[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body_start, body_end = m.end(), i
        blocks.append(
            Block(
                type=m.group(1),
                labels=re.findall(r'"([^"\n]*)"', m.group(2)),
                body=text[body_start:body_end],
                masked_body=masked[body_start:body_end],
                line=text.count("\n", 0, start) + 1,
            )
        )
    return blocks


# ------------------------------------------------------------------------------
# 検査結果
# ------------------------------------------------------------------------------
@dataclass
class Issue:
    code: str
    path: str  # リポジトリルートからの相対パス
    message: str
    line: int | None = None


@dataclass
class ModuleReport:
    module: str
    issues: list[Issue] = field(default_factory=list)

    def add(self, code: str, path: str, message: str, line: int | None = None) -> None:
        self.issues.append(Issue(code, path, message, line))


# ------------------------------------------------------------------------------
# Markdown の補助
# ------------------------------------------------------------------------------
def section(md: str, heading: str, level: int = 2) -> str:
    """`## <heading>` から次の同レベル見出しまでを返す。見つからなければ空文字列。"""
    prefix = "#" * level
    pattern = re.compile(
        rf"(?m)^{prefix} +{re.escape(heading)}\s*$(.*?)(?=^{prefix} |\Z)", re.S
    )
    m = pattern.search(md)
    return m.group(1) if m else ""


def first_table(md: str) -> list[list[str]]:
    """最初の Markdown テーブルの本文行をセルのリストで返す。"""
    rows: list[list[str]] = []
    started = False
    for raw in md.splitlines():
        line = raw.strip()
        if line.startswith("|"):
            started = True
            cells = [c.strip() for c in line.strip("|").split("|")]
            rows.append(cells)
        elif started:
            break
    if len(rows) < 2:
        return []
    # 1 行目はヘッダー、2 行目は区切り
    return rows[2:]


def cell_name(cell: str) -> str:
    return cell.strip().strip("`").strip("*").strip()


def nested_tables(md: str) -> dict[str, set[str]]:
    """`### \`path\`` 形式の見出しごとに、その直後の表の Name 列を集める。

    1 つの見出しに複数のパスを書いた場合（`### \`job.env_vars[*]\` / \`job.secret_env_vars[*]\``）は、
    同じ表がどちらのパスの説明でもあるとみなす。
    """
    tables: dict[str, set[str]] = {}
    headings = list(re.finditer(r"(?m)^#{3,4} +(.*)$", md))
    for idx, m in enumerate(headings):
        paths = re.findall(r"`([^`]+)`", m.group(1))
        if not paths:
            continue
        end = headings[idx + 1].start() if idx + 1 < len(headings) else len(md)
        # 次の `## ` 見出しが先に来る場合はそこで切る
        nxt = re.search(r"(?m)^## ", md[m.end() : end])
        body = md[m.end() : m.end() + nxt.start()] if nxt else md[m.end() : end]
        names = {cell_name(row[0]) for row in first_table(body) if row and cell_name(row[0])}
        for path in paths:
            tables.setdefault(path, set()).update(names)
    return tables


# ------------------------------------------------------------------------------
# 変数の型式（object / list / map / optional）のパース
# ------------------------------------------------------------------------------
def split_top_level(text: str, separators: str) -> list[str]:
    """カッコの深さ 0 にある区切り文字で分割する（文字列・コメントは無視）。"""
    masked = mask(text)
    parts: list[str] = []
    depth, start = 0, 0
    for i, ch in enumerate(masked):
        if ch in "({[":
            depth += 1
        elif ch in ")}]":
            depth -= 1
        elif ch in separators and depth == 0:
            parts.append(text[start:i])
            start = i + 1
    parts.append(text[start:])
    return [p.strip() for p in parts if p.strip()]


def parse_type(expr: str) -> dict:
    """型式を {"kind": ...} の木にする。

    kind は "object"（attrs 付き）/ "collection"（elem 付き）/ "scalar" のいずれか。
    optional(T, default) は T として扱う。
    """
    expr = expr.strip()
    m = re.match(r"^([a-z_]+)\s*\(", expr)
    if not m:
        return {"kind": "scalar"}
    masked = mask(expr)
    depth, i = 1, m.end()
    while i < len(expr):
        if masked[i] == "(":
            depth += 1
        elif masked[i] == ")":
            depth -= 1
            if depth == 0:
                break
        i += 1
    inner = expr[m.end() : i]
    fn = m.group(1)
    if fn == "optional":
        args = split_top_level(inner, ",")
        return parse_type(args[0]) if args else {"kind": "scalar"}
    if fn == "object":
        body = inner.strip()
        if body.startswith("{"):
            body = body[1 : body.rfind("}")]
        attrs: dict[str, dict] = {}
        # object の属性は改行またはカンマ区切り
        for part in split_top_level(body, ",\n"):
            am = re.match(r"^([A-Za-z_][\w-]*)\s*=\s*(.*)$", part, re.S)
            if am:
                attrs[am.group(1)] = parse_type(am.group(2))
        return {"kind": "object", "attrs": attrs}
    if fn in ("list", "set", "map"):
        return {"kind": "collection", "elem": parse_type(inner)}
    # tuple(...) は要素ごとに型が違うため、中身までは追わない
    return {"kind": "scalar"}


def object_paths(node: dict, path: str, found: dict[str, dict], depth: int = 0) -> None:
    """型の木を辿り、object になっている位置を {パス: ノード} で集める。

    コレクション（list / set / map）は 1 段ごとに `[*]` を付ける。README のネストした表の
    見出し（`### \`neg_backends[*].log_config\`` など）と同じ表記になる。
    """
    if depth > 8:
        return
    kind = node.get("kind")
    if kind == "collection":
        object_paths(node["elem"], f"{path}[*]", found, depth + 1)
    elif kind == "object":
        found[path] = node
        for name, child in node["attrs"].items():
            object_paths(child, f"{path}.{name}", found, depth + 1)


# ------------------------------------------------------------------------------
# 各検査
# ------------------------------------------------------------------------------
def check_files(mod: Path, rep: ModuleReport) -> None:
    for name in REQUIRED_FILES:
        if not (mod / name).is_file():
            rep.add("M001", str(mod.relative_to(REPO_ROOT)), f"必須ファイル {name} がありません。")


def tf_files(mod: Path) -> list[Path]:
    return sorted(p for p in mod.glob("*.tf"))


def check_no_provider_block(mod: Path, rep: ModuleReport, blocks_by_file) -> None:
    for path, blocks in blocks_by_file.items():
        for b in blocks:
            if b.type == "provider":
                rep.add(
                    "M002",
                    rel(path),
                    f'provider ブロック "{b.name}" はモジュール内に置けません。'
                    "認証情報や project / region の既定値は利用者のルートモジュールの責務です。",
                    b.line,
                )


def check_versions(mod: Path, rep: ModuleReport, blocks_by_file) -> tuple[str | None, dict[str, str]]:
    """versions.tf を検査し、(required_version, {プロバイダー名: バージョン制約}) を返す。"""
    versions_tf = mod / "versions.tf"
    if not versions_tf.is_file():
        return None, {}
    text = versions_tf.read_text(encoding="utf-8")
    tf_blocks = [b for b in parse_blocks(text) if b.type == "terraform"]
    if not tf_blocks:
        rep.add("M003", rel(versions_tf), "terraform ブロックがありません。")
        return None, {}

    attrs = tf_blocks[0].attributes()
    # required_version が無いことは tflint (terraform_required_version) が報告するので、
    # ここでは「あるなら値が揃っているか」だけを見る。
    required_version = attrs.get("required_version", "").strip().strip('"')
    if required_version and required_version != REQUIRED_TERRAFORM_VERSION:
        rep.add(
            "M003",
            rel(versions_tf),
            f'required_version はリポジトリ全体で "{REQUIRED_TERRAFORM_VERSION}" に揃えます '
            f'(現在: "{required_version}")。',
        )

    providers: dict[str, str] = {}
    # required_providers は terraform ブロック直下のネストしたブロックなので、本文から切り出す
    m = re.search(r"(?ms)^  required_providers\s*\{(.*?)^  \}", tf_blocks[0].body)
    if not m:
        rep.add("M004", rel(versions_tf), "required_providers ブロックがありません。")
        return required_version, providers

    body = m.group(1)
    for pm in re.finditer(r"(?ms)^    ([A-Za-z0-9_-]+)\s*=\s*\{(.*?)^    \}", body):
        name, entry = pm.group(1), pm.group(2)
        # source / version が無いことは tflint (terraform_required_providers) が報告する。
        version = re.search(r'version\s*=\s*"([^"]+)"', entry)
        if not version:
            continue
        constraint = version.group(1)
        providers[name] = constraint
        if ">=" not in constraint or "<" not in constraint.replace("<=", ""):
            rep.add(
                "M004",
                rel(versions_tf),
                f'プロバイダー {name} のバージョン制約 "{constraint}" は下限と上限の両方を '
                '指定してください (例: ">= 6.0.0, < 8.0.0")。上限がないと破壊的変更を含む '
                "メジャーバージョンを取り込んでしまいます。",
            )
    return required_version, providers


def check_provider_usage(mod: Path, rep: ModuleReport, blocks_by_file, declared: dict[str, str]) -> None:
    """使っているのに宣言していないプロバイダーを検査する。

    逆（宣言したのに使っていない）は tflint の terraform_unused_required_providers が
    報告するので、ここでは見ない。
    """
    used: set[str] = set()
    for path, blocks in blocks_by_file.items():
        for b in blocks:
            if b.type in ("resource", "data") and b.labels:
                used.add(b.labels[0].split("_", 1)[0])
            if b.type in ("resource", "data", "module"):
                explicit = b.attributes().get("provider")
                if explicit:
                    used.add(explicit.split(".", 1)[0].strip())

    for name in sorted(used - set(declared)):
        rep.add(
            "M005",
            rel(mod / "versions.tf"),
            f"プロバイダー {name} を使っているのに required_providers で宣言していません。"
            "暗黙の推論に依存すると利用者の構成次第で壊れます。",
        )


def type_expression(block: Block) -> str:
    return block.attributes().get("type", "")


def check_variables(mod: Path, rep: ModuleReport, blocks_by_file) -> dict[str, Block]:
    """変数を集めつつ、any 型を禁止する。

    description / type の有無は tflint (terraform_documented_variables /
    terraform_typed_variables) が報告するので、ここでは見ない。
    """
    variables: dict[str, Block] = {}
    for path, blocks in blocks_by_file.items():
        for b in blocks:
            if b.type != "variable":
                continue
            variables[b.name] = b
            type_expr = b.attributes().get("type", "").strip()
            if re.search(r"\bany\b", type_expr):
                rep.add(
                    "V003",
                    rel(path),
                    f"変数 {b.name} の型に any が含まれています。ネストしたオブジェクトも "
                    "明示的に型付けしてください。",
                    b.line,
                )
    return variables


def collect_outputs(blocks_by_file) -> dict[str, Block]:
    """出力を集める（description の有無は tflint の terraform_documented_outputs が見る）。"""
    return {b.name: b for blocks in blocks_by_file.values() for b in blocks if b.type == "output"}


def check_tests(mod: Path, rep: ModuleReport) -> None:
    """テストの構成を検査する。

    run ブロックの名前は内容が伝わるものであればよい（`minimal` などの固定名は求めない）。
    検査するのは「最小構成とフル構成の正常系があるか」「validation が落ちることを
    確認しているか」「モックを使っていて実リソースを作らないか」の 3 点。
    """
    test_file = mod / "main.tftest.hcl"
    if not test_file.is_file():
        return
    text = test_file.read_text(encoding="utf-8")
    runs = [b for b in parse_blocks(text) if b.type == "run"]
    reject_runs = [b for b in runs if "expect_failures" in b.masked_body]
    success_runs = [b for b in runs if b not in reject_runs]

    if len(success_runs) < MIN_SUCCESS_RUNS:
        rep.add(
            "T001",
            rel(test_file),
            f"正常系のテストが {len(success_runs)} 件しかありません。"
            f"最小構成（既定値の確認）とフル構成（主要オプションの反映確認）で "
            f"最低 {MIN_SUCCESS_RUNS} 件用意してください。",
        )
    if not reject_runs:
        rep.add(
            "T002",
            rel(test_file),
            "expect_failures を使った validation のテスト (reject_*) がありません。"
            "validation が実際に落ちることを確認してください。",
        )
    if not re.search(r"(?m)^mock_provider\b", text):
        rep.add(
            "T003",
            rel(test_file),
            "mock_provider がありません。テストは実際のクラウドリソースを作らず、"
            "認証情報なしで実行できる必要があります。",
        )


def check_readme(
    mod: Path,
    rep: ModuleReport,
    variables: dict[str, Block],
    outputs: dict[str, Block],
    required_version: str | None,
    providers: dict[str, str],
) -> None:
    readme = mod / "README.md"
    if not readme.is_file():
        return
    md = readme.read_text(encoding="utf-8")

    for heading in REQUIRED_README_SECTIONS:
        if not re.search(rf"(?m)^## +{re.escape(heading)}\s*$", md):
            rep.add("D001", rel(readme), f"README に `## {heading}` セクションがありません。")

    # Inputs: トップレベルの表と variables.tf を突き合わせる
    inputs_section = section(md, "Inputs")
    if inputs_section:
        documented = {cell_name(row[0]) for row in first_table(inputs_section) if row}
        for name in sorted(set(variables) - documented):
            rep.add("D002", rel(readme), f"変数 {name} が Inputs の表にありません。")
        for name in sorted(documented - set(variables)):
            rep.add("D002", rel(readme), f"Inputs の表にある {name} は variables.tf に存在しません。")

        # object を含む変数は、ネストした階層ごとに表を作り、内容も型と一致させる
        tables = nested_tables(md)
        for name, block in sorted(variables.items()):
            found: dict[str, dict] = {}
            object_paths(parse_type(type_expression(block)), name, found)
            for path, node in sorted(found.items()):
                if path not in tables:
                    rep.add(
                        "D006",
                        rel(readme),
                        f"object 型 {path} のネストした属性の表 (`### `{path}``) がありません。"
                        "利用者が指定できる属性が README から分からなくなります。",
                    )
                    continue
                documented = tables[path]
                actual = set(node["attrs"])
                for attr in sorted(actual - documented):
                    rep.add(
                        "D007",
                        rel(readme),
                        f"属性 {path}.{attr} が `### `{path}`` の表にありません。",
                    )
                for attr in sorted(documented - actual):
                    rep.add(
                        "D007",
                        rel(readme),
                        f"`### `{path}`` の表にある {attr} は variables.tf の型に存在しません。",
                    )

    # Outputs
    outputs_section = section(md, "Outputs")
    if outputs_section:
        documented = {cell_name(row[0]) for row in first_table(outputs_section) if row}
        for name in sorted(set(outputs) - documented):
            rep.add("D003", rel(readme), f"出力 {name} が Outputs の表にありません。")
        for name in sorted(documented - set(outputs)):
            rep.add("D003", rel(readme), f"Outputs の表にある {name} は outputs.tf に存在しません。")

    # Requirements: versions.tf と一致していること
    req_section = section(md, "Requirements")
    if req_section:
        documented = {cell_name(row[0]): cell_name(row[1]) for row in first_table(req_section) if len(row) >= 2}
        if required_version and documented.get("terraform") != required_version:
            rep.add(
                "D004",
                rel(readme),
                f'Requirements の terraform が versions.tf と一致しません '
                f'(README: "{documented.get("terraform", "なし")}" / versions.tf: "{required_version}")。',
            )
        for name, constraint in sorted(providers.items()):
            if documented.get(name) != constraint:
                rep.add(
                    "D004",
                    rel(readme),
                    f'Requirements の {name} が versions.tf と一致しません '
                    f'(README: "{documented.get(name, "なし")}" / versions.tf: "{constraint}")。',
                )
        for name in sorted(set(documented) - {"terraform"} - set(providers)):
            rep.add("D004", rel(readme), f"Requirements にある {name} は versions.tf に宣言されていません。")

    # 2 つの利用パターンの両方を載せる
    usage = section(md, "使い方")
    if usage:
        if "git::https://github.com/" not in usage or "?ref=" not in usage:
            rep.add(
                "D005",
                rel(readme),
                "使い方に GitHub 参照 (パターン A) の例がありません。"
                '`source = "git::https://.../terraform-modules.git//modules/...?ref=main"` を載せてください。',
            )
        if not re.search(r'source\s*=\s*"\./', usage):
            rep.add(
                "D005",
                rel(readme),
                "使い方にコピー＆ペースト (パターン B) の例がありません。"
                '`source = "./modules/..."` を載せてください。',
            )


def check_root_readme(modules: list[Path], rep: ModuleReport) -> None:
    root_readme = REPO_ROOT / "README.md"
    if not root_readme.is_file():
        return
    md = root_readme.read_text(encoding="utf-8")
    rows = {
        m.group(1): m.group(0)
        for m in re.finditer(r"(?m)^\| \[[a-z0-9-]+\]\((\./modules/[^)]+)\).*$", md)
    }
    for mod in modules:
        link = "./" + str(mod.relative_to(REPO_ROOT))
        row = rows.get(link)
        if row is None:
            rep.add(
                "R001",
                "README.md",
                f"ルート README のモジュール一覧に {mod.relative_to(REPO_ROOT)} がありません。",
            )
        elif "TODO" in row:
            # make new-module が入れたプレースホルダーのまま公開されるのを防ぐ
            rep.add(
                "R002",
                "README.md",
                f"ルート README のモジュール一覧の {mod.relative_to(REPO_ROOT)} の概要が "
                "TODO のままです。何をするモジュールかを 1 行で書いてください。",
            )


def rel(path: Path) -> str:
    try:
        return str(Path(path).resolve().relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


# ------------------------------------------------------------------------------
# 実行
# ------------------------------------------------------------------------------
def discover_modules() -> list[Path]:
    return sorted(p.parent for p in (REPO_ROOT / "modules").glob("*/*/main.tf"))


def lint_module(mod: Path) -> ModuleReport:
    rep = ModuleReport(module=str(mod.relative_to(REPO_ROOT)))
    check_files(mod, rep)

    blocks_by_file = {}
    for path in tf_files(mod):
        try:
            blocks_by_file[path] = parse_blocks(path.read_text(encoding="utf-8"))
        except UnicodeDecodeError:
            rep.add("M001", rel(path), "UTF-8 として読めません。")

    check_no_provider_block(mod, rep, blocks_by_file)
    required_version, providers = check_versions(mod, rep, blocks_by_file)
    check_provider_usage(mod, rep, blocks_by_file, providers)
    variables = check_variables(mod, rep, blocks_by_file)
    outputs = collect_outputs(blocks_by_file)
    check_tests(mod, rep)
    check_readme(mod, rep, variables, outputs, required_version, providers)
    return rep


def main() -> int:
    parser = argparse.ArgumentParser(description="terraform-modules の規約チェッカー")
    parser.add_argument("modules", nargs="*", help="対象モジュール (省略時は全モジュール)")
    parser.add_argument(
        "--format",
        choices=("text", "github"),
        default="github" if os.environ.get("GITHUB_ACTIONS") == "true" else "text",
        help="出力形式。github を指定すると Actions のアノテーションも出力する。",
    )
    args = parser.parse_args()

    modules = [Path(m).resolve() for m in args.modules] if args.modules else discover_modules()
    modules = [m for m in modules if m.is_dir()]
    if not modules:
        print("対象モジュールが見つかりません。", file=sys.stderr)
        return 1

    use_color = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None
    green = "\033[32m" if use_color else ""
    red = "\033[31m" if use_color else ""
    reset = "\033[0m" if use_color else ""

    reports = [lint_module(mod) for mod in modules]
    root_report = ModuleReport(module="(root)")
    if not args.modules:  # 全体を見ているときだけルート README を検査する
        check_root_readme(modules, root_report)

    total = 0
    for rep in reports:
        count = len(rep.issues)
        total += count
        status = f"{green}OK{reset}" if count == 0 else f"{red}{count} 件{reset}"
        print(f"  {rep.module:<56} {status}")
        for issue in rep.issues:
            location = f"{issue.path}:{issue.line}" if issue.line else issue.path
            print(f"      [{issue.code}] {location}: {issue.message}")
            if args.format == "github":
                line = f",line={issue.line}" if issue.line else ""
                message = issue.message.replace("\n", " ")
                print(f"::error file={issue.path}{line},title={issue.code}::{message}")

    for issue in root_report.issues:
        total += 1
        print(f"      [{issue.code}] {issue.path}: {issue.message}")
        if args.format == "github":
            print(f"::error file={issue.path},title={issue.code}::{issue.message}")

    if total:
        print(f"  {red}規約違反が {total} 件あります。{reset}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
