---
name: create-pr
description: ghコマンドでPull Requestを作成する。
---

## Dynamic Context

### Current Branch & Remote Status
```
!`git branch --show-current && git status -sb`
```

### Commits to be included in PR
```
!`git log develop..HEAD --oneline 2>/dev/null || git log origin/develop..HEAD --oneline 2>/dev/null || echo "ベースブランチとの差分を取得できません"`
```

### Changed Files
```
!`git diff develop..HEAD --stat 2>/dev/null | tail -20 || git diff origin/develop..HEAD --stat 2>/dev/null | tail -20`
```

---

# PR作成スキル

コミット済みの変更から `develop` への Pull Request を作成する。

## 前提条件

- 変更がコミット済みであること
- `make preflight` が通っていること
- リモートにプッシュ済み、またはプッシュ可能な状態であること

> **注意**: 未コミットの変更がある場合は、先に [commit-changes](../commit-changes/SKILL.md) スキルを使用してコミットしてください。

## 実行手順

### 1. 状態確認

```bash
git status -sb                      # 未コミット・未プッシュの確認
git log origin/develop..HEAD --oneline   # PR に含まれるコミット
gh issue list --state open --limit 10    # 関連 issue の確認
```

### 2. ブランチ確認・作成

現在のブランチが `develop` または `main` の場合、新しいブランチを作成する：

```bash
git checkout -b feature/ISSUE-<番号>-<簡潔な説明>
```

### 3. リモートへプッシュ（未プッシュの場合）

```bash
git push -u origin HEAD
```

### 4. PR作成

本文は [.github/PULL_REQUEST_TEMPLATE.md](../../../.github/PULL_REQUEST_TEMPLATE.md) の
見出しに沿って書く（**ここに写しを置かない**）。テンプレートを埋めた本文を一時ファイルに
書き出し、`--body-file` で渡す。`--body` に直接書くとシェルの解釈で崩れやすい。

```bash
# /tmp/pr-body.md にテンプレートを埋めた本文を書いてから
gh pr create \
  --base develop \
  --title "<type>(<scope>): <subject>" \
  --body-file /tmp/pr-body.md
```

**ラベルとアサインは自動で付く**（[triage.yml](../../../.github/workflows/triage.yml) が
タイトルの type と変更ファイルから判定する）。足りない場合だけ `gh pr edit --add-label` で足す。

### 5. タイトルの形式

[commit_message.md](../../../docs/commit_message.md) の規約に従う。**scope は必須**。

```
<type>(<scope>): <subject>
```

`develop` へのマージは squash なので、**PR タイトルがそのままコミットの subject になり、
リリースのバージョン判定に使われる**（`feat` → MINOR、それ以外 → PATCH）。
破壊的変更を含む場合は type の後ろに `!` を付ける（→ MAJOR）。

```
feat(modules/google/postgres-psc)!: database_flags の型を map(string) に変更
```

形式はローカル（commitlint / `.commitlintrc.json`）と CI（PR タイトル）の両方でチェックされる。

### 6. 本文の書き方

- **概要**: 関連する issue を `Closes #123` で紐づける。
  **`develop` にマージしても Issue は閉じない。** GitHub が自動クローズするのは
  デフォルトブランチ（`main`）にマージされたときだけなので、リリースで `main` に
  入った時点で閉じる。それより早く閉じたい場合は手で閉じる
- **変更内容**: 何を、なぜ変更したか
- **影響範囲**: 利用者側の対応が必要かどうか
- **テスト**: 実行したチェック（`make preflight` / `make check`）

## 出力形式

PR作成後、以下の形式で報告：

```
PRを作成しました：
<PR URL>

タイトル: <type>(<scope>): <subject>
ベースブランチ: develop
```

## 注意事項

- `develop` や `main` ブランチから直接PRを作成しない（新しいブランチを作成する）
- **`main` への PR は作らない。** `main` へのリリース PR は
  [release-pr.yml](../../../.github/workflows/release-pr.yml) が自動で作る
  （[docs/release_workflow.md](../../../docs/release_workflow.md)）。
  例外は `hotfix` のみ。
- コミットがない状態でPRを作成しない
- 未プッシュのコミットがある場合は先にプッシュする
- ドラフトPRにする場合は `--draft` オプションを追加
