# メンテナンスガイド

このドキュメントは、`terraform-modules` を長く安全に運用するための「自動化されている仕組み」と、
それが失敗したときの対処をまとめたものです。

## 1. 自動化されていること


| いつ | 何が動くか | 失敗したときにやること |
| :--- | :--- | :--- |
| コミット時（`make hooks` を実行済みの場合） | `terraform fmt` と規約チェック | `make fmt-fix` で整形する |
| ローカルで `make preflight` | fmt + 規約 + validate + test + tflint | 表示されたコマンドで修正する |
| PR / `main` への push | CI（規約・tflint・validate & test・trivy） | ローカルで `make check` を実行すると同じ内容を再現できる |
| モジュール追加時 | `make new-module` が雛形・ルート README の一覧・テストまで用意する | 生成後に `make preflight` を実行して実装を進める |
| 毎週月曜 07:00 JST | Dependabot が GitHub Actions とプロバイダー制約の更新 PR を作る | PR の CI が通ることを確認してマージする |

CI で使うツールのバージョンは [`.tool-versions`](../.tool-versions) が唯一の情報源です。
ローカルの `make lint` / `make security` と CI は同じバージョンを使います。

## 2. ローカル環境のセットアップ


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

## 3. 規約チェック（`make policy`）が見ているもの


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

## 4. tflint / trivy


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

## 5. モジュールが増えても破綻しないための設計


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
  `main` への push では常に全モジュールを検証するので、
  絞り込みによる取りこぼしはそこで拾えます。
- ローカルでも同じ絞り込みができます。

  ```bash
  make MODULE=modules/google/external-lb test                        # 単一モジュール
  make MODULES="$(scripts/changed-modules.sh origin/main)" test   # 変更分だけ
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

## 6. ツールのバージョンを上げる


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

## 7. 新しいモジュールを追加する


```bash
make new-module NAME=google/pubsub-topic DESC="Pub/Sub トピック + IAM"
```

`templates/module/` から雛形を生成し、ルート README のモジュール一覧にも行を追加します。
生成直後の状態で `make preflight` が通るので、そこからサンプル実装を置き換えていきます
（`DESC` を省略した場合は一覧の概要が `TODO` のままになり、`make policy` が R002 で指摘します）。
詳細は [module_contribution_guidelines.md](./module_contribution_guidelines.md) の
「9. 新規モジュール追加のチェックリスト」を参照してください。
