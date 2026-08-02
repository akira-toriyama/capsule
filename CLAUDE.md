# capsule の運用ポリシー

- **この repo の操作者は Claude Code のみ**（人間は直接編集しない）。
  PR 作成・push・merge・デプロイ・bake まで全て自律実行してよい。
  確認待ちで止まらず、作業を進めることを優先する。
- 目的: akira-toriyama Swift app family（wand, sill, prism, facet,
  focusfx, …）向けの headless GUI 検証環境（Tart VM）。設計判断と
  検証済み事実は [docs/design.md](docs/design.md) が正典。
- Swift app 側からこの検証環境を使う入口は dotfiles 管理の
  `macos-gui-verify` skill（そこに capsule への導線を置く）。
