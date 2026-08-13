# Godot + Vibe Coding 上手指南 — 從 Charms Seeker 開始

> **注意：這是 Milestone 1 當時的建置紀錄，保留下來是為了「怎麼開始」那一段的思路。**
> 檔案位置已經在後來的重組中改過了 —— 文中的 `res://scripts/*.gd` 與 `Main.tscn`
> 現在分別是 `res://games/seeker/*.gd` 與 `Launcher.tscn`。
> **目前的目錄結構與硬規則一律以 `CLAUDE.md` 為準。**

---

## 0. 先回答：推薦嗎？

**推薦，但有一個前提。**

Godot 對你這三款遊戲幾乎是最佳解：純 2D、像素風、單一畫面不捲動、要吃手把、要匯出 PC/主機。引擎免費開源、沒有分潤、匯出 Windows 一鍵完成，手把支援內建（Xbox 手把插上就能用，不用寫驅動）。整包編輯器不到 100MB，解壓縮就能跑。

**但 vibe coding 在 Godot 有一個特定的摩擦點**：Godot 的「場景檔」（`.tscn`）是一種自訂格式，節點的階層、屬性、連線都存在裡面。AI 寫 `.tscn` 很容易寫出格式對但一開啟就報錯的檔案，而且你在編輯器裡拖拉的改動，AI 看不到。

**解法：讓場景保持極簡，邏輯全部寫在 `.gd` 裡。**

這份指南給的 Milestone 1，整個專案只有 **一個場景、一個節點**，迷宮、角色、珍珠全部由程式碼在執行時生成。這樣：

- AI 只需要讀寫純文字的 `.gd` 檔，成功率大幅提高
- 你要改迷宮，改的是程式碼裡的一個陣列，不是在編輯器裡一格一格拖
- Git diff 看得懂，出事可以回溯

等玩法都跑順了，再把美術素材接進來（那時候才需要真的碰編輯器）。

> **要不要考慮別的？** 如果只是做網頁展示，Phaser / 純 Canvas 也可以，而且 AI 更熟。但你要的是手把操作 + 可能上主機，那 Godot 明顯比較穩。Unity 對這種規模的小專案太重了。

---

## 1. 安裝（10 分鐘）

1. 到 <https://godotengine.org/download> 下載 **Godot 4.7.1 (Standard)**
   - 選 **Standard**，不要選 .NET/C# 版本 —— 我們用 GDScript，語法接近 Python，AI 寫得最好
   - 免安裝，解壓縮出來是一個執行檔，雙擊就開
2. 第一次開啟會看到 Project Manager → **Create New Project**
   - 專案名稱：`CharmsSeeker`
   - Renderer 選 **Compatibility**（2D 像素遊戲用這個最省資源、相容性最好）

---

## 2. 專案設定（像素遊戲必做的四件事）

開啟專案後，選單 **Project → Project Settings**：

| 設定路徑 | 值 | 為什麼 |
|---|---|---|
| Display → Window → Viewport Width / Height | `480` / `270` | 這就是企劃書寫的邏輯畫面 |
| Display → Window → Window Width / Height Override | `1440` / `810` | 開發時視窗放大 3 倍，看得清楚 |
| Display → Window → Stretch → Mode | `canvas_items` | 整數放大，像素不會糊 |
| Rendering → Textures → Canvas Textures → Default Texture Filter | `Nearest` | **最重要的一項**，不設會讓像素圖變模糊 |

> 打開 Project Settings 後記得把左上角的 **Advanced Settings** 打開，不然有些選項看不到。

---

## 3. 建立檔案

在 FileSystem 面板（左下角）按右鍵 → New Folder，建立 `scripts` 資料夾。

然後把附的三個檔案放進去：

```
res://
├── scripts/
│   ├── main.gd
│   ├── maze.gd
│   └── player.gd
└── Main.tscn
```

**建立 Main.tscn：**

1. 左上 Scene 面板 → **Other Node** → 搜尋 `Node2D` → 建立
2. 選中這個節點，右鍵 → **Attach Script** → 路徑填 `res://scripts/main.gd` → 因為檔案已存在，它會直接掛上
3. Ctrl+S 存成 `Main.tscn`
4. 選單 **Project → Project Settings → Application → Run → Main Scene** 設成 `Main.tscn`

**按 F5 執行。** 應該就會看到迷宮、珍珠、和一個可以用方向鍵移動的粉紅色方塊。

整個 Milestone 1 你在編輯器裡做的事，就只有上面這四步。

---

## 4. Milestone 路線圖

一次做一段，每段做完都能跑、能玩，不要一次全寫。

| # | 內容 | 大約規模 |
|---|---|---|
| **M1** | 迷宮生成 + 露娜格子移動 + 吃珍珠計分 | ← **這份指南給你的** |
| **M2** | HUD（秒數／分數／生命）+ 60 秒倒數 + 結算畫面 | 一個 CanvasLayer + 一支 hud.gd |
| **M3** | 暗影猫追逐 AI（3 隻，格子路徑追蹤） | 一支 cat.gd，最花時間的一段 |
| **M4** | 月光能量 + 石化狀態 + 擊碎 + 3 條命 | 在 M3 的基礎上加狀態機 |
| **M5** | 每 20 秒加一隻貓 + 清空重鋪 + 上限 8 隻 | 純數值邏輯，很快 |
| **M6** | 換上真的像素素材、音效、手把震動 | 這時才需要美術 |
| **M7** | 匯出 Windows / Web，接排行榜與 MysteryBox | — |

M1 到 M5 都可以完全用色塊（placeholder）做，美術可以並行進行、最後才接上。

---

## 5. Milestone 1 程式碼說明

三個檔案的分工：

- **`maze.gd`** — 純資料。迷宮長什麼樣、哪裡是牆、哪裡放珍珠。你要改迷宮只動這一個檔案的 `BLOCKS` 陣列。
- **`player.gd`** — 露娜的格子移動。Pac-Man 式的「轉彎預輸入」都在這裡。
- **`main.gd`** — 把上面兩者黏起來，負責畫圖與計分。

### 迷宮怎麼定義的

不用手打 ASCII 地圖（那個很容易打錯字，而且 AI 常常算錯字元數）。改成 **外框牆 + 一堆矩形障礙塊**：

```gdscript
const BLOCKS: Array[Rect2i] = [
    Rect2i(2, 2, 4, 2),    # x, y, 寬, 高（單位是 tile）
    ...
]
```

只要每個塊之間至少隔一格、且不碰到外框，走道就保證全部連通，不會出現走不到的死角。你要改迷宮外觀，加減幾個 `Rect2i` 就好，改完立刻 F5 看結果。

目前這組配置會生成 **約 200 顆珍珠**（企劃書寫 180 顆）。要對齊的話，多放一兩個障礙塊即可 —— 程式會自動重算，數字直接顯示在畫面上。

### 座標系統

- 一格 = 16 px，迷宮 28×14 格 = 448×224 px
- 迷宮左上角放在畫面 `(16, 32)`，上方 32px 留給 HUD
- `Vector2i` 是格子座標，`Vector2` 是像素座標，兩者用 `cell_center()` 轉換 —— **不要混用**，這是最常見的 bug 來源

### 移動邏輯的關鍵

Pac-Man 式移動不是「按住就走」，而是：

1. 角色永遠在往「某一格的中心」移動
2. 玩家的輸入存成 `want`（想要的方向），**不會立刻生效**
3. 每次抵達格子中心時，才檢查 `want` 方向能不能走，能走就轉彎

這樣手感才對 —— 你可以提前一點按方向，到路口自動轉。程式碼裡的 `_arrive_at_cell()` 就是在做這件事。

唯一的例外是「反方向」：往左走時按右，應該要立刻掉頭，不用等到下一格。這個特例在 `_read_input()` 裡處理。

---

## 6. 怎麼跟 AI 一起做（vibe coding 實務）

### 在專案根目錄放一個 `CLAUDE.md`

這是整個流程裡投報率最高的一件事。內容大致這樣：

```markdown
# CharmsSeeker

Godot 4.7 / GDScript / Compatibility renderer

## 硬規則
- 邏輯一律寫在 res://scripts/*.gd，不要修改 .tscn 檔
- 節點在程式碼中用 add_child() 建立，不要求我去編輯器拖拉
- 邏輯畫面固定 480x270，一格 16px，不要改
- 格子座標一律 Vector2i，像素座標一律 Vector2
- 不要引入外部套件或 addon

## 目前進度
M1 完成：迷宮、移動、吃珍珠
下一步：M2 HUD 與 60 秒倒數

## 玩法規格
（把企劃書的核心玩法段落貼進來）
```

有了這個，AI 每次都會照同一套規則寫，不會今天用 TileMap 明天用 ColorRect。

### 下指令的顆粒度

**不要這樣：**
> 幫我做完 Charms Seeker

**要這樣：**
> 讀 scripts/maze.gd 和 scripts/main.gd。加一個 60 秒倒數計時器，時間到就 print("TIME UP") 並暫停所有移動。計時器的秒數畫在畫面左上角，用現有的 draw_string 方式。不要改動迷宮和移動邏輯。

一次一個 Milestone、指定要讀哪些檔案、指定不准動哪些東西。這三件事做到，AI 的產出品質差很多。

### 每個 Milestone 結束就 commit

```bash
git init
git add -A && git commit -m "M1: 迷宮 + 移動 + 吃珍珠"
```

Godot 專案的 `.godot/` 資料夾是快取，加進 `.gitignore`。AI 改壞了直接 `git checkout .` 回去，比讓它自己修快得多。

---

## 7. 新手常踩的坑

| 症狀 | 原因 | 解法 |
|---|---|---|
| 像素圖糊掉 | Texture Filter 沒設 Nearest | 見第 2 節 |
| 角色卡在牆角、抖動 | 用了物理碰撞做格子移動 | 格子遊戲不要用 CharacterBody2D 的碰撞，用純數學判斷（這份程式碼就是） |
| `_draw()` 畫的東西不更新 | 忘記呼叫 `queue_redraw()` | 資料改變後一定要呼叫一次 |
| 改了程式碼但畫面沒變 | 場景還開著舊的 | 存檔後重新 F5 |
| AI 給的程式碼報 `Invalid call` | Godot 3 的舊寫法 | 提醒它「這是 Godot 4.7，用 `@onready`、`Vector2i`、`queue_redraw()`」 |

---

## 8. 下一步

M1 跑起來之後，最推薦的順序是 **先做 M2（計時與結算）再做 M3（貓）**。理由是有了 60 秒倒數，你才有一個完整的「一局」可以反覆測手感；貓的 AI 是整個專案最花時間的一段，最好在遊戲框架穩定之後再進去。

M2 要做的時候跟我說，我把 HUD 和倒數的程式碼寫給你。
