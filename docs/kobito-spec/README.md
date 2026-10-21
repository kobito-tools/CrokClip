# kobito シリーズの規格（写し）

このフォルダは kobito-workspace の共通部品の中の、シリーズの規格の文書（`kobito_workspace/kit/docs`）の写しです。**直接書き換えないでください。**

- 写した元の版は `KIT_VERSION.json` にあります。
- 更新するときは、kobito-workspace で `uv run scripts/vendor_kit.py --docs-only <このフォルダ>` を実行します。
- 規格を変えたいときは、kobito-workspace の `kobito_workspace/kit/docs` を直してから写し直します。
- アプリ間の約束は `CONTRACTS.md`、入口と目印は `APP_PACKAGE.md`、名乗り方は `APP_INTERFACE.md` にあります。
