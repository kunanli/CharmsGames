extends Node2D

# ─────────────────────────────────────────────────────────
# 通用排行榜面板（三款遊戲共用一份，不要各寫一套）。
#
# launcher 負責在 add_child 前設定欄位：
#   game_id / game_name
# 之後面板自己跟 LeaderboardManager 要資料，排行榜邏輯完全不進遊戲腳本。
#
# 版面（2026-08 美術進場後改版，2026-08 底改為「只看前 10」）：
#   - 底圖是各款的 assets/UI/LeaderBoard/rank-<game_id>.png
#     （catch/seeker 1920×1080、fishing 1536×864），全屏繪製
#     （邏輯 480×270）。表頭、花紋、標題都是美術畫在底圖上的。
#   - 資料表在 1920 座標的 (330, 240) 起、890×415（÷4 即邏輯座標）。
#   - **只顯示前 10 名**：左右兩欄各 5 列（左欄 1~5、右欄 6~10），
#     列距拉成兩倍、垂直置中落在原 20 列版面的行區內（底緣與原本
#     第 10 列同一條線，各款行區的實測常數直接沿用，見 LAYOUT）。
#   - 不顯示本局成績：沒有 YOUR SCORE 行、不高亮自己的記錄
#     （自己的排名與分數只在局終的 Game Over 界面顯示）。
#
# 一律只讀（2026-08 底：清除功能搬到管理員一級標題的清除選單
# ui/admin_clear_menu.gd，面板不再有任何清除入口）。
#
# 按鍵：
#   B / ESC   回該款二級標題（launcher 清名字、不保留玩家名稱）
# ─────────────────────────────────────────────────────────

signal exit_requested

# ── launcher 在 add_child 前設定 ─────────────────────────
var game_id := ""
var game_name := ""           # catch/fishing 的底圖沒畫標題，程式補畫

const SCREEN := Vector2(480, 270)
const TOP_N := 10             # 只顯示前 10 名，不翻頁

# 資料表區域：1920×1080 美術座標 (330, 240, 890, 415)，÷4 → 邏輯座標。
const DATA_X := 82.5
const DATA_W := 340

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
#   rows_y    = 原 10 列版面的第一列基線（前 10 名版式第 1 列在
#               rows_y + pitch，第 5 列在 rows_y + 9*pitch —— 見 _draw_rows）
#   pitch     = 原列距；前 10 名版式實際列距 = 2 * pitch
#   footer    = 頁腳（清除選單、TOP N、按鍵提示）：
#               mode "wide" 左右分佈在深色底，mode "center" 置中在行區下的淺色帶
#   light     = 文字底色是深色帶（true，淺色字）還是淺色底（false，深色字）
const LAYOUT := {
	"catch": {
		"bg": "res://assets/UI/LeaderBoard/rank-catch.png",
		"data_x": 82.5,
		"name_y": 12,
		"rows_y": 78, "pitch": 13,
		"footer": {"mode": "wide", "a": 247, "b": 258, "size": 10},
		"light": true,
	},
	"fishing": {
		"bg": "res://assets/UI/LeaderBoard/rank-fishing.png",
		"data_x": 82.5,
		"name_y": 8,
		"rows_y": 88, "pitch": 13,
		# 底部 y200 以下全是美術的花紋，頁腳置中放在行區下的乾淨淺色帶
		"footer": {"mode": "center", "a": 172, "b": 245, "c": 192, "size": 10},
		"light": true,
	},
	"seeker": {
		"bg": "res://assets/UI/LeaderBoard/rank-seeker.png",
		"data_x": 87.0,                     # 行區左緣有描邊，整欄右移閃開
		"name_y": -1,                       # 底圖已畫標題
		"rows_y": 102, "pitch": 11,          # 行區只有 372→655（底圖標題帶較高）
		# 底部全是花紋，頁腳置中放行區下的淺色帶（再下去 y205 是花紋線）
		"footer": {"mode": "center", "a": 178, "b": 246, "c": 230, "size": 10},
		"light": false,
	},
}

var _layout: Dictionary = {}
var _bg: Texture2D

var _records: Array = []        # Array[LeaderboardRecord]，前 10 名
var _total := 0


func _ready() -> void:
	_layout = LAYOUT.get(game_id, LAYOUT["catch"])
	_bg = load(_layout["bg"])
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.keycode == KEY_B or key.keycode == KEY_ESCAPE:
		exit_requested.emit()


## 重新向 Manager 要資料（永遠第一頁、前 TOP_N 條）。
func _refresh() -> void:
	var data := LeaderboardManager.get_page(game_id, 0, TOP_N)
	_total = data["total"]
	_records = data["records"]
	queue_redraw()


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

	if _total == 0:
		# 表格區三款都是淺色底，統一用深字
		_center("NO RECORDS YET - BE THE FIRST", 120, 8, Palette.NIGHT)
	else:
		_draw_rows()

	var f: Dictionary = _layout["footer"]
	_draw_footer_line(f, f["size"], text_col, dim_col)


## 前 10 名：左欄 1~5、右欄 6~10，各 5 列。列距 = 2×pitch，
## 第 1 列在 rows_y + pitch、第 5 列在 rows_y + 9×pitch —— 與原 20 列
## 版式的第 2~10 列同一批基線，行區內垂直置中，實測常數不用重調。
func _draw_rows() -> void:
	var font := ThemeDB.fallback_font
	var half_w := DATA_W / 2.0
	var pitch: float = _layout["pitch"]
	for i in _records.size():
		var r: LeaderboardRecord = _records[i]
		var side := i / 5                    # 0 左欄 1 右欄
		var row := i % 5
		var x := float(_layout["data_x"]) + side * half_w
		var y := float(_layout["rows_y"]) + (2 * row + 1) * pitch
		draw_string(font, Vector2(x + COL_RANK_RIGHT, y),
			"%d" % (i + 1), HORIZONTAL_ALIGNMENT_RIGHT, -1, 6, Palette.NIGHT)
		draw_string(font, Vector2(x + COL_NAME_LEFT, y), _fit_name(font, r.player_name, MAX_NAME_W),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Palette.NIGHT)
		draw_string(font, Vector2(x + COL_SCORE_RIGHT - 25, y), "%d" % r.score,
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


func _draw_footer_line(f: Dictionary, size: int, text_col: Color, dim_col: Color) -> void:
	var font := ThemeDB.fallback_font
	var first := 1
	var last := mini(TOP_N, _total)
	var page_text := "%d-%d / %d" % [first, last, _total]
	if f["mode"] == "center":
		_center(page_text, f["b"], size, dim_col)
		_center("B BACK", f["c"], size, text_col)
	else:
		draw_string(font, Vector2(12, f["b"]), page_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, dim_col)
		draw_string(font, Vector2(0, f["b"]), "B BACK",
			HORIZONTAL_ALIGNMENT_RIGHT, SCREEN.x - 12, size, text_col)


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, col)
