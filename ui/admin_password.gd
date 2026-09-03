extends Node2D

# ─────────────────────────────────────────────────────────
# 管理員密碼界面（二級標題按住 A＋B 三秒進入，Modal Overlay）。
# 密碼不是文字，是方向指令序列「上上下下左右左右」（↑ ↑ ↓ ↓ ← → ← →）：
# 玩家每按一個方向鍵就輸入一位（共 8 位），全部輸完按 A 確認 ——
# 正確 → succeeded（launcher 回一級管理員界面）；錯誤 → 清空重填。
# 方向鍵以外不收任何字元，所以不需要遮蔽輸入。
#
# 按鍵（輸入優先級 Level 1，全吃；街機 A／B 綁定見 shared/arcade_input.gd，
# 手柄按鈕事件不進 _unhandled_key_input，本檔改走 _unhandled_input）：
#   ↑ ↓ ← →    輸入一位（超過 8 位不收）；鍵盤方向鍵＋手柄左搖杆上下左右
#               （搖桿過 ±0.5 死區輸入一位、推住不連發，與起名屏同一檔）
#   B           刪除最後一位；沒輸入內容時等同 ESC（取消回二級）
#               （B＝鍵盤 S／手柄 B，2026-09 鍵盤 B 邏輯改到 S）
#   A           確認（未輸滿 8 位只給提示；A＝鍵盤 A／手柄 A）
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

## 方向名稱 → 密碼位用的 KEY_* 鍵碼（手柄搖桿與鍵盤方向鍵共用同一管道）。
const DIR_KEYS := {
	"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
}

const SCREEN := Vector2(480, 270)

var _input: Array[int] = []   # 已輸入的方向（KEY_* 鍵碼，順序即輸入順序）
var _dir_held := {            # 手柄左搖杆四方向的推住狀態（邊沿觸發用）
	"up": false, "down": false, "left": false, "right": false,
}
var _error := ""
var _error_timer := 0.0


func _process(delta: float) -> void:
	if _error_timer > 0.0:
		_error_timer -= delta
		if _error_timer <= 0.0:
			_error = ""
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# 街機 A／B 走 InputMap action（鍵盤 A·S／手柄 A·B，見 shared/arcade_input.gd）；
	# 密碼方向位吃鍵盤方向鍵＋手柄左搖杆（_stick_direction）；ESC 維持鍵盤。
	# 滑鼠等事件不收。
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
		_confirm()
	elif ArcadeInput.pressed(event, ArcadeInput.ACTION_B):
		# B（鍵盤 S／手柄 B）：刪除最後一位；沒輸入內容時等同 ESC（取消回二級）
		if _input.is_empty():
			cancelled.emit()
		else:
			_input.pop_back()
	elif stick != null:
		_stick_direction(stick)
	elif key != null:
		match key.keycode:
			KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
				if _input.size() < PASSWORD_LEN:
					_input.append(key.keycode)
			KEY_ESCAPE:
				cancelled.emit()


## 手柄左搖杆 → 輸入一位方向（與鍵盤 ↑↓←→ 同一管道、存同一組 KEY_* 鍵碼，
## 所以與 PASSWORD 的比對不用改）。過 ±0.5 死區的上升緣輸入一位，推住不
## 連發、回中立區重置後才允許下一次（與起名屏的搖桿判定同一檔）。斜推會
## 先後越過兩個軸、輸入兩位 —— 想輸哪個方向就單純推哪邊。
func _stick_direction(mot: InputEventJoypadMotion) -> void:
	match mot.axis:
		JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
			pass
		_:
			return              # 只有左搖杆；右搖杆／扳機不收
	var dir := ""
	if absf(mot.axis_value) < 0.5:
		# 回中立區：把這個軸的兩個方向狀態清掉，允許下一次輸入
		if mot.axis == JOY_AXIS_LEFT_X:
			_dir_held["left"] = false
			_dir_held["right"] = false
		else:
			_dir_held["up"] = false
			_dir_held["down"] = false
		return
	if mot.axis == JOY_AXIS_LEFT_X:
		dir = "right" if mot.axis_value > 0.0 else "left"
	else:
		dir = "down" if mot.axis_value > 0.0 else "up"
	if _dir_held[dir]:
		return                  # 這個方向已經在推，不重複輸入
	_dir_held[dir] = true
	if _input.size() < PASSWORD_LEN:
		_input.append(DIR_KEYS[dir])


## A 確認：未輸滿 8 位只給提示；滿了且與 PASSWORD 一致 → 成功，
## 不一致 → 清空重填。
func _confirm() -> void:
	if _input.size() < PASSWORD_LEN:
		_error = "%d DIRECTIONS NEEDED" % PASSWORD_LEN
		_error_timer = 1.2
		return
	if _input == PASSWORD:
		AudioManager.play_sfx("ui_confirm")   # 密碼正確
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

	draw_string(font, Vector2(140, 162), "A CONFIRM   B DELETE/BACK   ESC CANCEL",
		HORIZONTAL_ALIGNMENT_CENTER, 200, 8, Palette.TEXT_DIM)
	if _error != "":
		draw_string(font, Vector2(240, 172), _error,
			HORIZONTAL_ALIGNMENT_CENTER, 200, 8, Palette.WARN)
