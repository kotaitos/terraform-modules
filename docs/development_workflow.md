# 開発ワークフロー

このドキュメントでは、本リポジトリにおける日々の開発手順を定義します。Issueの作成からプルリクエストのマージまで、一貫したプロセスを定めることで、スムーズな共同作業を目指します。

リリース作業については、`release_workflow.md`を参照してください。

## 1. 開発プロセスの全体像

開発は以下のステップで進められます。

1.  **ISSUE作成**: すべての作業はGitHubのISSUEから開始します。
2.  **ブランチ作成**: `develop`ブランチから作業用の`feature`ブランチを作成します。
3.  **開発とコミット**: コードの変更、テスト、コミットを繰り返します。
4.  **プルリクエスト (PR) 作成**: `develop`ブランチへのマージを依頼します。
5.  **レビューとマージ**: チームによるレビューを経て、承認後にマージされます。

## 2. 開発環境のセットアップ

必要なのは Terraform CLI (>= 1.10) と Python 3、それに
[mise](https://mise.jdx.dev/) です。tflint / trivy / pre-commit は
`.tool-versions` で固定したバージョンを `make tools` が入れます。

```bash
make tools                                    # .tool-versions のツールを入れる（最初に一度）
make help                                     # 利用できるタスクの一覧
make hooks                                    # git フック（fmt・規約・コミットメッセージ）を有効にする
make preflight                                # fmt + policy + validate + test + lint
make check                                    # preflight + security（CI と同じ内容）
make fmt-fix                                  # フォーマットの自動修正
make MODULE=modules/google/external-lb test   # 単一モジュールのテスト
make new-module NAME=google/pubsub-topic DESC="概要"   # モジュールの雛形を作る
make next-version REF=origin/develop          # 次のリリースバージョンを確認する
make clean                                    # .terraform / キャッシュ / .tools を削除
```

`make hooks` を一度実行しておくと、コミット時にフォーマットと規約チェック、
コミットメッセージの形式チェックが自動で走ります（緊急時は `git commit --no-verify`）。
実行するものは [.pre-commit-config.yaml](../.pre-commit-config.yaml) にあります。

自動化されている仕組みの一覧は [maintenance.md](./maintenance.md) にまとめています。

`terraform test` は `mock_provider` を使うため、**実際のクラウドリソースは作成されず、
認証情報も不要**です。テストの書き方は
[module_contribution_guidelines.md](./module_contribution_guidelines.md) を参照してください。

`.devcontainer/` に Terraform / gcloud / Docker を含む開発コンテナ定義があります。
VS Code の "Reopen in Container" で同じ環境を再現できます。

## 3. ブランチ戦略

本リポジトリでは、GitFlowに基づいた以下のブランチを使用します。

-   **`main`**: 常に安定し、リリース可能な状態を保つ本番ブランチ。直接のコミットは禁止です。
-   **`develop`**: 次のリリースに向けた開発の統合ブランチ。`feature`ブランチのマージ先です。
-   **`feature/*`**: 新機能開発やバグ修正を行う作業ブランチ。`develop`から分岐します。
-   **`release/vX.Y.Z`**: リリース対象を固定するブランチ。**毎月 1 日に `develop` から自動で
    作られ**、`main` へマージされると自動で削除されます。手で作る必要はありません
    （[release_workflow.md](./release_workflow.md)）。
-   **`hotfix/*`**: `main` から分岐する緊急修正用のブランチ。

## 4. 具体的な開発フロー

### ステップ1: ISSUE作成

-   **目的**: 新機能の追加、バグ修正、改善、ドキュメント更新など、すべての作業はISSUEとして登録します。
-   **内容**: ISSUEには、作業の目的、具体的な内容、期待される結果を明確に記述してください。
-   **関連付け**: 作業を開始する前に、必ず関連するISSUEを作成し、担当者をアサインしてください。

### ステップ2: ブランチ作成

-   `develop`ブランチを最新の状態にし、作業内容に応じた名前で`feature`ブランチを作成します。
-   ブランチ名は `feature/ISSUE番号-作業内容` の形式を推奨します。

```bash
# developブランチに移動し、最新化
git checkout develop
git pull origin develop

# featureブランチを作成
git checkout -b feature/123-new-module
```

### ステップ3: 開発とコミット

-   ブランチでコードの変更、テスト、コミットを行います。
-   **コミット前に `make preflight` を実行してください。** CI でも同じチェックが走ります
    （CI はこれに加えて trivy によるセキュリティスキャンと、最小サポートバージョン /
    最新バージョンの 2 つの Terraform での検証を行います。ローカルで CI と同じ内容を
    実行するには `make check`）。
-   新しいモジュールを追加する場合は
    `make new-module NAME=<provider>/<module-name> DESC="<1 行の概要>"` で雛形を作れます。
    ルート README のモジュール一覧にも行が追加され、生成直後の状態で `make preflight` が通ります。
-   コミットメッセージは `<type>(<scope>): <subject>` 形式で記述してください
    （詳細は [docs/commit_message.md](commit_message.md)）。
    **形式はリリースのバージョン判定に使われます**（`feat` なら MINOR、`feat(scope)!:` なら
    MAJOR）。破壊的変更を含む場合は type の後ろに `!` を付けてください。
-   作業中は、定期的に`develop`ブランチの変更を取り込み、コンフリクトを解消することを推奨します。

```bash
git fetch origin
git rebase origin/develop
```

### ステップ4: プルリクエスト (PR) の作成

-   作業が完了したら、`develop`ブランチへのプルリクエストを作成します。
-   PRのテンプレート (`.github/PULL_REQUEST_TEMPLATE.md`) に従い、変更内容やテスト結果を記述してください。
-   **PR のタイトルはコミットメッセージと同じ `<type>(<scope>): <subject>` 形式にしてください。**
    `develop` へのマージは squash なので、PR タイトルがそのままコミットの subject になり、
    リリースのバージョン判定とリリースノートに使われます。形式は CI
    （[triage.yml](../.github/workflows/triage.yml)）がチェックします。
-   **ラベルとアサインは自動で付きます。** タイトルの type と変更したファイルからラベルを付与し、
    未アサインなら作成者をアサインします。足りない場合は手で追加してください（自動で付け直したり
    外したりはしません）。ラベルの定義は [.github/labels.yml](../.github/labels.yml) です。

```bash
# GitHub CLIを利用する場合
gh pr create --base develop --head feature/123-new-module \
  --title "feat(modules/google/pubsub-topic): Pub/Sub トピックモジュールを追加" \
  --body-file /path/to/pr_description.md
```

### ステップ5: レビューとマージ

-   チームメンバーによるレビューを受けます。指摘事項があれば修正し、再度プッシュしてください。
-   PRは、少なくとも1名以上のレビュアーによる承認が必要です。
-   承認後、`develop`ブランチにマージします。マージは、GitHub上の **"Squash and merge"** を使用し、コミット履歴をクリーンに保ちます。
-   マージ後、作業ブランチは削除します。
-   リリースは月 1 回、自動で行われます（毎月 1 日にリリース PR が作られ、4 日にマージされます）。
    `develop` にマージしたあとに個別の作業は要りません
    （[release_workflow.md](./release_workflow.md)）。

```bash
# ローカルのブランチも削除
git branch -d feature/123-new-module

# リモートのブランチも削除
git push origin --delete feature/123-new-module
```
