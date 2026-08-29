extends Node2D

# ─────────────────────────────────────────────────────────
# 管理員密碼界面（二級標題按住 A＋B 三秒進入，Modal Overlay）。
# 密碼不是文字，是方向指令序列「上上下下左右左右」（↑ ↑ ↓ ↓ ← → ← →）：
# 玩家每按一個方向鍵就輸入一位（共 8 位），全部輸完按 A 確認 ——
# 正確 → succeeded（launcher 回一級管理員界面）；錯誤 → 清空重填。
# 方向鍵以外不收任何字元，所以不需要遮蔽輸入。
#
# 按鍵（輸入優先級 Level 1，全吃）：
#   ↑ ↓ ← →    輸入一位（超過 8 位不收）
#   B           刪除最後一位
#   A           確認（未輸滿 8 位只給提示）
#   ESC         取消 → cancelled（回二級標題，不回一級）
#
# launcher 在此節點存在期間不處理任何按鍵（見 launcher.gd 的
# _password_modal 檢查），事件是否被標記 handled 都不影響攔截。
# ─────────────────────────────────────────────────────────

signal succeeded
signal cancelled

## 正確密碼：上上下下左右左右，8 個方向鍵碼（順序敏感）。
const PASSWORD := [KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN,
	KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT]
const PASSWORD_LEN := 8

## 方向鍵 → 顯示符號（內建字型有 ↑ ↓ ← → 字形，見 launcher 一級標題的用法）。
const DIR_CHARS := {
	KEY_UP: "↑",
	KEY_DOWN: "↓",
	KEY_LEFT: "←",
	KEY_RIGHT: "→",
}

const SCREEN := Vector2(480, 270)

var _input: Array[int] = []   # 已輸入的方向（KEY_* 鍵碼，順序即輸入順序）
var _error := ""
var _error_timer := 0.0


func _process(delta: float) -> void:
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
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			if _input.size() < PASSWORD_LEN:
				_input.append(key.keycode)
		KEY_B:
			if not _input.is_empty():
				_input.pop_back()
		KEY_A, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm()
		KEY_ESCAPE:
			cancelled.emit()


## A 確認：未輸滿 8 位只給提示；滿了且與 PASSWORD 一致 → 成功，
## 不一致 → 清空重填。
func _confirm() -> void:
	if _input.size() < PASSWORD_LEN:
		_error = "%d DIRECTIONS NEEDED" % PASSWORD_LEN
		_error_timer = 1.2
		return
	if _input == PASSWORD:
		succeeded.emit()
	else:
		_input.clear()
		_error = "WRONG PASSWORD"
		_error_timer = 1.2


func _draw() -> void:
	# 變暗背景蓋住底下的二級標題，凸顯 Modal
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(Palette.BG, 0.82))

	var font := ThemeDB.fallback_font

	# 彈窗框
	draw_rect(Rect2(140, 96, 200, 84), Palette.NIGHT)
	draw_rect(Rect2(140, 96, 200, 84), Palette.WALL, false, 1.0)
	draw_string(font, Vector2(140, 118), "ADMIN PASSWORD",
		HORIZONTAL_ALIGNMENT_CENTER, 200, 10, Palette.GOLD)

	# 8 個方向槽：已輸入的顯示方向符號、未輸入的顯示 _（底線）
	var base_x := 240.0 - PASSWORD_LEN * 8.0
	for i in PASSWORD_LEN:
		var filled := i < _input.size()
		var ch: String = DIR_CHARS[_input[i]] if filled else "_"
		draw_string(font, Vector2(base_x + i * 16.0, 142), ch,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Palette.TEXT if filled else Palette.TEXT_DIM)

	draw_string(font, Vector2(140, 162), "A CONFIRM   B DELETE   ESC CANCEL",
		HORIZONTAL_ALIGNMENT_CENTER, 200, 8, Palette.TEXT_DIM)
	if _error != "":
		draw_string(font, Vector2(240, 172), _error,
			HORIZONTAL_ALIGNMENT_CENTER, 200, 8, Palette.WARN)
