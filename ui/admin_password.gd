extends Node2D

# ─────────────────────────────────────────────────────────
# F3 管理員密碼彈窗（二級標題上的 Modal Overlay，結構鏡像 name_input.gd）。
# 只收可印字元、**保留大小寫**（密碼 admin / pandora 是小寫，不能像
# 起名屏那樣統一轉大寫）。輸入以 * 遮蔽顯示 —— 內建字型沒有 ●，
# 用 * 才不會變方框。
#
# 按鍵（輸入優先級 Level 1，全吃）：
#   可印字元           輸入（最多 MAX_LEN 字）
#   BACKSPACE          刪除
#   ENTER              確認 → 正確發 succeeded、錯誤清空留在框內
#   ESC                取消 → cancelled（回二級標題，不回一級）
#
# launcher 在此節點存在期間不處理任何按鍵（見 launcher.gd 的
# _password_modal 檢查），事件是否被標記 handled 都不影響攔截。
# ─────────────────────────────────────────────────────────

signal succeeded
signal cancelled

const MAX_LEN := 16
## 正確密碼。精確匹配，大小寫敏感。
const PASSWORDS := ["admin", "pandora"]

const SCREEN := Vector2(480, 270)

var _input := ""
var _blink := 0.0
var _error := ""
var _error_timer := 0.0


func _process(delta: float) -> void:
	_blink += delta
	if _error_timer > 0.0:
		_error_timer -= delta
		if _error_timer <= 0.0:
			_error = ""
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()

	match key.keycode:
		KEY_ESCAPE:
			cancelled.emit()
		KEY_BACKSPACE:
			if _input.length() > 0:
				_input = _input.substr(0, _input.length() - 1)
		KEY_ENTER, KEY_KP_ENTER:
			if _input.is_empty():
				_error = "PASSWORD REQUIRED"
				_error_timer = 1.2
			elif _input in PASSWORDS:
				succeeded.emit()
			else:
				# 錯誤：留在二級標題、清空重填，短提示
				_input = ""
				_error = "WRONG PASSWORD"
				_error_timer = 1.2
		_:
			var u := key.unicode
			if u < 33 or u > 126:
				return                # 非可印字元（含空白與中文輸入法）不收
			if _input.length() >= MAX_LEN:
				return
			_input += String.chr(u)  # 不轉大寫：密碼大小寫敏感


func _draw() -> void:
	# 變暗背景蓋住底下的二級標題，凸顯 Modal
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(Palette.BG, 0.82))

	var font := ThemeDB.fallback_font

	# 彈窗框
	draw_rect(Rect2(140, 96, 200, 84), Palette.NIGHT)
	draw_rect(Rect2(140, 96, 200, 84), Palette.WALL, false, 1.0)
	draw_string(font, Vector2(140, 118), "ADMIN PASSWORD",
		HORIZONTAL_ALIGNMENT_CENTER, 200, 10, Palette.GOLD)

	# 遮蔽輸入（*）+ 閃爍游標
	var masked := "*".repeat(_input.length())
	var size := font.get_string_size(masked, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var left := 240.0 - size.x * 0.5
	draw_string(font, Vector2(left, 142), masked,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.TEXT)
	if fmod(_blink, 0.8) < 0.4:
		draw_rect(Rect2(left + size.x + 4, 132, 6, 12), Palette.MOON)

	draw_string(font, Vector2(140, 162), "ENTER OK   ESC CANCEL",
		HORIZONTAL_ALIGNMENT_CENTER, 200, 8, Palette.TEXT_DIM)
	if _error != "":
		draw_string(font, Vector2(240, 172), _error,
			HORIZONTAL_ALIGNMENT_CENTER, 200, 8, Palette.WARN)
