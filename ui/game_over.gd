extends Node2D

# ─────────────────────────────────────────────────────────
# 局終 Game Over 界面（三款遊戲共用一份，取代「局終直接進排行榜」）。
#
# launcher 負責在 add_child 前設定欄位：
#   title_image / player_name / score / game_over / record_id
# 排名由本檔自己用 record_id 向 LeaderboardManager 查（submit 已在局終
# 完成，新記錄一定查得到），launcher 不重複算。
#
# 版面（程式繪製，美術還沒出 GameOver 素材）：
#   底層 = 該款二級標題圖 + 50% 黑罩（與起名 overlay 同一套分層），
#   中央一個 NIGHT 底、GOLD 框的面板，依序顯示：
#     GAME OVER / TIME UP（大字）→ PLAYER 名字 → SCORE 分數（滾動）
#     → RANK 排名 → RESTART／LEADERBOARD 兩個按鈕（↑ ↓ 切換、A 執行）。
#
# 按鍵：
#   ↑ ↓（或 A 以外的任一方向）  切換 RESTART／LEADERBOARD
#   A（或 Enter／空白）         執行選中的按鈕
#   B / ESC                    回該款二級標題（launcher 清名字）
#
# 分數滾動與遊戲內同一套公式（fx.gd）：小分數瞬間到位、大分數滾 0.3 秒。
# ─────────────────────────────────────────────────────────

signal restart_requested
signal leaderboard_requested
signal exit_requested

const SCREEN := Vector2(480, 270)
const BUTTONS := ["RESTART", "LEADERBOARD"]

const PANEL := Rect2(90, 36, 300, 186)
const BTN_W := 180.0
const BTN_H := 18.0
const BTN_X := (SCREEN.x - BTN_W) / 2.0
const BTN_Y := [158.0, 184.0]     # RESTART / LEADERBOARD 的按鈕上緣

var title_image: Texture2D        # 該款二級標題圖，套黑罩當底
var player_name := ""
var score := 0
var game_over := false            # true 顯示 GAME OVER，false 顯示 TIME UP
var record_id := ""               # 查本局排名用

var _rank := -1
var _sel := 0                     # 0 = RESTART，1 = LEADERBOARD
var _score_shown := 0.0           # 分數滾動：追 score


func _ready() -> void:
	_rank = LeaderboardManager.get_rank(record_id)


func _process(delta: float) -> void:
	_score_shown = move_toward(_score_shown, float(score),
		maxf(150.0, absf(float(score) - _score_shown) * 3.0) * delta)
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	match key.keycode:
		KEY_UP, KEY_DOWN:
			_sel = 1 - _sel
			AudioManager.play_sfx("ui_select")   # 切換 RESTART／LEADERBOARD
			queue_redraw()
		KEY_A, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			AudioManager.play_sfx("ui_confirm")   # 執行選中的按鈕
			_confirm()
		KEY_B, KEY_ESCAPE:
			exit_requested.emit()


func _confirm() -> void:
	if _sel == 0:
		restart_requested.emit()
	else:
		leaderboard_requested.emit()


# ── 繪製 ─────────────────────────────────────────────────

func _draw() -> void:
	if title_image != null:
		draw_texture_rect(title_image, Rect2(Vector2.ZERO, SCREEN), false)
	# 50% 黑罩：底下的標題圖透得出來，凸顯面板（與起名 overlay 同一套）
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.0, 0.0, 0.0, 0.5))

	var font := ThemeDB.fallback_font
	draw_rect(PANEL, Palette.NIGHT)
	draw_rect(PANEL, Palette.GOLD, false, 1.0)

	var rank_text := "RANK  #%d" % _rank if _rank > 0 else "RANK  --"
	_center("GAME OVER" if game_over else "TIME UP", 64, 18, Palette.WARN)
	_center("PLAYER  %s" % player_name, 92, 10, Palette.TEXT)
	_center("SCORE  %06d" % int(round(_score_shown)), 122, 16, Palette.GOLD)
	_center(rank_text, 144, 10, Palette.MOON)

	_draw_button(font, 0)
	_draw_button(font, 1)
	_center("ARROWS SELECT   A CONFIRM   B BACK", 248, 8, Palette.TEXT_DIM)


func _draw_button(font: Font, idx: int) -> void:
	var selected := idx == _sel
	var rect := Rect2(BTN_X, BTN_Y[idx], BTN_W, BTN_H)
	if selected:
		draw_rect(rect, Color(Palette.GOLD, 0.22))
	draw_rect(rect, Palette.GOLD if selected else Palette.WALL_DARK, false, 1.0)
	if selected:
		draw_string(font, Vector2(BTN_X - 10, BTN_Y[idx] + 12), ">",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.GOLD)
	draw_string(font, Vector2(0, BTN_Y[idx] + 12), BUTTONS[idx],
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, 10,
		Palette.GOLD if selected else Palette.TEXT_DIM)


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, col)
