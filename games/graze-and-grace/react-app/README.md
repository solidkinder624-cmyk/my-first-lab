# GRAZE & GRACE (React)

`games/graze-and-grace/index.html`（外部ライブラリなしのCanvas版プロトタイプ）と同じゲームを、
Vite + React でビルドし直したもの。ゲームロジック本体（`core.js` / `score.js` / `rhythm.js`）は
一つ上の階層 (`games/graze-and-grace/`) にある同じファイルを共有しており、二重管理はしていない。

## セットアップ

```bash
npm install
npm run dev       # 開発サーバー (HMR付き)
npm run build     # 本番ビルド (dist/ に出力)
npm run preview   # ビルド結果をローカルで確認
npm run lint      # oxlint
npm test          # 共有ロジック(core.js/score.js/rhythm.js)のNode検証 (= ../verify.mjs)
```

## なぜ相対importではなく `graze-and-grace-core` というパッケージ名でimportしているか

`core.js` などは DOM に一切依存しない CommonJS 形式 (`module.exports = {...}`) で書かれていて、
`games/graze-and-grace/index.html` からは `<script src="./core.js"></script>` でそのまま
グローバル (`window.GrazeCore` 等) として読み込まれる。これはブラウザで直接開くだけで動く
（ビルド不要）という Canvas 版プロトタイプの特性を保つためにあえてそうしている。

Vite の開発サーバー (`npm run dev`) は、プロジェクト外の相対パス
(`import { x } from '../../core.js'`) を素の ES Module として扱おうとするため、
CommonJS の `module.exports` を自動変換してくれない
(`vite build` の本番ビルドは Rollup がバンドル時に変換するので動くが、
`npm run dev` の非バンドル配信ではエラーになる)。

これを回避するため、`games/graze-and-grace/package.json` でロジック一式を
`graze-and-grace-core` という名前のローカルパッケージとして定義し、
`npm install ../` (= `file:..` 依存) で `node_modules/graze-and-grace-core` に
シンボリックリンクしている。こうすると Vite の依存関係プリバンドラ（esbuild）が
通常のnpmパッケージと同様に CommonJS → ESM 変換を行ってくれる
(`vite.config.js` の `resolve.preserveSymlinks: true` と `optimizeDeps.include` が必要な設定)。

`core.js` 自体を書き換えていないので、Canvas版プロトタイプは一切影響を受けない。
