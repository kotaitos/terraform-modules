# コミットメッセージ規約

## 形式

```
<type>(<scope>): <subject>
```

## Type（必須）

| type | 用途 |
|------|------|
| `feat` | 新機能追加 |
| `fix` | バグ修正 |
| `refactor` | 動作を変えないコード改善 |
| `test` | テストコードの追加・修正 |
| `docs` | ドキュメントのみの変更 |
| `style` | フォーマット、空白、セミコロン等 |
| `chore` | ビルド、依存関係、設定等 |
| `perf` | パフォーマンス改善 |

## Scope（必須）

変更対象のモジュール/パッケージ名を指定する。スラッシュ（`/`）でサブスコープを定義可能：

- `docs` - ドキュメント関連
- `modules` - Terraformモジュール
  - `google` - Google Cloud
    - `[モジュール名]`
- `ci` - CI/CDワークフロー（.github/workflows配下）
- `agents` - AI エージェントの設定（AGENTS.md / .agents/ / .claude/ / .gemini/ / GEMINI.md）

サブスコープの例：`modules/google/artifact-registry`

## 破壊的変更

利用者の対応が必要な変更（変数の削除・リネーム・必須化、リソースの再作成など）は、
type の後ろに `!` を付ける。

```
feat(modules/google/postgres-psc)!: database_flags の型を map(string) に変更
```

`!` の付いたコミットがあると、リリースのバージョンが MAJOR で上がる
（[docs/release_workflow.md](release_workflow.md)）。
本文に `BREAKING CHANGE: <内容>` を書いても同じ扱いになる。

## Subject

- 日本語で簡潔に記述
- 末尾にピリオドは付けない
- 「何をしたか」を端的に

## PR タイトル

`develop` へのマージは squash なので、**PR タイトルがそのままコミットの subject になる**。
PR タイトルも同じ形式で書く（CI がチェックする）。

## 禁止事項

- Co-Authored-Byの署名は追加しない（明示的に要求された場合のみ）
- 機密情報（.env、credentials等）をコミットしない
- 不要なファイル（memo.md、.DS_Store、__pycache__等）をコミットしない
