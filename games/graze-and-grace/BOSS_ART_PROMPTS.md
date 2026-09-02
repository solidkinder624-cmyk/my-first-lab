# ボスキャラクター 画像生成プロンプト（NijiJourney用）

`GAME_DESIGN.md` 6.1章のキャラ設定をもとにした NijiJourney (v6) 向けプロンプト。
4人とも「耽美・ゴシック」で作風を揃えるため、共通のスタイルタグ
（gothic dark fantasy, decadent elegant atmosphere, cinematic dramatic lighting,
full body portrait）を末尾に付けている。

## 使い方のコツ

- まずは4人ともこのプロンプトのまま1枚ずつ生成し、気に入った絵柄が出たら
  `--sref <画像URL>` （スタイル参照）でその絵の雰囲気を他のキャラにも適用すると
  シリーズとしての統一感が出しやすい。
- 顔立ちを固定してポーズ違い・衣装違いを量産したい場合は `--cref <画像URL>`
  （キャラクター参照、Niji 6で対応）を使う。
- `--niji 6` の中でも `--style expressive` はドラマチックな陰影と作り込んだ衣装が
  出やすく、この企画のダークファンタジー耽美路線と相性が良い。可愛らしさを強めたい
  場合は `--style cute`、写実寄りにしたい場合は `--style scenic` も試す価値がある。
- 単語の重み付けは `::` で調整できる（例: `slender dancer's physique::1.5`）。
  体型の個性が薄いと感じたら該当ワードの重みを上げる。

---

## 1. 星詠みの魔道士（星辰の花嫁）

```
a beautiful young woman with an alluring, ethereal aura, slender dancer's
physique with long graceful limbs and elegant ballet-like poise, wearing a
deep navy-black long flowing robe embroidered with gold constellation
patterns that reveals her collarbone and back, long flowing silver hair,
one eye covered by a star-shaped eyepatch, the other eye reflecting a
starry night sky, wearing a celestial armillary sphere pendant, delicate
fingers conjuring glowing stardust particles, surrounded by faint
constellation lines, gothic dark fantasy, decadent elegant atmosphere,
cinematic dramatic lighting, intricate ornate costume design,
full body portrait --ar 2:3 --niji 6 --style expressive
```

## 2. 神殿の聖騎士（白亡の裁定者）

```
a tall beautiful young woman with an athletic yet elegantly feminine
physique and perfectly symmetrical proportions, wearing ornate
white-silver full plate armor with a flowing crimson cape and gold trim
accentuating her shoulders chest and waist, a full-face mask-like helmet
concealing her face with only glowing eyes visible, alluring exposed nape
and neckline, wing-shaped armor motifs on her back, wielding a sword made
of condensed radiant light, gothic dark fantasy, decadent elegant
atmosphere, cinematic dramatic lighting, intricate ornate armor design,
full body portrait --ar 2:3 --niji 6 --style expressive
```

## 3. 妖精の女王（常夜の花園主）

```
a beautiful young woman with soft alluring curves and a voluptuous
figure, ageless ethereal charm, wearing a revealing dress woven from
vines and wilting flower petals, long hair in a gradient from deep green
to purple, small thorn-shaped hairpins, delicate translucent butterfly
wings on her back, barefoot and floating slightly above the ground,
surrounded by falling petals and thorny vine tendrils, gothic dark
fantasy, decadent elegant atmosphere, cinematic dramatic lighting,
intricate botanical costume design, full body portrait
--ar 2:3 --niji 6 --style expressive
```

## 4. 深淵のネクロマンサー（終幕の道化）

```
a beautiful slender young woman with long limbs and a sharp dramatic
cabaret-dancer silhouette, wearing a feminized black gothic tailcoat
dress with corset lacing and fishnet-like details, a masquerade mask
covering half her face, holding a bone-shaped cane, shrouded in purple
smoke, a small will-o'-the-wisp flame flickering on her fingertip, eerie
yet youthful expression, gothic dark fantasy, decadent theatrical
atmosphere, cinematic dramatic lighting, intricate ornate costume design,
full body portrait --ar 2:3 --niji 6 --style expressive
```
