---
name: sync-docs
description: TerraformモジュールのREADME.mdをソースファイル（variables.tf / outputs.tf / versions.tf）と同期する。
---

## Dynamic Context

### Available Modules
```
!`find modules -mindepth 2 -name "variables.tf" -exec dirname {} \; 2>/dev/null | sort`
```

### Recently Modified Modules (source files newer than README)
```
!`for dir in $(find modules -mindepth 2 -name "variables.tf" -exec dirname {} \; 2>/dev/null); do if [ -f "$dir/README.md" ]; then src_time=$(stat -f %m "$dir/variables.tf" 2>/dev/null || stat -c %Y "$dir/variables.tf" 2>/dev/null); readme_time=$(stat -f %m "$dir/README.md" 2>/dev/null || stat -c %Y "$dir/README.md" 2>/dev/null); if [ "$src_time" -gt "$readme_time" ] 2>/dev/null; then echo "$dir (要更新)"; fi; else echo "$dir (README未作成)"; fi; done`
```

### Git Status (uncommitted changes in modules/)
```
!`git status --porcelain modules/ 2>/dev/null | head -20`
```

---

# ドキュメント同期スキル

モジュールの `README.md` を `variables.tf` / `outputs.tf` / `versions.tf` と一致させる。

> [!IMPORTANT]
> **README の書式そのものはこのファイルで定義しない。** 必須セクション、ネストした表の
> パス表記、2 つの利用パターン、Notes に書くことは
> [docs/module_contribution_guidelines.md](../../../docs/module_contribution_guidelines.md)
> の「7. ドキュメント」が唯一の情報源で、`make policy` が検査する。
> 新規作成の雛形は [templates/module/google/README.md](../../../templates/module/google/README.md)
> を使う（`make new-module` が展開する）。ここに書き写すと必ず食い違う。

## 何を生成し、何を残すか

| セクション | 扱い |
| :--- | :--- |
| タイトルと概要 / なぜこのモジュールを使うのか / 構成リソース / 使い方 / Notes | **手書き。絶対に上書きしない** |
| Inputs | `variables.tf` から**再生成** |
| Outputs | `outputs.tf` から**再生成** |
| Requirements | `versions.tf` から**再生成** |

`Requirements` は**推測してはいけない**。`required_providers` に宣言されているプロバイダーだけを、
宣言されているバージョン制約の文字列のまま転記する（`make policy` D004 が突き合わせる）。

## 手順

1. `variables.tf` / `outputs.tf` / `versions.tf` を読む。
2. 上の表に従って Inputs / Outputs / Requirements だけを差し替える。
3. **`make policy` を実行する。** 表と実装の食い違い（D002 / D003 / D004 / D006 / D007）は
   ここで検出される。
4. `make policy` が指摘した箇所を直す。手書きセクションの修正が必要になることもある
   （変数を消したのに「使い方」の例に残っている、など）。

## 表の書き方

`make policy` は表の**項目名**が実装と一致していることを検査するが、Type / Default / Required の
列の書き方までは見ない。次に揃える。

| Terraform の型 | Type 列 | Default 列 | Required 列 |
| :--- | :--- | :--- | :--- |
| `string` / `number` / `bool` | その型名 | `default` があればその値、無ければ `n/a` | `default` が無ければ `yes`、あれば `no` |
| `list(string)` / `map(string)` など | その型名 | 同上 | 同上 |
| `object({...})` | `object` | 同上 | 同上 |
| `list(object({...}))` / `map(object({...}))` | `list(object)` / `map(object)` | 同上 | 同上 |
| `optional(T)` / `optional(T, d)` | `T` の表記 | `d`（省略時は `null`） | 常に `no` |

- **`object` になっている階層はすべて `### <パス>` の表にする**（`make policy` D006 / D007）。
  属性が同じ複数のパスは、見出しに両方を書いて 1 つの表にまとめてよい。
- そのモジュールで使っていない属性は説明に**「このモジュールでは未使用」**と明記する。
  利用者が「渡さないと動かないのか」を迷わないようにするため。
- `validation` で表現されている排他・依存の制約は、該当する表の直前に 1 文で書く
  （例: 「`condition` と `most_recent_versions` は**どちらか一方のみ**を指定します。」）。

## 報告の形式

```
README.md を更新しました：
<module_path>/README.md

更新内容:
- Inputs: <変数数> 個の変数
- Outputs: <出力数> 個の出力
- Requirements: terraform <version>, <provider> <version>
- make policy: OK
```

## 一括更新

上の Dynamic Context の「Recently Modified Modules」に出たモジュールに対して順番に適用する。
最後に `make policy`（引数なし＝全モジュール）を 1 回実行して確認する。

## 関連スキル

- 更新後は [commit-changes](../commit-changes/SKILL.md) でコミット
- PR 作成は [create-pr](../create-pr/SKILL.md)
