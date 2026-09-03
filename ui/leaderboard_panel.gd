extends Node2D

# ─────────────────────────────────────────────────────────
# 通用排行榜面板（三款遊戲共用一份，不要各寫一套）。
#
# launcher 負責在 add_child 前設定欄位：
#   game_id / player_name / score / record_id
# 之後面板自己跟 LeaderboardManager 要資料；「當前玩家」的成績與排名
# 由 launcher 傳入（submit 已在局終完成，record_id 一定查得到排名）。
#
# 版面（2026-09 改版：需求以 1920×1080 設計座標給定位、÷4 轉邏輯座標，
# 三款共用同一套，不再吃各款底圖的實測常數）：
#   - 底圖 = 各款 assets/UI/LeaderBoard/rank-<game_id>.png 全屏繪製
#     （美術只畫黑底＋裝飾，所有文字都是程式畫的）。
#   - 大標題 **YOUR SCORE**：(960, 80) 水平置中、96px（邏輯 24px）。
#   - **前 10 名單欄**垂直排列：第一行視覺中心 Y≈190（1920）、行距 72px；
#     每行三欄左對齊、字體 60px（邏輯 15px）：
#       排名 1ST./2ND./…（X≈370）、玩家名字（X≈620）、分數（X≈1255）。
#   - 進入面板時**逐行交錯顯現**：淡入＋從左滑入，每行錯開 ROW_STAGGER 秒，
#     只播一次；底部當前玩家行最後顯現。
#   - 畫面最底部是**當前玩家**的成績行（MOON_LIGHT 高亮，同樣排名／
#     名字／分數格式；排名是本局實際名次，可能 >10）—— 不管本局有沒有
#     進前 10 都會顯示。
#   - 配色（2026-09 企劃指定）：前十名行文字 = MOON（#A0DCFF），
#     大標題與底部當前玩家行 = MOON_LIGHT（#90FFFF，色盤新增色）。
#
# 按鍵：
#   B / ESC   回該款二級標題（launcher 清名字、不保留玩家名稱；
#             B＝鍵盤 S／手柄 B，2026-09 鍵盤 B 邏輯改到 S）
# ─────────────────────────────────────────────────────────

signal exit_requested

# ── launcher 在 add_child 前設定 ─────────────────────────
var game_id := ""
var player_name := ""
var score := 0
var record_id := ""

const SCREEN := Vector2(480, 270)
const TOP_N := 10             # 只顯示前 10 名，不翻頁

# ── 版面（1920×1080 設計座標 ÷ 4）────────────────────────
const TITLE_CENTER_Y := 20.0      # 標題視覺中心 (1920: 80)，水平置中
const TITLE_SIZE := 24            # 1920: 96px
const ROW_FONT := 15              # 每行字體 (1920: 60px)
const ROW_CENTER_Y := 47.5        # 第一行視覺中心 (1920: 190)
const ROW_PITCH := 18.0           # 行距 (1920: 72)
const RANK_X := 92.5              # 排名欄左緣 (1920: 370)
const NAME_X := 155.0             # 名字欄左緣 (1920: 620)
const SCORE_X := 313.75           # 分數欄左緣 (1920: 1255)
const PLAYER_BASELINE := 256.0    # 底部當前玩家行基線 (1920: 1024)

# 交錯顯現動畫（進入時只播一次）
const TITLE_DELAY := 0.10
const ROW_DELAY := 0.25           # 第一行開始顯現的時間
const ROW_STAGGER := 0.10         # 行與行之間錯開的秒數
const ROW_FADE := 0.22            # 單行淡入＋滑入的時長
const SLIDE_PX := 8.0             # 滑入的起始左移量（邏輯 px）

var _bg: Texture2D
var _records: Array = []        # Array[LeaderboardRecord]，前 10 名
var _total := 0
var _rank := -1
var _elapsed := 0.0
var _anim_done := false


func _ready() -> void:
	_bg = load("res://assets/UI/LeaderBoard/rank-%s.png" % game_id)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rank = LeaderboardManager.get_rank(record_id)
	_refresh()


func _process(delta: float) -> void:
	if _anim_done:
		return
	_elapsed += delta
	_anim_done = _elapsed >= _player_delay() + ROW_FADE
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# B／ESC 回二級。B 走 InputMap action（鍵盤 S／手柄 B，
	# 見 shared/arcade_input.gd）；手柄軸／滑鼠等事件不收。
	var key := event as InputEventKey
	var pad := event as InputEventJoypadButton
	if key == null and pad == null:
		return
	if key != null and (key.echo or not key.pressed):
		return
	get_viewport().set_input_as_handled()
	if ArcadeInput.pressed(event, ArcadeInput.ACTION_B) \
			or (key != null and key.keycode in [KEY_S, KEY_ESCAPE]):
		exit_requested.emit()


## 重新向 Manager 要資料（永遠第一頁、前 TOP_N 條）。
func _refresh() -> void:
	var data := LeaderboardManager.get_page(game_id, 0, TOP_N)
	_total = data["total"]
	_records = data["records"]
	queue_redraw()


## 底部當前玩家行的顯現起始時間：前十名全部顯現完之後。
func _player_delay() -> float:
	return ROW_DELAY + TOP_N * ROW_STAGGER + 0.12


## 交錯顯現的單行狀態：回傳 {alpha, dx}，alpha 0~1、dx 為滑入左移量。
## start 之前的行完全不可見（不畫），之後在 ROW_FADE 秒內淡入並歸位。
func _reveal(start: float) -> Dictionary:
	var t := _elapsed - start
	if t <= 0.0:
		return {"alpha": 0.0, "dx": SLIDE_PX}
	var k := clampf(t / ROW_FADE, 0.0, 1.0)
	return {"alpha": k, "dx": SLIDE_PX * (1.0 - k)}


# ── 繪製 ─────────────────────────────────────────────────

func _draw() -> void:
	if _bg != null:
		draw_texture_rect(_bg, Rect2(Vector2.ZERO, SCREEN), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, SCREEN), Palette.BG)
	var font := ThemeDB.fallback_font

	var t := _reveal(TITLE_DELAY)
	if t["alpha"] > 0.0:
		_center(font, "YOUR SCORE",
			TITLE_CENTER_Y + font.get_ascent(TITLE_SIZE) / 2.0,
			TITLE_SIZE, Color(Palette.MOON_LIGHT, t["alpha"]))

	if _total == 0:
		var e := _reveal(ROW_DELAY)
		if e["alpha"] > 0.0:
			_center(font, "NO RECORDS YET - BE THE FIRST",
				ROW_CENTER_Y + font.get_ascent(ROW_FONT) / 2.0 + ROW_PITCH * 5.0,
				8, Color(Palette.TEXT_DIM, e["alpha"]))
	else:
		_draw_rows(font)

	_draw_player_row(font)

	draw_string(font, Vector2(0, 264.0), "B BACK",
		HORIZONTAL_ALIGNMENT_RIGHT, SCREEN.x - 10.0, 6, Palette.TEXT_DIM)


func _draw_rows(font: Font) -> void:
	for i in _records.size():
		var e := _reveal(ROW_DELAY + i * ROW_STAGGER)
		if e["alpha"] <= 0.0:
			continue
		var r: LeaderboardRecord = _records[i]
		var y := ROW_CENTER_Y + font.get_ascent(ROW_FONT) / 2.0 + i * ROW_PITCH
		var col := Color(Palette.MOON, e["alpha"])
		var dx: float = e["dx"]
		draw_string(font, Vector2(RANK_X + dx, y), _ordinal(i + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT, col)
		draw_string(font, Vector2(NAME_X + dx, y), r.player_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT, col)
		draw_string(font, Vector2(SCORE_X + dx, y), "%d" % r.score,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT, col)


## 底部當前玩家行：最後顯現、MOON_LIGHT 高亮。排名是本局的實際名次
## （可能 >10；找不到記錄時顯示 -- 兜底）。
func _draw_player_row(font: Font) -> void:
	var e := _reveal(_player_delay())
	if e["alpha"] <= 0.0:
		return
	var col := Color(Palette.MOON_LIGHT, e["alpha"])
	var dx: float = e["dx"]
	var rank_text := _ordinal(_rank) if _rank > 0 else "--"
	draw_string(font, Vector2(RANK_X + dx, PLAYER_BASELINE), rank_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT, col)
	draw_string(font, Vector2(NAME_X + dx, PLAYER_BASELINE), player_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT, col)
	draw_string(font, Vector2(SCORE_X + dx, PLAYER_BASELINE), "%d" % score,
		HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT, col)


## 1ST.／2ND.／3RD.／4TH.…（英文序數＋句點）。
func _ordinal(i: int) -> String:
	var n := i % 100
	if n >= 11 and n <= 13:
		return "%dTH." % i
	match i % 10:
		1: return "%dST." % i
		2: return "%dND." % i
		3: return "%dRD." % i
	return "%dTH." % i


func _center(font: Font, text: String, y: float, size: int, col: Color) -> void:
	draw_string(font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, col)
