# 二級標題待機動畫（IdleVideo）

三款遊戲的二級標題各有一支全屏待機動畫（10 秒無操作後循環播放），
路徑寫在 `launcher/launcher.gd` 的 `GAMES` 條目 `idle_video` 欄位：

| 遊戲 | 檔案 |
|---|---|
| CharmsSeeker | `CharmsSeeker_Idle.ogv` |
| CharmsFishing | `CharmsFishing_Idle.ogv` |
| CharmsCatch | `CharmsCatch_Idle.ogv` |

## 為什麼是 .ogv 不是 .mp4

Godot 內建 `VideoStreamPlayer` **只支援 Ogg Theora（.ogv）**，不支援 MP4
（官方文件明載 "The only supported format in core is Ogg Theora"）。
素材請以 MP4 交付，進 Godot 前先轉成 .ogv：

```bash
ffmpeg -i 素材.mp4 -q:v 6 -q:a 6 -g:v 64 CharmsSeeker_Idle.ogv
```

規格建議：

- **1920×1080、16:9** 最佳（與現有設計解析度一致，可以鋪滿全屏）
- 非 16:9 素材也可以播：畫面會**等比例縮放置中**（維持長寬比、不拉伸），
  多餘的邊用底色補
- 內容要能無縫循環（結尾接回開頭不跳幀）
- 音軌可留可不留；會隨影片一起播放
- 播放時畫面中央會閃爍 **CLICK TO PLAY** 提示（吸引模式標準做法）

放好檔案後用 Godot 重新開啟專案（自動 import 成 VideoStreamTheora），
待機功能即生效。檔案還沒放進來時功能不會報錯：計時照走、畫面停在
標題圖，素材到位後自動開始播。
