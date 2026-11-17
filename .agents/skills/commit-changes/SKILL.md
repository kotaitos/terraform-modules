---
name: commit-changes
description: 変更を適切な粒度でコミットする
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash
---

## Dynamic Context

### Current Branch & Status
```
!`git branch --show-current && git status --short`
```

### Staged Changes
```
!`git diff --cached --stat 2>/dev/null | head -30`
```

### Recent Commits (for style reference)
```
!`git log --oneline -10`
```

---

# 変更コミットスキル

ステージされた変更、または未ステージの変更を論理的な単位に分割し、適切な粒度でコミットする。

## 実行手順

### 1. 変更内容の確認

```bash
# ステージされた変更を確認
git diff --cached --stat
git diff --cached --name-only

# 未ステージの変更も確認
git status
```

### 2. コミット粒度の判断基準

- **各コミットは実行可能であること**: 各コミット時点でテストが通り、ビルドが成功する状態を維持
- **1コミット1目的**: 1つのコミットは1つの論理的変更のみ
- **関連ファイルをまとめる**: 同じ目的の変更は1コミットに
- **テストは実装と一緒**: 新機能とそのテストは同一コミット
- **フォーマット修正は分離**: コードフォーマットは別コミット

### 3. コミット順序の原則

複数コミットに分割する場合、以下の順序で行う：

1. **依存される側を先に**: 他のコードが参照する関数・クラスの追加を先にコミット
2. **インフラ・設定変更を先に**: 設定ファイルや依存関係の変更を先にコミット
3. **テストは実装と同時**: 機能追加とそのテストは同一コミットで行う

**アンチパターン（避けるべき）:**
- テストだけ先にコミット → テスト対象がないため失敗する
- import文の整理を先にコミット → 参照先がないためエラーになる
- 呼び出し側を先にコミット → 呼び出される関数がないためエラーになる

### 4. コミット実行

コミットメッセージは `<type>(<scope>): <subject>` 形式で書く。
type は `feat` / `fix` / `refactor` / `test` / `docs` / `style` / `chore` / `perf`、
subject の末尾にピリオドは付けない。

```bash
# 必要に応じてステージを解除して再グループ化
git reset HEAD

# カテゴリごとにステージしてコミット
git add <files>
git commit -m "$(cat <<'EOF'
<type>(<scope>): <subject>
EOF
)"
```

## 出力形式

コミット完了後、以下の形式で報告する：

```
完了しました。N個のコミットに分割しました：

1. **<type>(<scope>): <subject>** - <説明>
2. **<type>(<scope>): <subject>** - <説明>
...
```

## 注意事項

- コミット前に`git status`で未コミットの変更がないか確認
- **コミット対象外のファイルは破棄しない**: ユーザーが明示的に指定したファイルのみコミットし、それ以外の変更は未ステージのまま残す
