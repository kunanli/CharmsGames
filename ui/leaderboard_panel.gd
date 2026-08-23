extends Node2D

# ─────────────────────────────────────────────────────────
# 通用排行榜面板（三款遊戲共用一份，不要各寫一套）。
#
# launcher 負責在 add_child 前設定欄位：
#   game_id / game_name / player_name / current_record_id /
#   score / game_over / chest_tiers
# 之後面板自己跟 LeaderboardManager 要資料，排行榜邏輯完全不進遊戲腳本。
#
# 取代各遊戲原本的結算畫面：頂部承接「GAME OVER / TIME UP + 分數滾動 +
# 寶箱等級揭曉」，下面就是排行榜。
#
# 按鍵：
#   ← →       翻頁（首／末頁無操作）
#   C         清除選單（TODAY / YESTERDAY / DAY BEFORE）
#   1/2/3 直選或 ←→ 循環選日子，ENTER 進二次確認
#   ENTER     清除的二次確認 → 執行；平時 → restart_requested
#   ESC       清除時逐層取消；平時 → exit_requested
# ─────────────────────────────────────────────────────────

enum ClearState { NONE, SELECT, CONFIRM }

signal restart_requested
signal exit_requested

# ── launcher 在 add_child 前設定 ─────────────────────────
var game_id := ""
var game_name := ""
var player_name := ""           # 底部「你的成績」要用，不從記錄找（同名會找錯）
var current_record_id := ""
var score := 0                  # 本局最終分數（頂部結算行）
var game_over := false          # 顯示 GAME OVER 還是 TIME UP
var chest_tiers: Array[int] = [1500, 3000, 5000]   # 銅／銀／金

const SCREEN := Vector2(480, 270)
const PAGE_SIZE := 20

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


func _chest_tier() -> String:
	if score >= chest_tiers[2]:
		return "GOLD CHEST"
	elif score >= chest_tiers[1]:
		return "SILVER CHEST"
	elif score >= chest_tiers[0]:
		return "BRONZE CHEST"
	return "NO CHEST"


# ── 繪製 ─────────────────────────────────────────────────

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Palette.BG)
	var font := ThemeDB.fallback_font

	_center(game_name, 16, 12, Palette.GOLD)

	# 結算行：TIME UP / GAME OVER + 滾動分數 + 寶箱等級（滾完才揭曉）
	var over_col: Color = Palette.WARN if game_over else Palette.GOLD
	draw_string(font, Vector2(12, 32), "GAME OVER" if game_over else "TIME UP",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, over_col)
	draw_string(font, Vector2(0, 32), "SCORE %06d" % int(round(_score_shown)),
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, 10, Palette.TEXT)
	if int(round(_score_shown)) >= score:
		draw_string(font, Vector2(0, 32), _chest_tier(),
			HORIZONTAL_ALIGNMENT_RIGHT, SCREEN.x - 12, 10, Palette.MOON)

	# 表頭（x 座標與 _draw_rows 完全一致）
	draw_string(font, Vector2(44, 44), "RANK", HORIZONTAL_ALIGNMENT_RIGHT, -1, 8, Palette.TEXT_DIM)
	draw_string(font, Vector2(48, 44), "NAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.TEXT_DIM)
	draw_string(font, Vector2(240, 44), "SCORE", HORIZONTAL_ALIGNMENT_RIGHT, -1, 8, Palette.TEXT_DIM)
	draw_string(font, Vector2(254, 44), "DIFF", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.TEXT_DIM)
	draw_string(font, Vector2(324, 44), "TIME", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.TEXT_DIM)

	if _total == 0:
		_center("NO RECORDS YET - BE THE FIRST", 120, 10, Palette.TEXT_DIM)
	else:
		_draw_rows()

	_draw_bottom()


func _draw_rows() -> void:
	var font := ThemeDB.fallback_font
	var y := 52
	for i in _records.size():
		var r: LeaderboardRecord = _records[i]
		var is_me := r.record_id == current_record_id
		var col: Color = Palette.GOLD if is_me else Palette.TEXT
		if is_me:
			draw_rect(Rect2(2, y - 7, SCREEN.x - 4, 9), Color(Palette.GOLD, 0.10))
			draw_string(font, Vector2(4, y), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.GOLD)
		# 列距：RANK 右對齊（第 1000 名也不頂到 NAME）；SCORE 右對齊（七位數
		# 也不頂到 DIFF）。行首 ">" 只畫在目前玩家的那一行。
		draw_string(font, Vector2(44, y), "%d" % (_page * PAGE_SIZE + i + 1),
			HORIZONTAL_ALIGNMENT_RIGHT, -1, 8, col)
		draw_string(font, Vector2(48, y), r.player_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
		draw_string(font, Vector2(240, y), "%d" % r.score,
			HORIZONTAL_ALIGNMENT_RIGHT, -1, 8, col)
		draw_string(font, Vector2(254, y), r.difficulty_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.TEXT_DIM)
		draw_string(font, Vector2(324, y), r.played_at.substr(5, 11),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.TEXT_DIM)
		y += 9


func _draw_bottom() -> void:
	var font := ThemeDB.fallback_font

	# 清除流程的提示優先（暫時蓋掉底部那行「你的成績」）
	if _clear_state == ClearState.SELECT:
		var x := 12
		for i in 3:
			var col: Color = Palette.GOLD if i == _clear_day else Palette.TEXT_DIM
			var label := "[%d] %s" % [i + 1, _clear_labels[i]]
			draw_string(font, Vector2(x, 246), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
			x += 96
		draw_string(font, Vector2(0, 246), "ESC BACK",
			HORIZONTAL_ALIGNMENT_RIGHT, SCREEN.x - 12, 8, Palette.TEXT_DIM)
		_draw_footer()
		return
	if _clear_state == ClearState.CONFIRM:
		_center("CLEAR %s? [ENTER] CONFIRM  [ESC] CANCEL" % _clear_labels[_clear_day],
			246, 8, Palette.WARN)
		_draw_footer()
		return

	# 本局成績不在前 20 名時，底部補一行（rank ≤ 20 只在表格裡高亮，不重複）
	if _rank > PAGE_SIZE:
		draw_string(font, Vector2(12, 246), "YOUR SCORE  #%d  %s  %d" % [
			_rank, player_name, score], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.WARN)

	_draw_footer()


func _draw_footer() -> void:
	var font := ThemeDB.fallback_font
	var first := 0 if _total == 0 else _page * PAGE_SIZE + 1
	var last := mini(first + PAGE_SIZE - 1, _total)
	draw_string(font, Vector2(12, 258), "PAGE %d-%d / %d  [C] CLEAR" % [first, last, _total],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.TEXT_DIM)
	draw_string(font, Vector2(0, 258), "ENTER RESTART  ESC EXIT",
		HORIZONTAL_ALIGNMENT_RIGHT, SCREEN.x - 12, 8, Palette.TEXT_DIM)


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, col)
