# メンテナンスガイド

このドキュメントは、`terraform-modules` を長く安全に運用するための「自動化されている仕組み」と、
それが失敗したときの対処をまとめたものです。日々の開発手順は
[development_workflow.md](./development_workflow.md)、リリース手順は
[release_workflow.md](./release_workflow.md) を参照してください。

## 1. 自動化されていること

| いつ | 何が動くか | 失敗したときにやること |
| :--- | :--- | :--- |
| コミット時（`make hooks` を実行済みの場合） | `terraform fmt` と規約チェック、コミットメッセージの形式チェック | `make fmt-fix` で整形する／メッセージを規約に合わせる |
| ローカルで `make preflight` | fmt + 規約 + validate + test + tflint | 表示されたコマンドで修正する |
| PR / `main`・`develop` への push | CI（規約・tflint・validate & test・trivy） | ローカルで `make check` を実行すると同じ内容を再現できる |
| モジュール追加時 | `make new-module` が雛形・ルート README の一覧・テストまで用意する | 生成後に `make preflight` を実行して実装を進める |
| PR / Issue の作成時 | ラベルの付与、未アサインなら作成者のアサイン、PR タイトルの形式チェック | タイトルを `<type>(<scope>): <subject>` 形式に直す／ラベルは手で足す |
| 毎月 1 日 09:00 JST | `release/vX.Y.Z` の作成と、`main` へのリリース PR の作成 | Actions の実行サマリーに理由が出る（差分が無ければ作られない） |
| 毎月 4 日 09:00 JST | リリース PR の自動マージ（差分が無ければ何もしない） | 見送られた場合は PR にコメントが付く。原因を解消して PR をマージすればリリースされる |
| リリース PR のマージ（`main` への push） | バージョンタグの作成 → 全チェック → GitHub Release の作成 | チェックが落ちると `maintenance` ラベルの Issue が作られる。タグは打ち直さず、次のパッチバージョンをリリースする |
| `.github/labels.yml` の変更 | ラベルの同期（作成・色や説明の更新） | 実行ログを確認する（削除はしない） |
| 毎週月曜 07:00 JST | 最新プロバイダーでの検証と、バージョン制約の棚卸し | 自動で Issue が作られる（直ると自動で閉じる）。下記「7. 週次メンテナンス」参照 |
| 毎週月曜 07:00 JST | Dependabot が GitHub Actions とプロバイダー制約の更新 PR を作る | PR の CI が通ることを確認してマージする |

CI で使うツールのバージョンは [`.tool-versions`](../.tool-versions) が唯一の情報源です。
ローカルの `make lint` / `make security` と CI は同じバージョンを使います。

## 2. リリースの自動化

リリースは「`develop` に変更を入れる → 自動で作られるリリース PR をマージする」だけです。
手順の詳細は [release_workflow.md](./release_workflow.md) にありますが、仕組みは 3 つの
ワークフローに分かれています。

| ワークフロー | トリガー | 役割 |
| :--- | :--- | :--- |
| [release-pr.yml](../.github/workflows/release-pr.yml) の `prepare` ジョブ | 毎月 1 日 09:00 JST / 手動 | バージョンを算出し、`release/vX.Y.Z` を切って `main` へのリリース PR を作る |
| [release-pr.yml](../.github/workflows/release-pr.yml) の `release` ジョブ | 毎月 4 日 09:00 JST / 手動 | リリース PR をマージしてリリースを開始し、リリースブランチを削除する |
| [release-tag.yml](../.github/workflows/release-tag.yml) | `main` への push | バージョンタグを作成して release.yml を起動する。`hotfix` なら `develop` への追従 PR も作る |
| [release.yml](../.github/workflows/release.yml) | タグ | `make check` を実行し、通ったら GitHub Release を作成する |

- **バージョンはコミットメッセージから決まります**（`feat(scope)!:` → MAJOR、`feat` → MINOR、
  それ以外 → PATCH）。判定は [scripts/next-version.py](../scripts/next-version.py) にあり、
  `make next-version REF=origin/develop` でローカルでも確認できます。
- **リリースは月次で自動的に行われます**（1 日に `release/vX.Y.Z` と PR を作成、4 日にマージ）。
  CI が緑で、コンフリクトが無く、破壊的変更（MAJOR）を含まないときだけマージし、それ以外は理由を
  PR にコメントして見送ります（ワークフローは失敗させません）。止めたいときは `release-hold`
  ラベル、すぐ出したいときは PR を手でマージします。
  **リリース PR は `develop` への push では作られません**（リリースの周期に合わせて作られます）。
- **リリース対象はリリースブランチに固定されます。** head を `develop` にすると確認中に
  `develop` へのマージが PR に入ってしまうためです。リリース直前の修正はリリースブランチに
  直接入れ（`main` → `develop` の追従 PR が自動で作られます）、機能追加は次回に回します。
- **リリースノートは PR のタイトルとラベルから自動生成されます**
  （カテゴリ設定は [.github/release.yml](../.github/release.yml)）。
  リリース PR 本文の「破壊的変更の移行手順」欄に書いた内容は、リリースノートの先頭に転記されます。
- **GITHUB_TOKEN で行った push / PR 作成 / マージでは、その push イベントや `pull_request`
  イベントのワークフローが起動しない**という GitHub の仕様があります。この制約への対応は 3 か所です。
  - リリース PR のマージ（月次）: `release-pr.yml` の `release` ジョブが `release-tag.yml` を
    `workflow_dispatch` で起動します（マージしても `main` への push イベントは発火しないため）。
  - タグ: `release-tag.yml` が `release.yml` を `workflow_dispatch` で起動します
    （`workflow_dispatch` と `repository_dispatch` はこの制限の例外）。
  - リリース PR の CI: PR に対する CI は走りませんが、`develop` への push で同じコミットに対して
    CI が実行されるため、結果は PR 上のチェックとして表示されます。
- 「`main` にマージ済みなのにタグが無い」状態（自動リリースの中断など）になったときは、
  Actions から `Release Tag` を `main` に対して手動で実行すれば回復します。既存のタグは
  打ち直さないので、何度実行しても安全です。
- 動かすには GitHub 側の設定（Actions の書き込み権限と PR 作成の許可）が必要です。
  [release_workflow.md の「5. リポジトリ設定の前提」](./release_workflow.md#5-リポジトリ設定の前提)を参照してください。

## 3. ラベルと Triage

リリースノートのカテゴリ分けはラベルで決まるため、ラベルを人の記憶に頼らない形にしています。

- **ラベルの定義**: [.github/labels.yml](../.github/labels.yml) が唯一の情報源です。
  変更を push すると [labels.yml](../.github/workflows/labels.yml) が同期します
  （既存ラベルの削除はしません。PR や Issue から外れてしまうためです）。
- **PR のラベル**: [triage.yml](../.github/workflows/triage.yml) が、タイトルの type
  （`feat` → `enhancement`、`fix` → `bug`、`!` → `breaking-change`）と scope
  （`ci` / `scripts` / `cursor` → `ci`、`templates` → `template`、`devcontainer` → `devcontainer`）、
  変更ファイル（新規 `modules/*/*/main.tf` → `new-module` など）から付与します。
  開発基盤の scope は type より優先します（`fix(ci)` はモジュールのバグ修正ではないため
  `bug` ではなく `ci` になります）。
  付与は **PR の作成時だけ**です。人が外したラベルを付け直さないようにしています。
- **PR タイトルの形式**:
  [amannn/action-semantic-pull-request](https://github.com/amannn/action-semantic-pull-request)
  でコミットメッセージと同じ規約をチェックします（`develop` へは squash マージなので、
  PR タイトルがそのままコミットの subject になり、バージョン判定に使われます）。
  失敗すると PR にコメントが付きます。自動生成されるリリース PR は `release` ラベルで除外します。
- **アサイン**: PR と Issue が未アサインなら作成者をアサインします。
- **Issue のラベル**: Issue テンプレートを使えばラベルが付きます。空の Issue はタイトルから
  推測し、分からなければ `needs-triage` を付けます。

## 4. ローカル環境のセットアップ

必要なのは Terraform CLI (>= 1.10) と Python 3、それに
[mise](https://mise.jdx.dev/) です。tflint / trivy / pre-commit は `.tool-versions` で
固定したバージョンを mise が入れます（システムに同じツールが入っていればそちらを使います）。

```bash
mise --version   # 無ければ: curl https://mise.run | sh  /  brew install mise
make tools       # .tool-versions のツールを入れる
make hooks       # git フック（pre-commit / commit-msg）を有効にする
make help        # 使えるタスクの一覧
```

`make hooks` は [pre-commit](https://pre-commit.com/) のフックを入れます。コミット時に
`terraform fmt`・規約チェック・コミットメッセージの形式チェックが自動で走ります
（実行するものは [.pre-commit-config.yaml](../.pre-commit-config.yaml)、緊急時は
`git commit --no-verify` で回避できます）。

> [!NOTE]
> 以前は `core.hooksPath` を `.githooks` に向けていました。既にセットアップ済みの環境では
> **`make hooks` をもう一度実行してください**（古い設定は `make hooks` が自動で外します）。
> 外れていないと pre-commit が入れたフックが無視され、チェックが黙って走らなくなります。

## 5. 週次メンテナンス（[maintenance.yml](../.github/workflows/maintenance.yml)）

モジュールはバージョン制約に幅（`>= 6.0.0, < 8.0.0`）を持たせているため、**自分たちが何も
変更しなくても、プロバイダーの新しいリリースで壊れることがあります**。これを利用者より先に
見つけるために、週次で次の 2 つを確認しています。

1. **最新プロバイダーでの検証**: プロバイダーのキャッシュを使わずに、制約の範囲内で最新の
   プロバイダーを取得して `validate` / `test` / `tflint` を実行します。
   失敗した場合は、モジュールを修正するか、`versions.tf` の上限を下げます。
2. **バージョン制約の棚卸し**: 制約の上限を超える安定版が出ていないかを確認します
   （`make providers` でローカルでも実行できます）。出ている場合は、破壊的変更を確認したうえで
   `versions.tf` と各モジュールの README の Requirements を更新します。
   README と `versions.tf` の食い違いは `make policy` が検出します。

どちらかが失敗すると `maintenance` ラベルの付いた Issue が 1 つ作られ、以降の実行では
その Issue にコメントが追加されます。直ると自動でコメントを付けて閉じます。

## 6. 規約チェック（`make policy`）が見ているもの

[docs/coding_standards.md](./coding_standards.md) と
[docs/module_contribution_guidelines.md](./module_contribution_guidelines.md) のうち、
機械的に判定できるルールを [scripts/lint-modules.py](../scripts/lint-modules.py) が検査します。

**一般的な Terraform の作法は tflint に任せているので、ここには含まれません**（下の表を参照）。
同じ規約を二か所で検査すると必ず片方が腐るため、重複させていません。

| ID | 内容 |
| :--- | :--- |
| M001 | 必須ファイル（`versions.tf` / `README.md` / `main.tftest.hcl`）が揃っている |
| M002 | モジュール内に `provider` ブロックを書いていない |
| M003 | `required_version` がリポジトリ全体で `>= 1.10` に揃っている |
| M004 | プロバイダーのバージョン制約に下限と上限の両方がある |
| M005 | 使っているプロバイダーを `required_providers` で宣言している |
| V003 | 変数の型に `any` を使っていない |
| T001 / T002 / T003 | 正常系のテストが 2 つ以上、`expect_failures` のテストがある、`mock_provider` を使っている |
| D001 | README に必須セクション（なぜこのモジュールを使うのか／構成リソース／使い方／Inputs／Outputs／Requirements／Notes）がある |
| D002 / D003 | README の Inputs / Outputs の表が `variables.tf` / `outputs.tf` と一致している |
| D004 | README の Requirements が `versions.tf` と一致している |
| D005 | README の使い方に 2 つの利用パターン（GitHub 参照 / コピー＆ペースト）がある |
| D006 | `object` になっている**すべての階層**（`neg_backends[*].log_config` など）に、ネストした属性の表（`### <パス>` の見出しと表）がある |
| D007 | ネストした属性の表の項目が `variables.tf` の型と一致している |
| R001 / R002 | ルート README のモジュール一覧に載っていて、概要が雛形の TODO のままになっていない |

チェッカー自体のテストは `make test-scripts` で実行できます（規約違反を混ぜたモジュールを
一時ディレクトリに作り、各チェックが実際に発火するかを確認します）。ルールを追加・変更した
ときは、このテストにもケースを足してください。

## 7. tflint / trivy

- **tflint** ([.tflint.hcl](../.tflint.hcl)): 公式 terraform ルールセットの全ルールと、
  プロバイダー向けルールセット（現在は google）を有効にしています。未使用の宣言、命名規則、
  非推奨の構文などを検出します。**一般的な Terraform の作法はここが担当**で、
  `make policy` とは重複させていません。

  | tflint のルール | 見ているもの |
  | :--- | :--- |
  | `terraform_standard_module_structure` | `main.tf` / `variables.tf` / `outputs.tf` があり、宣言が正しいファイルにある |
  | `terraform_documented_variables` / `terraform_documented_outputs` | 変数と出力に `description` がある |
  | `terraform_typed_variables` | 変数に `type` がある |
  | `terraform_required_version` | `required_version` がある（値の揃えは M003） |
  | `terraform_required_providers` | プロバイダーに `source` / `version` がある（上下限は M004） |
  | `terraform_unused_required_providers` | 宣言したのに使っていないプロバイダー（逆は M005） |
- **trivy** ([trivy.yaml](../trivy.yaml)): Terraform の misconfiguration スキャンです。
  HIGH 以上を失敗扱いにします。対象はこのリポジトリが配布するもの（`modules/` と
  `templates/`）だけで、`.devcontainer/` は対象外です。

検出結果を除外する場合は [.trivyignore.yaml](../.trivyignore.yaml) に
**なぜ安全なのかを `statement` に書いて**追加します。理由を書けない場合はコードを直します。

> [!NOTE]
> 現在の除外は `GCP-0015`（Cloud SQL の TLS 強制）1 件で、これは誤検出です。
> `postgres-psc` は `settings.ssl_mode` の既定を `ENCRYPTED_ONLY` にして TLS を強制して
> いますが、Trivy は `optional(string, "ENCRYPTED_ONLY")` のような **object 型の中に書かれた
> 既定値を解決できず**、未設定として扱います。既定が効いていることは
> `terraform test`（`ssl_mode_null_falls_back_to_default`）で担保しています。

## 8. モジュールが増えても破綻しないための設計

モジュールは今後も増える前提なので、**モジュールを増やすときに触るファイルを増やさない**
ことを方針にしています。

- モジュールの一覧はどこにもハードコードしません。Makefile・規約チェッカー・
  プロバイダー確認・Dependabot はすべて `modules/<provider>/<module>/` を動的に探索します
  （新しいプロバイダーのディレクトリを足しても設定変更は不要です）。
  唯一の一覧であるルート README のモジュール一覧は `make new-module` が更新し、
  抜けは `make policy`（R001 / R002）が検出します。
- **CI の実行時間はモジュール数に比例させません。** PR では
  [scripts/changed-modules.sh](../scripts/changed-modules.sh) で変更のあったモジュールだけを
  `validate` / `test` / `tflint` の対象にします。Makefile・`scripts/`・`templates/`・
  ツール設定など全体に影響する変更の場合は全モジュールを対象にします。
  `main` / `develop` への push と週次メンテナンスでは常に全モジュールを検証するので、
  絞り込みによる取りこぼしはそこで拾えます。
- ローカルでも同じ絞り込みができます。

  ```bash
  make MODULE=modules/google/external-lb test                        # 単一モジュール
  make MODULES="$(scripts/changed-modules.sh origin/develop)" test   # 変更分だけ
  ```

- CI はモジュールごとにジョブを分けず、「Terraform のバージョンごとに 1 ジョブ」で
  対象モジュールをまとめて検証します。モジュール単位のジョブに分けると並列度は上がりますが、
  ジョブ起動のオーバーヘッドと実行時間の課金がモジュール数に比例して増えるためです。
  1 モジュールあたりの検証は数秒なので、当面はこの構成で十分です。

### 新しいプロバイダー（aws など）を追加するとき

触るのは次の 2 か所だけです。それ以外（Makefile・規約チェック・CI・Dependabot・
プロバイダーのバージョン確認・trivy・ルート README のモジュール一覧）は
`modules/<provider>/<module>/` を動的に探索するか `make new-module` が更新するので、
変更は要りません。規約チェッカーもリソース名の接頭辞からプロバイダーを判定するため、
`aws_s3_bucket` のようなリソースをそのまま扱えます。

1. **雛形**: `templates/module/<provider>/` を作る（手順は
   [templates/module/README.md](../templates/module/README.md)）。
   `make test-scripts` がすべての雛形を規約に照らして検査するので、追加したら実行してください。
2. **tflint**: [.tflint.hcl](../.tflint.hcl) にそのプロバイダーのルールセットを追加する
   （コメントで例を書いてあります）。

## 9. ツールのバージョンを上げる

1. [`.tool-versions`](../.tool-versions) のバージョンを変更する。
2. `make tools` を実行してローカルを更新する（mise が入れたものは `.gitignore` 済み）。
3. `make check` が通ることを確認する。
4. PR を出す。CI も同じバージョンでチェックを実行します。

Terraform の行は「最小サポートバージョン」です。モジュールの `required_version` を上げる
場合は、`.tool-versions`・各モジュールの `versions.tf`・各 README の Requirements を
すべて更新してください（食い違いは `make policy` が検出します）。

> [!IMPORTANT]
> CI のジョブ名には Terraform のバージョンが入ります（`validate & test (terraform 1.10.0)`）。
> Required status checks に登録している場合は、**バージョンを上げたときにチェック名も
> 更新してください**（古い名前のチェックは永久に来ないため PR がマージできなくなります）。

## 10. 新しいモジュールを追加する

```bash
make new-module NAME=google/pubsub-topic DESC="Pub/Sub トピック + IAM"
```

`templates/module/` から雛形を生成し、ルート README のモジュール一覧にも行を追加します。
生成直後の状態で `make preflight` が通るので、そこからサンプル実装を置き換えていきます
（`DESC` を省略した場合は一覧の概要が `TODO` のままになり、`make policy` が R002 で指摘します）。
詳細は [module_contribution_guidelines.md](./module_contribution_guidelines.md) の
「9. 新規モジュール追加のチェックリスト」を参照してください。
