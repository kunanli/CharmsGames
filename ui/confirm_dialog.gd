extends Node2D

# ─────────────────────────────────────────────────────────
# 通用 A／B 確認彈窗（Modal Overlay）：半透明黑罩蓋住底層畫面，中間一個
# 小框顯示 message。A（鍵盤 A／手柄 A；Enter／空白同義）確認、B（鍵盤 S／
# 手柄 B）或 ESC 取消。街機 A／B 綁定見 shared/arcade_input.gd；手柄按鈕
# 事件不進 _unhandled_key_input，本檔走 _unhandled_input。
#
# 呼叫端在 add_child() 前用 set("message", ...) 設文案、接 confirmed／
# cancelled 兩個信號；節點存在期間呼叫端自己不處理任何按鍵（見
# launcher.gd 的 _confirm_modal 檢查 —— 與管理員密碼彈窗同一套攔截）。
# 目前唯一使用點：launcher SETTING 二級的 TURN OFF WINDOWS（確認後關機）。
#
# 文案一律英文：PixelFont.ttf 沒有簡體中文字形，中文會畫成豆腐塊
# （硬規則「HUD 文字一律用英文」）。
# ─────────────────────────────────────────────────────────

signal confirmed
signal cancelled

const SCREEN := Vector2(480, 270)

## 提示文案（單行），呼叫端在 add_child() 前用 set() 指定。
var message := "CONFIRM?"

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var pad := event as InputEventJoypadButton
	var stick := event as InputEventJoypadMotion
	if key == null and pad == null and stick == null:
		return
	if key != null and (key.echo or not key.pressed):
		return
	get_viewport().set_input_as_handled()

	if ArcadeInput.pressed(event, ArcadeInput.ACTION_A) \
			or (key != null and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]):
		AudioManager.play_sfx("ui_confirm")
		confirmed.emit()
	elif ArcadeInput.pressed(event, ArcadeInput.ACTION_B) \
			or (key != null and key.keycode == KEY_ESCAPE):
		cancelled.emit()

func _draw() -> void:
	# 變暗背景蓋住底下的 SETTING 選單，凸顯彈窗
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(Palette.BG, 0.82))

	var font := ThemeDB.fallback_font
	var box := Rect2(130, 104, 220, 62)
	draw_rect(box, Palette.NIGHT)
	draw_rect(box, Palette.WALL, false, 1.0)
	draw_string(font, Vector2(box.position.x, box.position.y + 20.0), message,
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 10, Palette.TEXT)
	draw_string(font, Vector2(box.position.x, box.position.y + 44.0),
		"A CONFIRM    B CANCEL",
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 8, Palette.TEXT_DIM)
