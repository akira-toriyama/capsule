# capsule

![platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)
![tool](https://img.shields.io/badge/Tart-2.30%2B-blue)
![license](https://img.shields.io/badge/license-MIT-blue)
![status](https://img.shields.io/badge/status-skeleton-orange)

[English](README.md) · **日本語**

akira-toriyama の Swift アプリ家系（wand, sill, prism, facet, focusfx …）の
**headless GUI 検証**のための、再現可能で使い捨ての **[Tart](https://tart.run)**
macOS VM。

ホスト機での GUI 自動化はフォーカスを奪い・ウィンドウを動かし・Space を飛ばす
——開発者の作業を妨げ、かつ非決定的（マルチディスプレイ座標・toolchain のブレ・
TCC の当たり外れ・別セッションとの repo 衝突）。capsule は検証ループまるごとを
使い捨て VM に移す：**カプセルを投げれば綺麗なラボが出現し、畳めば消える。**
狙いは **Claude Code がターミナルから端から端まで駆動でき、ホストを一切妨げない**
環境。

## ループ（日常・安い）

```
tart clone <base> <ephemeral>     # APFS copy-on-write — 一瞬・ディスクほぼ0
tart run  --dir=product:…/.build:ro --dir=app:…/App.app:ro <ephemeral>
  → peekaboo（スクショ + AX）+ helpers/click.swift（middle-click）で駆動
  → 結果をスクショ / AX で読む
tart delete <ephemeral>           # 差分だけ回収
```

ループの前後で必ず `export TART_NO_AUTO_PRUNE=1`。素の `tart clone`/`pull` は
OCI キャッシュを自動 prune（既定 100GB の LRU）し、他の VM を黙って消し得る。

## イメージでなくレシピ（両方出すが、正本はレシピ）

**レシピ**（`provision/*.sh` + `packer/base.pkr.hcl`）が diff 可能・レビュー可能・
再現可能な正本。焼いた ~27GB イメージは**使い捨てのローカルキャッシュ**
（`tart export` → `.tvm`）——git には入れず、既定で registry に push もしない
（`tart push` はレイヤ再利用がなく、re-bake ごとに ~27GB 再アップになる —
[cirruslabs/tart#771](https://github.com/cirruslabs/tart/issues/771)）。これは
家系の北極星「source > stale な brew スナップショット」の VM 版：push した
イメージ = stale スナップショット、レシピ = source。

> 焼くのに GitHub-hosted CI は要らない（Apple の Virtualization Framework は
> **Linux** ゲストしか nest できず、Tart の macOS VM は hosted macOS runner 上で
> 動かない）。**ホスト Mac でローカルに焼く**——隔離 VM 内で SSH 越しに走り、
> ホストのアプリには触れない＝焼き込みはホストを妨げない。将来は self-hosted の
> Apple Silicon runner で自動 re-bake も可能（cirruslabs 自身がそうしている）。

## 現状

🚧 **骨組み。** レシピはまだ端から端まで焼けておらず（`packer` 未インストール）、
検証ループも clone 内で未実行。`WIP` / `DRAFT` のファイルは未検証。唯一の実戦
投入可能な成果物は [`helpers/click.swift`](helpers/click.swift)（verbatim で退避）。

次は **risk-gated な立ち上げ**：Packer の焼き込みに投資する前に、*既存*の手作り
VM で headless の垂直スライスを1本通す。決定の記録・各選択の根拠・立ち上げ手順は
[docs/design.md](docs/design.md) を参照。追跡は `projects/t-8ffm`。
