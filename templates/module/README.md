# モジュール雛形

`make new-module NAME=<provider>/<module-name> DESC="<概要>"` が使う雛形です。
プロバイダーごとにディレクトリを分けています。

```
templates/module/
└── google/    # modules/google/* を作るときの雛形
```

## 新しいプロバイダー（例: aws）に対応する

1. `templates/module/aws/` を作り、`google/` と同じ 6 ファイルを置く。
   （`main.tf` / `variables.tf` / `outputs.tf` / `versions.tf` / `README.md` / `main.tftest.hcl`）
2. 雛形の中身はそのプロバイダーで**実際に動くサンプル実装**にする。
   `make new-module` 直後に `make preflight` が通る状態を保つため。
3. `.tflint.hcl` にそのプロバイダーのルールセットを追加する
   （例: `tflint-ruleset-aws`）。
4. `make test-scripts` を実行する。`templates/module/*` のすべての雛形が
   リポジトリ規約を満たしているかを自動で検査します。

## プレースホルダー

| トークン | 置換される値（例: `google/pubsub-topic`） |
| :--- | :--- |
| `__MODULE_NAME__` | `pubsub-topic` |
| `__MODULE_SNAKE__` | `pubsub_topic` |
| `__MODULE_TITLE__` | `Pubsub Topic` |
| `__MODULE_PATH__` | `modules/google/pubsub-topic` |
