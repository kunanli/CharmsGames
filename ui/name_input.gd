extends Node2D

# ─────────────────────────────────────────────────────────
# 玩家名稱輸入屏（純 _draw 繪製，不建 Control 節點）。
# 只收可印字元（A-Z / 0-9 / 空白），統一英文大寫 —— 專案 HUD 一律英文。
# 名字清洗統一走 CurrentPlayerSession.sanitize_player_name()。
#
# 按鍵：
#   A-Z / 0-9 / SPACE  輸入（最多 CurrentPlayerSession.MAX_NAME_LEN 字）
#   BACKSPACE          刪除
#   ENTER              確認 → confirmed(名字)；空名字只提示不發
#   ESC                取消 → cancelled
# ─────────────────────────────────────────────────────────

signal confirmed(name: String)
signal cancelled

const SCREEN := Vector2(480, 270)

var _name := ""
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
			if _name.length() > 0:
				_name = _name.substr(0, _name.length() - 1)
		KEY_ENTER, KEY_KP_ENTER:
			var clean := CurrentPlayerSession.sanitize_player_name(_name)
			if clean.is_empty():
				_error = "NAME REQUIRED"
				_error_timer = 1.2
			else:
				confirmed.emit(clean)
		_:
			var u := key.unicode
			if u < 32 or u > 126:
				return                # 非可印字元（含中文輸入法）不收
			if _name.length() >= CurrentPlayerSession.MAX_NAME_LEN:
				return
			_name += String.chr(u).to_upper()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Palette.BG)
	var font := ThemeDB.fallback_font

	_center("ENTER YOUR NAME", 72, 16, Palette.GOLD)
	_center("THIS NAME GOES ON THE LEADERBOARD", 92, 8, Palette.TEXT_DIM)

	# 輸入框：文字 + 底線 + 閃爍游標
	var size := font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var left := 240.0 - size.x * 0.5
	draw_string(font, Vector2(left, 118), _name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.TEXT)
	draw_line(Vector2(left - 6, 124), Vector2(left + size.x + 6, 124), Palette.WALL, 1.0)
	if fmod(_blink, 0.8) < 0.4:
		draw_rect(Rect2(left + size.x + 4, 108, 6, 12), Palette.MOON)

	_center("A-Z 0-9 SPACE  BACKSPACE  ENTER OK  ESC CANCEL", 140, 8, Palette.TEXT_DIM)
	if _error != "":
		_center(_error, 160, 10, Palette.WARN)


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, col)
