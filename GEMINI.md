# terraform-modules（Gemini CLI 固有の注意）

このリポジトリでの作業ルールは [AGENTS.md](AGENTS.md) にある。エージェントの種類で
守ることは変わらないので、規約をこのファイルに書き足さず `docs/` 側を直す。

`AGENTS.md` は [.gemini/settings.json](.gemini/settings.json) の `context.fileName` で
このファイルと一緒に読み込まれる。読み込まれていないときは自分で開く。

## ツールの使い方

- `replace`: **正確に一致する短い文字列**の置換にだけ使う。大きなブロックや複雑な
  フォーマットは `read_file` で読み、編集してから `write_file` で書き戻す。
- `read_file` / `write_file`: プロジェクトルート内の**絶対パス**を指定する。
- `gh pr create` / `gh issue create`: 本文はシェルの解釈を避けるため一時ファイルに
  書き出して `--body-file` で渡し、作成後にその一時ファイルを削除する。
- Confluence を操作する場合は、ユーザーから明示された作業スペースの外を参照・作成・編集しない。
