# CharmsGames

Pandora 品牌合作的三款 8-bit 像素小遊戲，共用世界觀、色盤與結算系統。
每款都是單一關卡、60 秒，局終計分數並進當地排行榜（寶箱系統已移除）。

**Godot 4.7 / GDScript**，邏輯畫面 480×270，4 倍整數放大。

| | 玩法 | 狀態 |
|---|---|---|
| **CharmsSeeker** | 迷宮追逐（小精靈式），躲三隻暗影猫收集星塵珍珠 | 到 M4 |
| **CharmsFishing** | 黃金礦工式夜釣，鉤子自動擺、玩家只決定何時放線 | 首版完成 |
| **CharmsCatch** | 底部左右移動接珠寶、躲炸彈，靠 Combo 倍率拉分 | 首版完成 |

---

## 跑起來

1. 裝 **Godot 4.7**（純 GDScript，不需要 .NET 版）
2. Godot Project Manager → Import → 選這個 repo 的 `project.godot`
3. 按 **Run**
4. 選單按 **1 / 2 / 3** 進遊戲；首次進遊戲要先輸入名字（**← → 可選難度 EASY／HARD**）。
   遊戲中按 **ESC** 回選單，結算按 **Enter** 重來

### 操作

| | 移動 | 主動技能 |
|---|---|---|
| Seeker | 方向鍵（**不支援 WASD**） | **A** 啟動 8 秒石化（需先撿到月光能量） |
| Fishing | ← → 探看湖面 | **A**／空白／↓／Enter 放線；**B**／**X** 用月光能量 |
| Catch | ← → | **A** 衝刺；**B**／**X** 引爆護盾 |

### 第一次跑會看到什麼

**畫面上所有東西都是程式畫的色塊與線條** —— 粉紅方框是露娜，紫色方框是暗影猫。
`assets/` 是空的，美術素材還沒進場（M6）。這是預期的，不是壞掉。

另外，第一次用 Godot 開啟專案時會多出一批 `*.gd.uid` 檔（Godot 自動生成的
資源 ID）。那是正常的，**請一起 commit** —— 目前 repo 裡只有 `games/seeker/`
下的幾支有，其餘是在沒有 Godot 的環境寫的所以還沒生成。

---

## 開發

在分支上開發，完成一個 Milestone 就開 PR 併回 `main`。歷史用 merge commit
保留（不 squash），這樣 `git bisect` 才找得到是哪一次改動出的問題。

**開發指南在 [`AGENTS.md`](AGENTS.md)** —— 硬規則、架構決定、三款的完整玩法規格、
待辦與其中的坑，全部在那一份。動手前請先讀。

規格的最終權威是 `Guides/` 裡的三份 GDD；`AGENTS.md` 記的是實作上的決定，
以及 GDD 沒寫或寫了行不通、我們自己補的部分。

### 改數值前先跑模擬

這個專案的平衡完全靠數值堆出來，而開發環境沒有 Godot binary，
所以邏輯有一份 Python 移植可以跑幾百局驗證：

```bash
python3 tools/sim/juice_sim.py      # 震動／漂移／擠壓的數學性質
python3 tools/sim/seeker_sim.py     # 迷宮結構、貓 AI、石化狀態機、難度
python3 tools/sim/fishing_sim.py    # 物件放置、死內容、分數分佈
python3 tools/sim/catch_sim.py      # Combo 可達性、分數分佈、頓格
```

只需要 Python 3，無相依套件。**改數值前跑一次記下基準，改完再跑一次比較。**
用眼睛看程式碼判斷不出「中位分數會落在哪個區間」—— 這套做法實際抓到過五個
會出貨的 bug，清單在 [`tools/sim/README.md`](tools/sim/README.md)。
