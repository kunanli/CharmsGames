extends Node2D

# ─────────────────────────────────────────────────────────
# 管理員的排行榜清除選單（一級標題的 Modal Overlay，結構鏡像
# admin_password.gd）。launcher 在一級標題按 B、對「當前選中的遊戲」
# 開啟，add_child 前設定 game_id / game_name（一級標題的短名）。
#
# 兩個狀態：
#   SELECT  五種清除規則，← → 循環選擇（選中的高亮）、A 進二次確認、
#           B / ESC 取消回一級標題
#   CONFIRM DELETE <GAME> SCORE DATA? ＋ 所選規則，A 執行刪除、
#           B / ESC 回 SELECT
#
# 規則（LeaderboardManager.ClearRule，索引與 RULES 順序一一對應）：
#   LAST 1 HOUR  現在往前 1 小時內
#   LAST 4 HOURS 現在往前 4 小時內
#   TODAY        今天 00:00 之後
#   BEFORE TODAY 今天之前（保留今天）
#   ALL DATA     這款遊戲的全部記錄
#
# 執行成功發 cleared（launcher 關閉選單、在一級標題顯示成功提示）；
# 取消發 cancelled（launcher 關閉選單，什麼都不做）。刪除只影響
# 設進來的 game_id，不跨遊戲 —— 責任在 LeaderboardManager.clear_records。
# ─────────────────────────────────────────────────────────

signal cleared
signal cancelled

const SCREEN := Vector2(480, 270)

## 五種規則的顯示名。順序對應 LeaderboardManager.ClearRule，不能調換。
const RULES := [
	"LAST 1 HOUR",
	"LAST 4 HOURS",
	"TODAY",
	"BEFORE TODAY",
	"ALL DATA",
]

const BOX := Rect2(118, 30, 244, 200)
const OPT_Y0 := 80.0      # 選項第一行文字基線
const OPT_DY := 24.0

var game_id := ""
var game_name := ""       # MAZE / FISHING / CATCH

var _rule := 0            # 選中的規則（ClearRule 索引）
var _confirm := false     # 二次確認中


func _unhandled_input(event: InputEvent) -> void:
	# 街機 A／B 走 InputMap action（鍵盤 A·S／手柄 A·B，見 shared/arcade_input.gd）；
	# ← → 循環選擇與 ESC 維持鍵盤。手柄軸／滑鼠等事件不收。
	var key := event as InputEventKey
	var pad := event as InputEventJoypadButton
	if key == null and pad == null:
		return
	if key != null and (key.echo or not key.pressed):
		return
	get_viewport().set_input_as_handled()

	var pressed_a := ArcadeInput.pressed(event, ArcadeInput.ACTION_A) \
		or (key != null and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE])
	var pressed_b := ArcadeInput.pressed(event, ArcadeInput.ACTION_B) \
		or (key != null and key.keycode in [KEY_S, KEY_ESCAPE])

	if not _confirm:
		if key != null and key.keycode == KEY_LEFT:
			_rule = (_rule + RULES.size() - 1) % RULES.size()
			AudioManager.play_sfx("ui_select")
		elif key != null and key.keycode == KEY_RIGHT:
			_rule = (_rule + 1) % RULES.size()
			AudioManager.play_sfx("ui_select")
		elif pressed_a:
			AudioManager.play_sfx("ui_confirm")   # 進二次確認
			_confirm = true
		elif pressed_b:
			cancelled.emit()
	else:
		if pressed_a:
			AudioManager.play_sfx("ui_confirm")   # 執行刪除
			LeaderboardManager.clear_records(game_id, _rule)
			cleared.emit()
		elif pressed_b:
			_confirm = false
	queue_redraw()


func _draw() -> void:
	# 變暗背景蓋住底下的一級標題，凸顯 Modal（與密碼彈窗同一套）
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(Palette.BG, 0.82))

	var font := ThemeDB.fallback_font
	draw_rect(BOX, Palette.NIGHT)
	draw_rect(BOX, Palette.WALL, false, 1.0)

	if not _confirm:
		_center("%s SCORE MANAGEMENT" % game_name, 54, 12, Palette.GOLD)
		for i in RULES.size():
			var y := OPT_Y0 + i * OPT_DY
			var selected := i == _rule
			if selected:
				draw_rect(Rect2(BOX.position.x + 8, y - 14, BOX.size.x - 16, 18),
					Color(Palette.WALL_DARK, 0.55))
			draw_string(font, Vector2(BOX.position.x + 20, y), RULES[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Palette.GOLD if selected else Palette.TEXT)
		_center("← → SELECT    A CONFIRM    B BACK", 240, 8, Palette.TEXT_DIM)
	else:
		_center("DELETE %s SCORE DATA?" % game_name, 62, 12, Palette.WARN)
		_center("RULE:", 92, 10, Palette.TEXT_DIM)
		_center(RULES[_rule], 114, 12, Palette.GOLD)
		_center("A : CONFIRM", 152, 10, Palette.TEXT)
		_center("B : CANCEL", 172, 10, Palette.TEXT_DIM)


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, col)
