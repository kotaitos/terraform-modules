---
name: create-issue
description: ghコマンドでIssueを作成する。
---

# Issue作成スキル

GitHubにIssueを作成する。ラベルとアサインは
[triage.yml](../../../.github/workflows/triage.yml) が自動で付けるので、
**手で指定する必要はない**（意図があるときだけ上書きする）。

## 実行手順

### 1. Issue の種類を決める

| 種類 | 使うもの |
| :--- | :--- |
| バグ報告 | [bug_report.yml](../../../.github/ISSUE_TEMPLATE/bug_report.yml) の項目（対象モジュール / 参照バージョン / 何が起きたか / 期待した挙動 / 再現手順 / バージョン）を埋める。ラベル `bug` が付く |
| 新しいモジュールの追加 | [new_module.yml](../../../.github/ISSUE_TEMPLATE/new_module.yml) の項目（モジュール名 / なぜ必要か / 作成するリソース / 想定インターフェース）を埋める。ラベル `new-module` が付く |
| その他（改善・調査・ドキュメント） | 下記の汎用フォーマットで作る。ラベルはタイトルから推測されるか `needs-triage` が付く |

ブラウザでテンプレートを使う場合は `gh issue create --web` を実行する。

### 2. Issue を作成する

```bash
gh issue create \
  --title "<簡潔で具体的なタイトル>" \
  --body "$(cat <<'EOF'
## 概要

<!-- 何が問題か / 何をしたいかを 1-2 文で -->

## 詳細

<!-- 背景、再現手順、エラーログ、対象モジュールのパスなど -->

## 期待する結果

<!-- どうなっていれば完了か -->

## 備考

<!-- 関連 Issue / PR、参考リンク -->
EOF
)"
```

- ラベルを明示したい場合だけ `--label` を足す。使えるラベルは
  [.github/labels.yml](../../../.github/labels.yml) が唯一の情報源
  （`bug` / `enhancement` / `documentation` / `new-module` / `breaking-change` /
  `ci` / `dependencies` / `template` / `devcontainer` など）。
- 担当者を自分以外にする場合だけ `--assignee <user>` を足す
  （省略すると作成者がアサインされる）。

## 出力形式

Issue作成後、以下の形式で報告：

```
Issueを作成しました：
<Issue URL>

タイトル: <タイトル>
```

## 注意事項

- モジュールの追加・変更に関する Issue では、対象モジュールのパス（`modules/google/xxx`）を必ず書く。
- 破壊的変更になりそうな要望は、その旨を本文に書く（リリースが MAJOR になる）。
- 作業の進め方は [docs/development_workflow.md](../../../docs/development_workflow.md) に従う。
