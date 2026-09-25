# CCtweaked-SimplifiedBroadcastingSystem

`CCtweaked-RailwayAnnouncementSystem` をベースに、無人駅向けの接近放送だけを残した簡易版です。

## 方針

元システムの Client / Server 責務を維持し、以下を削除しています。

- MTR API / metadata
- 通過・発車・停車中・次列車案内
- 発車時刻計算 / guidance bell
- rednet transport（1台PC運用のためlocal transportのみ）
- Client/Server間のasset同期

Client側で接近入力を受け、`Segment` / `Composer` で完成済みsegment列を作成し、`PlaybackClient` から同一PC内の `PlaybackServer` へ渡します。Server側はqueue、dedupe、TTL、実再生を担当します。

## 放送順序

```text
audio/melody/approach.dfpwm        接近チャイム
  ↓
audio/approach/soon.dfpwm
  ↓
audio/track/ni/<track>.dfpwm
  ↓
audio/approach/train.dfpwm         元システムの簡易放送fallback
  ↓
audio/approach/warning.dfpwm
  ↓
audio/melody/approach_after.dfpwm  任意
```

`approach_after.dfpwm` は存在しない場合、自動的に省略されます。`config.lua` の `announcement.melody.approachAfterEnabled = false` でも無効化できます。

## 2線入力

1台のComputerでbundled redstone 2線を監視します。各入力は `track` と bundled color の組み合わせだけで定義します。

| track | color |
|---:|---|
| 1 | `colors.red` |
| 2 | `colors.blue` |

sideは `top` です。すべて `config.lua` で変更できます。

```lua
lines = {
    { track = 1, color = colors.red },
    { track = 2, color = colors.blue },
}
```

`track` は放送する番線番号の識別にも使われ、`audio/track/ni/<track>.dfpwm` の選択に使用します。

起動時に既にHIGHの線は接近として扱わず、一度安定してLOWになった後にarmします。

## 音声import

`import_audio.lua` は元システムと同様に以下を受け付けます。

- `audio_pack.tar`: `/audio` 配下へ一括展開
- 単独 `.dfpwm`: `/audio/melody/approach_after.dfpwm` として保存

単独DFPWMの保存先だけ、元システムの `departure.dfpwm` から変更しています。

## インストール

CC:Tweaked Computer上で以下を実行します。

```text
wget run https://raw.githubusercontent.com/sankaku789/CCtweaked-SimplifiedBroadcastingSystem/main/install.lua
```

その後 `import_audio` で音声を投入し、必要に応じて `config.lua` を編集して再起動してください。

## 必要な音声

```text
audio/
├─ melody/
│  ├─ approach.dfpwm
│  └─ approach_after.dfpwm   # optional
├─ approach/
│  ├─ soon.dfpwm
│  ├─ train.dfpwm
│  └─ warning.dfpwm
└─ track/
   └─ ni/
      ├─ 1.dfpwm
      └─ 2.dfpwm
```
