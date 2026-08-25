extends Node2D

# ─────────────────────────────────────────────────────────
# 通用排行榜面板（三款遊戲共用一份，不要各寫一套）。
#
# launcher 負責在 add_child 前設定欄位：
#   game_id / game_name / player_name / current_record_id /
#   score / game_over
# 之後面板自己跟 LeaderboardManager 要資料，排行榜邏輯完全不進遊戲腳本。
#
# 版面（2026-08 美術進場後改版）：
#   - 底圖是各款的 assets/UI/LeaderBoard/rank-<game_id>.png
#     （catch/seeker 1920×1080、fishing 1536×864），全屏繪製
#     （邏輯 480×270）。表頭、花紋、標題都是美術畫在底圖上的。
#   - 資料表在 1920 座標的 (330, 240) 起、890×415（÷4 即邏輯座標），
#     分成左右兩欄各 10 列，一頁共 20 筆。
#   - 各款的行起點／列距／結算與頁腳文字位置，依底圖實測的
#     深色帶與行區微調（見 LAYOUT），改圖時要一起對。
#
# 按鍵：
#   ← →       翻頁（首／末頁無操作）
#   C         清除選單（TODAY / YESTERDAY / DAY BEFORE）
#   1/2/3 直選或 ←→ 循環選日子，ENTER 進二次確認
#   ENTER     清除的二次確認 → 執行；平時 → restart_requested
#   ESC       清除時逐層取消；平時 → exit_requested
#
# 只讀模式（launcher 設 read_only=true，二級標題按 R 進入）：
#   以上全部停用，只剩 ESC → exit_requested（launcher 關面板回二級標題）；
#   不畫結算行與 YOUR SCORE，頁腳只留分頁資訊與 ESC BACK。
# ─────────────────────────────────────────────────────────

enum ClearState { NONE, SELECT, CONFIRM }

signal restart_requested
signal exit_requested

# ── launcher 在 add_child 前設定 ─────────────────────────
var game_id := ""
var game_name := ""           # catch/fishing 的底圖沒畫標題，程式補畫
var player_name := ""         # 底部「你的成績」要用，不從記錄找（同名會找錯）
var current_record_id := ""
var score := 0                # 本局最終分數（頂部結算行）
var game_over := false        # 顯示 GAME OVER 還是 TIME UP
var read_only := false        # 二級標題按 R 開的「只看」模式：不翻頁／清除／重開，只 ESC 關閉

const SCREEN := Vector2(480, 270)
const PAGE_SIZE := 20

# 資料表區域：1920×1080 美術座標 (330, 240, 890, 415)，÷4 → 邏輯座標。
const DATA_X := 82.5
const DATA_W := 340
const DATA_H := 240

# 每半欄（寬 111.25）內的行欄位，RANK 右對齊／NAME 左對齊／
# SCORE 右對齊／DIFF 左對齊（12 字名字與六位分數都不會互相頂到）。
const COL_RANK_RIGHT := 12
const COL_NAME_LEFT := 29
const COL_SCORE_RIGHT := 89
const COL_DIFF_LEFT := 93
# 名字最寬 43px（六位分數佔 20px＋2px 間距），超出就截掉
const MAX_NAME_W := COL_SCORE_RIGHT - COL_NAME_LEFT - 22

# 每款版面（依 rank-*.png 實測底圖的深色帶／行區／底部花紋位置調的）：
#   name_y  ≥ 0 表示底圖沒有標題要程式補畫（-1 則不畫）
#   result_y  = GAME OVER／SCORE 行的基線
#   rows_y    = 第一列基線，pitch = 列距
#   footer    = 頁腳（YOUR SCORE／清除選單、PAGE、按鍵提示）：
#               mode "wide" 左右分佈在深色底，mode "center" 置中在行區下的淺色帶
#   light     = 文字底色是深色帶（true，淺色字）還是淺色底（false，深色字）
const LAYOUT := {
	"catch": {
		"bg": "res://assets/UI/LeaderBoard/rank-catch.png",
		"data_x": 82.5,
		"name_y": 12,
		"result_y": 30,
		"rows_y": 78, "pitch": 13,
		"footer": {"mode": "wide", "a": 247, "b": 258, "size": 10},
		"light": true,
	},
	"fishing": {
		"bg": "res://assets/UI/LeaderBoard/rank-fishing.png",
		"data_x": 82.5,
		"name_y": 8,
		"result_y": 13,
		"rows_y": 88, "pitch": 13,
		# 底部 y200 以下全是美術的花紋，頁腳置中放在行區下的乾淨淺色帶
		"footer": {"mode": "center", "a": 172, "b": 245, "c": 192, "size": 10},
		"light": true,
	},
	"seeker": {
		"bg": "res://assets/UI/LeaderBoard/rank-seeker.png",
		"data_x": 87.0,                     # 行區左緣有描邊，整欄右移閃開
		"name_y": -1,                       # 底圖已畫標題
		"result_y": 14,
		"rows_y": 102, "pitch":11,           # 行區只有 372→655（底圖標題帶較高）
		# 底部全是花紋，頁腳置中放行區下的淺色帶（再下去 y205 是花紋線）
		"footer": {"mode": "center", "a": 178, "b": 246, "c": 230, "size": 10},
		"light": false,
	},
}

var _layout: Dictionary = {}
var _bg: Texture2D

var _page := 0                  # 0 基（第 1 頁是 0）
var _records: Array = []        # Array[LeaderboardRecord]
var _total := 0
var _page_count := 1
var _rank := -1                 # 本局記錄的排名；清除後可能失效（-1）

var _score_shown := 0.0         # 頂部結算分數，滾動追上 score
var _clear_state := ClearState.NONE
var _clear_day := 0             # 0=今天 1=昨天 2=前天
var _clear_labels := ["TODAY", "YESTERDAY", "DAY BEFORE"]


func _ready() -> void:
	_layout = LAYOUT.get(game_id, LAYOUT["catch"])
	_bg = load(_layout["bg"])
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_refresh()


func _process(delta: float) -> void:
	# 分數滾動（與各遊戲同一套公式）：小分數瞬間到位，大分數滾個 0.3 秒
	_score_shown = move_toward(_score_shown, float(score),
		maxf(150.0, absf(float(score) - _score_shown) * 3.0) * delta)
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()

	# 只讀模式（二級標題按 R 進入）：翻頁／清除／重開全部停用，只有 ESC 關閉
	if read_only:
		if key.keycode == KEY_ESCAPE:
			exit_requested.emit()
		return

	match _clear_state:
		ClearState.NONE:
			match key.keycode:
				KEY_LEFT:
					if _page > 0:
						_page -= 1
						_refresh()
				KEY_RIGHT:
					if _page < _page_count - 1:
						_page += 1
						_refresh()
				KEY_C:
					_clear_state = ClearState.SELECT
					_clear_day = 0
				KEY_ENTER, KEY_KP_ENTER:
					restart_requested.emit()
				KEY_ESCAPE:
					exit_requested.emit()
		ClearState.SELECT:
			match key.keycode:
				KEY_1:
					_clear_day = 0
				KEY_2:
					_clear_day = 1
				KEY_3:
					_clear_day = 2
				KEY_LEFT:
					_clear_day = (_clear_day + 2) % 3   # ← 上一個日子（循環）
				KEY_RIGHT:
					_clear_day = (_clear_day + 1) % 3   # → 下一個日子（循環）
				KEY_ENTER, KEY_KP_ENTER:
					_clear_state = ClearState.CONFIRM
				KEY_ESCAPE:
					_clear_state = ClearState.NONE
		ClearState.CONFIRM:
			match key.keycode:
				KEY_ENTER, KEY_KP_ENTER:
					_do_clear()
				KEY_ESCAPE:
					_clear_state = ClearState.SELECT


## 重新向 Manager 要資料。清除後排名會變（甚至可能清掉本局記錄），
## 所以每次刷新都重算 rank，不緩存。
func _refresh() -> void:
	var data := LeaderboardManager.get_page(game_id, _page)
	_page = data["page_index"]          # 越界時被夾回，以 Manager 為準
	_total = data["total"]
	_page_count = data["page_count"]
	_records = data["records"]
	_rank = LeaderboardManager.get_rank(current_record_id)
	queue_redraw()


func _do_clear() -> void:
	match _clear_day:
		0: LeaderboardManager.clear_today_records()
		1: LeaderboardManager.clear_yesterday_records()
		2: LeaderboardManager.clear_day_before_yesterday_records()
	_clear_state = ClearState.NONE
	_refresh()


# ── 繪製 ─────────────────────────────────────────────────

func _draw() -> void:
	if _bg != null:
		draw_texture_rect(_bg, Rect2(Vector2.ZERO, SCREEN), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, SCREEN), Palette.BG)
	var font := ThemeDB.fallback_font
	var text_col: Color = Palette.TEXT if _layout["light"] else Palette.NIGHT
	var dim_col: Color = Palette.TEXT_DIM if _layout["light"] else Palette.WALL_DARK

	if _layout["name_y"] >= 0:
		_center(game_name, _layout["name_y"], 12, text_col)

	# 結算行：TIME UP / GAME OVER（左）＋ 滾動分數（右）。只讀模式沒有本局成績，不畫。
	var ry: float = _layout["result_y"]
	if not read_only:
		draw_string(font, Vector2(12, ry), "GAME OVER" if game_over else "TIME UP",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, text_col)
		draw_string(font, Vector2(0, ry), "SCORE %06d" % int(round(_score_shown)),
			HORIZONTAL_ALIGNMENT_RIGHT, SCREEN.x - 12, 10, text_col)

	if _total == 0:
		# 表格區三款都是淺色底，統一用深字
		_center("NO RECORDS YET - BE THE FIRST", 120, 8, Palette.NIGHT)
	else:
		_draw_rows()

	_draw_bottom()


## 左右兩欄各 10 列：第 1~10 名在左欄，11~20 名在右欄。
func _draw_rows() -> void:
	var font := ThemeDB.fallback_font
	var half_w := DATA_W / 2.0
	var pitch: float = _layout["pitch"]
	for i in _records.size():
		var r: LeaderboardRecord = _records[i]
		var side := i / 10                    # 0 左欄 1 右欄
		var col := i % 10
		var x := float(_layout["data_x"]) + side * half_w
		var y := float(_layout["rows_y"]) + col * pitch
		var is_me := r.record_id == current_record_id
		if is_me:
			draw_rect(Rect2(x - 3, y - 6, half_w + 6, 8), Color(Palette.GOLD, 0.30))
			draw_string(font, Vector2(x - 7, y), ">", HORIZONTAL_ALIGNMENT_LEFT,
				-1, 6, Palette.WARN)
		draw_string(font, Vector2(x + COL_RANK_RIGHT, y),
			"%d" % (_page * PAGE_SIZE + i + 1), HORIZONTAL_ALIGNMENT_RIGHT, -1, 6,
			Palette.WARN if is_me else Palette.NIGHT)
		draw_string(font, Vector2(x + COL_NAME_LEFT, y), _fit_name(font, r.player_name, MAX_NAME_W),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Palette.NIGHT)
		draw_string(font, Vector2(x + COL_SCORE_RIGHT - 25 ,  y), "%d" % r.score,
			HORIZONTAL_ALIGNMENT_RIGHT, -1, 6, Palette.NIGHT)
		draw_string(font, Vector2(x + COL_DIFF_LEFT, y), r.difficulty_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Palette.WALL_DARK)


## 半欄只有 111px 寬，長名字按實際字寬截到不頂到分數欄為止。
func _fit_name(font: Font, name: String, max_w: float) -> String:
	var text := name
	while text.length() > 1:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x <= max_w:
			break
		text = text.substr(0, text.length() - 1)
	return text


func _draw_bottom() -> void:
	var font := ThemeDB.fallback_font
	var f: Dictionary = _layout["footer"]
	var ya: float = f["a"]
	var yb: float = f["b"]
	var size: int = f["size"]
	var text_col: Color = Palette.TEXT if _layout["light"] else Palette.NIGHT
	var dim_col: Color = Palette.TEXT_DIM if _layout["light"] else Palette.WALL_DARK
	var sel_col: Color = Palette.GOLD if _layout["light"] else Palette.WARN

	# 清除流程的提示優先（暫時蓋掉底部那行「你的成績」）
	if _clear_state == ClearState.SELECT:
		if f["mode"] == "center":
			# 置中模式整組居中（寬度算出來再分開畫，才能逐個上色）
			var labels := []
			var total := 0.0
			for i in 3:
				var t := "[%d] %s" % [i + 1, _clear_labels[i]]
				labels.append(t)
				total += font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 24
			var x := 240.0 - total / 2.0
			for i in 3:
				var col: Color = sel_col if i == _clear_day else dim_col
				draw_string(font, Vector2(x, ya), labels[i],
					HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
				x += font.get_string_size(labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 24
			_center("ESC BACK", yb, size, dim_col)
		else:
			var x := 12
			for i in 3:
				var col: Color = sel_col if i == _clear_day else dim_col
				var label := "[%d] %s" % [i + 1, _clear_labels[i]]
				draw_string(font, Vector2(x, ya), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
				x += 96
			draw_string(font, Vector2(0, ya), "ESC BACK",
				HORIZONTAL_ALIGNMENT_RIGHT, SCREEN.x - 12, size, dim_col)
			_draw_footer_line(f, size, text_col, dim_col)
		return
	if _clear_state == ClearState.CONFIRM:
		_center("CLEAR %s? [ENTER] CONFIRM  [ESC] CANCEL" % _clear_labels[_clear_day],
			ya, size, Palette.WARN)
		if f["mode"] == "wide":
			_draw_footer_line(f, size, text_col, dim_col)
		return

	# 本局成績不在前 20 名時，底部補一行（rank ≤ 20 只在表格裡高亮，不重複）。
	# 只讀模式沒有本局成績，不畫。
	if not read_only and _rank > PAGE_SIZE:
		if f["mode"] == "center":
			_center("YOUR SCORE  #%d  %s  %d" % [_rank, player_name, score],
				ya, size, Palette.WARN)
		else:
			draw_string(font, Vector2(12, ya), "YOUR SCORE  #%d  %s  %d" % [
				_rank, player_name, score], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.WARN)

	_draw_footer_line(f, size, text_col, dim_col)


func _draw_footer_line(f: Dictionary, size: int, text_col: Color, dim_col: Color) -> void:
	var font := ThemeDB.fallback_font
	var first := 0 if _total == 0 else _page * PAGE_SIZE + 1
	var last := mini(first + PAGE_SIZE - 1, _total)
	# 只讀模式：去掉 [C] CLEAR 與 ENTER RESTART 提示，只留分頁與返回
	if read_only:
		if f["mode"] == "center":
			_center("%d        %d" % [first, last], f["b"], size, dim_col)
			_center("ESC BACK", f["c"], size, text_col)
		else:
			draw_string(font, Vector2(12, f["b"]), "PAGE %d-%d / %d" % [first, last, _total],
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, dim_col)
			draw_string(font, Vector2(0, f["b"]), "ESC BACK",
				HORIZONTAL_ALIGNMENT_RIGHT, SCREEN.x - 12, size, text_col)
		return
	if f["mode"] == "center":
		_center("PAGE %d-%d / %d  [C] CLEAR" % [first, last, _total], f["b"], size, dim_col)
		_center("ENTER RESTART  ESC EXIT", f["c"], size, text_col)
	else:
		draw_string(font, Vector2(12, f["b"]), " %d-%d / %d  [C] CLEAR" % [first, last, _total],
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, dim_col)
		draw_string(font, Vector2(0, f["b"]), "ENTER RESTART  ESC EXIT",
			HORIZONTAL_ALIGNMENT_RIGHT, SCREEN.x - 12, size, text_col)


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, col)
