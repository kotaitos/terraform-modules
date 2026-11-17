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
!`git log main..HEAD --oneline 2>/dev/null || git log origin/main..HEAD --oneline 2>/dev/null || echo "ベースブランチとの差分を取得できません"`
```

### Changed Files
```
!`git diff main..HEAD --stat 2>/dev/null | tail -20 || git diff origin/main..HEAD --stat 2>/dev/null | tail -20`
```

---

# PR作成スキル

コミット済みの変更から `main` への Pull Request を作成する。
`main` への直接 push と force push はリポジトリルールで禁止されているため、
変更は必ず PR を経由する。

## 前提条件

- 変更がコミット済みであること
- `make preflight` が通っていること
- リモートにプッシュ済み、またはプッシュ可能な状態であること

> **注意**: 未コミットの変更がある場合は、先に [commit-changes](../commit-changes/SKILL.md) スキルを使用してコミットしてください。

## 実行手順

### 1. 状態確認

```bash
git status -sb                        # 未コミット・未プッシュの確認
git log origin/main..HEAD --oneline   # PR に含まれるコミット
```

### 2. ブランチ確認・作成

現在のブランチが `main` の場合、新しいブランチを作成する：

```bash
git checkout -b <type>/<簡潔な説明>
```

### 3. リモートへプッシュ（未プッシュの場合）

```bash
git push -u origin HEAD
```

### 4. PR作成

本文は一時ファイルに書き出し、`--body-file` で渡す。
`--body` に直接書くとシェルの解釈で崩れやすい。

```bash
# /tmp/pr-body.md に本文を書いてから
gh pr create \
  --base main \
  --title "<type>(<scope>): <subject>" \
  --body-file /tmp/pr-body.md
```

### 5. タイトルの形式

```
<type>(<scope>): <subject>
```

type は `feat` / `fix` / `refactor` / `test` / `docs` / `style` / `chore` / `perf`。
破壊的変更を含む場合は type の後ろに `!` を付ける。

```
feat(modules/google/postgres-psc)!: database_flags の型を map(string) に変更
```

### 6. 本文の書き方

- **変更内容**: 何を、なぜ変更したか
- **影響範囲**: 利用者側の対応が必要かどうか
- **テスト**: 実行したチェック（`make preflight` / `make check`）

## 出力形式

PR作成後、以下の形式で報告：

```
PRを作成しました：
<PR URL>

タイトル: <type>(<scope>): <subject>
ベースブランチ: main
```

## 注意事項

- `main` ブランチから直接PRを作成しない（新しいブランチを作成する）
- コミットがない状態でPRを作成しない
- 未プッシュのコミットがある場合は先にプッシュする
- ドラフトPRにする場合は `--draft` オプションを追加
