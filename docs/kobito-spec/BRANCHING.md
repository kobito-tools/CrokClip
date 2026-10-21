# ブランチとコミットの決まり

kobito シリーズのどのリポジトリも、同じ決まりでブランチを分けます。GitHub で見たときに、どれが公開している版で、どれが開発中かが分かるようにするためです。

## ブランチ

| ブランチ | 役割 | どこから切るか | どこへ取り込むか |
|---|---|---|---|
| `main` | 公開している版。直接はコミットしない | — | — |
| `develop` | 開発の本流。次に公開する版がここで育つ | `main` | — |
| `feature/<内容>` | 機能を足す・変える作業1つ | `develop` | `develop` |
| `fix/<内容>` | 不具合を直す作業1つ | `develop` | `develop` |
| `release/<版>` | 公開の準備（版番号・README・変更の記録の仕上げ） | `develop` | `main` と `develop` |
| `hotfix/<内容>` | 公開している版の急ぎの直し | `main` | `main` と `develop` |

- `<内容>` は、英語の短い言葉をハイフンでつなぐ（例：`feature/series-actions`、`fix/screen-review`）。
- 取り込むときは `git merge --no-ff` を使う。こうすると、作業のまとまりが履歴に1つの取り込みとして残る。
- 取り込み終わった作業のブランチは消す（履歴は取り込みのコミットに残っている）。

## 公開するとき

1. `develop` から `release/<版>` を切る（例：`release/0.3.0`）。
2. 版番号（`pyproject.toml`・`package.json` など）と README を仕上げ、コミットする。
3. `main` へ `--no-ff` で取り込み、`main` の上でタグ `v<版>` を付ける。
4. 同じ `release/<版>` を `develop` へも取り込み、`release/<版>` を消す。

Python のアプリは Release を作らず、タグだけで版を表します（更新の確認もタグを見ます）。ネイティブのアプリ（Swift・Tauri）は、タグを push すると Release を作る仕組みがあるものもあります。

## コミット

- 変更の切れ目ごとにコミットする。あとで何を変えたかが分かるよう、英語で、何をしたかを書く。
- 作者は `ta-nish18 <54563775+ta-nish18@users.noreply.github.com>`。
- push とリモートの設定は、利用者が行う。
