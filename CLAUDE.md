# capsule の運用ポリシー

- **この repo の操作者・読者は Claude Code のみ**（人間は直接編集も精読もしない）。
  PR 作成・push・merge・デプロイ・bake まで全て自律実行してよい。
  確認待ちで止まらず、品質を担保できる範囲でどんどん進める。
- **ドキュメント・コメントは全て Claude Code 向けに書く**。人間向けの配慮
  （翻訳 README・鑑賞用コメント・commit body の和訳区切り）は不要。
  README.ja.md は置かない（2026-08-02 に削除済み）。
- **VM・イメージは使い捨て**: VM の破壊・削除はホストへの影響がほぼ無いので
  自由にやってよい。**破壊的変更も OK** — 互換レイヤーを残さず綺麗に壊す。
- **許諾済み（2026-08-02 本人明言）**: 各 Swift app repo を VM に clone して
  検証してよい。`ghcr.io/akira-toriyama/demo-base` への push もどんどん
  やってよい。VM 関連の作業は確認待ちせず進める。
  ただし **push 許諾は行使していない** — レイヤ再利用が無い
  （cirruslabs/tart#771）ため registry push は設計として採らず、配布は
  `make export` の `.tvm`（[docs/design.md](docs/design.md) §Image vs recipe
  と Makefile の `push` target 不在が正本）。許諾は将来 registry が必要に
  なったときのために残してある。
- 目的: akira-toriyama Swift app family（wand, sill, prism, facet,
  …）向けの headless GUI 検証環境（Tart VM）。設計判断と
  検証済み事実は [docs/design.md](docs/design.md) が正典。
- Swift app 側からこの検証環境を使う入口は dotfiles 管理の
  `macos-gui-verify` skill（そこに capsule への導線を置く）。
