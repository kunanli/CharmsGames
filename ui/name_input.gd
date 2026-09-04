extends Node2D

# ─────────────────────────────────────────────────────────
# 玩家名稱輸入屏（純 _draw 繪製，不建 Control 節點）—— 街機虛擬鍵盤版。
# 疊在二級標題上的半透明 overlay，三層從下到上：
#   1. launcher 在 NAME_INPUT 模式仍會畫二級標題圖（底層）
#   2. 這裡蓋一層 50% 黑罩 —— 底下的二級畫面透得出來
#   3. 各遊戲自己的起名彈窗圖（RGBA，只有彈窗區域不透明，四周透出黑罩＋二級頁）
# 功能文字疊在最上層，位置與顏色對齊彈窗圖的版面。
#
# 街機裝置沒有鍵盤滑鼠，只有搖杆＋八顆按鍵，所以名字輸入完全靠
# 畫面中央的虛擬鍵盤完成（不依賴系統鍵盤、不彈系統軟鍵盤）：
#   ↑ ↓ ← →（搖杆）      移動選擇框；邊界夾住不繞行
#   A（或 Enter／空白）   確認：選字元 → 加入名字；選 OK → 確認名字
#   B（鍵盤 S）／鍵盤 ←   刪除最後一個字元；名字已空 → 中止起名（aborted，
#                         launcher 退回開局吃掉的那枚幣）—— 2026-09 鍵盤 B
#                         邏輯改到 S，鍵盤上的 ← 鈕與 B 同義
#   X                     清空全部（輸入框閃一下回饋）
#   Y                     預留，暫無功能（結構已留好，未來直接掛）
#   ESC                   取消 → cancelled（不退幣；退幣的中止入口是上面
#                         「名字為空時按 B／S／←」）
# 同時也吃手把事件（十字鍵／左搖杆／A B X Y），實機可直接用手把測。
#
# 名字規則：只收 A-Z / 0-9，最多 MAX_NAME_LEN（9）字；名字為空時
# 按 OK 只給回饋（輸入框閃＋OK 抖）不進下一階段。
# 開啟時名字為空（DEFAULT_NAME = ""，2026-09 起不再預填 pandora）、
# 預設選中第一格（"0"），玩家從頭輸入。
# 鍵盤是資料驅動的：KEY_ROWS 就是全部按鍵（字元／OK／DEL 三種格），
# 未來要加 SPACE／RANDOM 等按鍵，在對應列加一格字串＋一個分支即可。
# OK／DEL 與字元鍵共用同一套按鍵素材（普通／選中兩態），各佔兩格寬
# （資料一格、繪製橫向跨兩格），沒有特殊大鈕。
# ─────────────────────────────────────────────────────────

signal confirmed(name: String)
signal cancelled          # ESC 取消（不退幣，開發機逃生口）
signal aborted            # 中止起名：名字為空時按 B／S／鍵盤 ←（launcher 退幣）

const SCREEN := Vector2(480, 270)

## 鍵盤資料：每列一個陣列；字元格之外有兩種功能格 —— DEL（回退，與 B
## 同義，畫成像素 ←）與 OK（確認名字），都排在最後一列、**各佔兩格寬**
## （選擇框裡是一格，繪製時橫向跨兩格：6 格字元＋2 寬鍵＝10 欄，與上面
## 三列對齊）。
const KEY_ROWS: Array = [
	["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"],
	["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"],
	["K", "L", "M", "N", "O", "P", "Q", "R", "S", "T"],
	["U", "V", "W", "X", "Y", "Z", "DEL", "OK"],
]
const OK_CELL := "OK"
const DEL_CELL := "DEL"   # 回退鈕：刪最後一碼；名字為空時＝中止起名
const MAX_NAME_LEN := 9

## 起名屏開啟時輸入框預設的初始名字。2026-09 起為空字串：不再預填
## pandora，玩家一律從頭輸入。要恢復預填就改這裡（A-Z／0-9、≤MAX_NAME_LEN）。
const DEFAULT_NAME := ""

## 鍵盤區：1920×1080 美術座標 (830, 519) 590×275 ÷ 4 → 邏輯座標。
## 這塊粉紅色區域畫在起名彈窗圖上，所有按鍵必須落在裡面。
const KEY_AREA := Rect2(207.5, 129.75, 147.5, 68.75)
const KEY_SIZE := 14.0           # 按鍵素材 64×64 美術 px，微縮後 10 顆才放得下一列
const KEY_GAP_X := 0.8
const KEY_GAP_Y := 2.4
# OK／DEL 2026-09 起與字元鍵同尺寸同素材（原「金色大鈕＋像素愛心」已拆）。

## 各款按鍵素材（普通／選中，美術畫的 64×64）—— 由 launcher 傳的 game_id 決定。
const BTN_TEX := {
	"catch": [
		"res://assets/title/Naming/NamingKeyboard/catch_btn.png",
		"res://assets/title/Naming/NamingKeyboard/catch_btn_chosen.png",
	],
	"fishing": [
		"res://assets/title/Naming/NamingKeyboard/fishing_btn.png",
		"res://assets/title/Naming/NamingKeyboard/fishing_btn_chosen.png",
	],
	"seeker": [
		"res://assets/title/Naming/NamingKeyboard/seeker_btn.png",
		"res://assets/title/Naming/NamingKeyboard/seeker_btn_chosen.png",
	],
}

## 像素左箭頭（5×5）：DEL 鈕的圖示。PixelFont 不保證有「←」字形，
## 直接用色塊畫，跟字元文字一樣穩。
const ARROW_LEFT := [
	[0, 0, 1, 0, 0],
	[0, 1, 0, 0, 0],
	[1, 1, 1, 1, 1],
	[0, 1, 0, 0, 0],
	[0, 0, 1, 0, 0],
]

var title_image: Texture2D       # 各遊戲的起名彈窗圖（RGBA，彈窗區域不透明）
var game_id := ""                # launcher 傳入，決定用哪組按鍵素材

var _name := DEFAULT_NAME       # 目前輸入的名字（2026-09 起預設為空）
var _sel_row: int = 0           # 選擇框位置：selected_key = KEY_ROWS[_sel_row][_sel_col]
var _sel_col: int = 0           # 預設選中第一格（"0"），玩家從頭輸入
var _dir_held := {               # 搖杆／按鍵的按住狀態（只在上升緣動作）
	"up": false, "down": false, "left": false, "right": false,
}
var _blink := 0.0
var _flash := 0.0                # 輸入框閃爍（滿字／空名按 OK／清空 的回饋）
var _ok_shake := 0.0             # OK 抖動（空名按 OK 的回饋）

var _btn: Texture2D              # 普通按鍵底圖
var _btn_chosen: Texture2D       # 選中按鍵底圖（金色）
var _grid_origin := Vector2.ZERO # 鍵盤格子左上角（_ready 依 KEY_AREA 計算）


func _ready() -> void:
	var paths: Array = BTN_TEX.get(game_id, BTN_TEX["catch"])
	_btn = load(paths[0])
	_btn_chosen = load(paths[1])
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 格子總寬高（10 格×KEY_SIZE + 9 個間隙），在粉紅鍵盤區內置中
	var grid_w := 10.0 * KEY_SIZE + 9.0 * KEY_GAP_X
	var grid_h := KEY_ROWS.size() * KEY_SIZE + (KEY_ROWS.size() - 1.0) * KEY_GAP_Y
	_grid_origin = Vector2(
		KEY_AREA.position.x + (KEY_AREA.size.x - grid_w) * 0.5,
		KEY_AREA.position.y + (KEY_AREA.size.y - grid_h) * 0.5)


func _process(delta: float) -> void:
	_blink += delta
	if _flash > 0.0:
		_flash -= delta
	if _ok_shake > 0.0:
		_ok_shake -= delta
	queue_redraw()


# ── 輸入：鍵盤事件（街機按鍵編碼成鍵碼，與三款遊戲同一套）＋手把 ──

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_on_key(event as InputEventKey)
	elif event is InputEventJoypadButton:
		_on_joy_button(event as InputEventJoypadButton)
	elif event is InputEventJoypadMotion:
		_on_joy_motion(event as InputEventJoypadMotion)


func _on_key(key: InputEventKey) -> void:
	if key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.pressed:
		match key.keycode:
			KEY_UP:
				_move("up", true)
			KEY_DOWN:
				_move("down", true)
			KEY_LEFT:
				_move("left", true)
			KEY_RIGHT:
				_move("right", true)
			KEY_A, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_confirm()
			KEY_S:
				_delete()               # 街機 B（2026-09 鍵盤 B 邏輯改到 S）
			KEY_X:
				_clear()
			KEY_Y:
				pass                    # 預留：未來功能掛這裡
			KEY_ESCAPE:
				cancelled.emit()
	else:
		match key.keycode:
			KEY_UP: _move("up", false)
			KEY_DOWN: _move("down", false)
			KEY_LEFT: _move("left", false)
			KEY_RIGHT: _move("right", false)


func _on_joy_button(btn: InputEventJoypadButton) -> void:
	get_viewport().set_input_as_handled()
	if btn.pressed:
		match btn.button_index:
			JOY_BUTTON_A:
				_confirm()
			JOY_BUTTON_B:
				_delete()
			JOY_BUTTON_X:
				_clear()
			JOY_BUTTON_Y:
				pass                    # 預留
			JOY_BUTTON_DPAD_UP:
				_move("up", true)
			JOY_BUTTON_DPAD_DOWN:
				_move("down", true)
			JOY_BUTTON_DPAD_LEFT:
				_move("left", true)
			JOY_BUTTON_DPAD_RIGHT:
				_move("right", true)
	else:
		# 十字鍵的釋放也要交回給 _move 清掉按住狀態，否則再按會被邊沿檢測吞掉
		match btn.button_index:
			JOY_BUTTON_DPAD_UP: _move("up", false)
			JOY_BUTTON_DPAD_DOWN: _move("down", false)
			JOY_BUTTON_DPAD_LEFT: _move("left", false)
			JOY_BUTTON_DPAD_RIGHT: _move("right", false)


func _on_joy_motion(mot: InputEventJoypadMotion) -> void:
	# 只有左搖杆（0/1）走軸事件；十字鍵在 Godot 4 是按鈕（JOY_BUTTON_DPAD_*）
	var value := 0.0
	match mot.axis:
		JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
			value = mot.axis_value
		_:
			return
	get_viewport().set_input_as_handled()
	if absf(value) < 0.5:
		if mot.axis == JOY_AXIS_LEFT_X:
			_move("left", false)
			_move("right", false)
		else:
			_move("up", false)
			_move("down", false)
		return
	if mot.axis == JOY_AXIS_LEFT_X:
		_move("right", value > 0.0)
		_move("left", value < 0.0)
	else:
		_move("down", value > 0.0)
		_move("up", value < 0.0)


## 移動選擇框。pressed=true 是按下／推入，false 是放開；只在上升緣動作，
## 按住不會連發。邊界規則：不繞行 —— 第一列再上、最左列再左、最右列再右
## 都停在原位；上下換列時直行對齊，目標列比較短就夾到該列最後一格。
func _move(dir: String, pressed: bool) -> void:
	if pressed == _dir_held[dir]:
		return
	_dir_held[dir] = pressed
	if not pressed:
		return
	AudioManager.play_sfx("ui_select")   # 選擇框移動（鍵盤／手把共用入口）
	match dir:
		"up":
			_sel_row = maxi(_sel_row - 1, 0)
			_sel_col = mini(_sel_col, KEY_ROWS[_sel_row].size() - 1)
		"down":
			_sel_row = mini(_sel_row + 1, KEY_ROWS.size() - 1)
			_sel_col = mini(_sel_col, KEY_ROWS[_sel_row].size() - 1)
		"left":
			_sel_col = maxi(_sel_col - 1, 0)
		"right":
			_sel_col = mini(_sel_col + 1, KEY_ROWS[_sel_row].size() - 1)


## A（或 Enter／空白）：目前格子是字元就加進名字，DEL 就回退，OK 就確認。
## 名字滿 9 字或空名按 OK 時，只給回饋（輸入框閃／OK 抖）不動作。
func _confirm() -> void:
	var cell: String = KEY_ROWS[_sel_row][_sel_col]
	if cell == DEL_CELL:
		_delete()
		return
	if cell == OK_CELL:
		if _name.is_empty():
			_flash = 0.4
			_ok_shake = 0.4
		else:
			AudioManager.play_sfx("ui_confirm")   # OK 確認名字
			confirmed.emit(_name)
		return
	if _name.length() >= MAX_NAME_LEN:
		_flash = 0.2
		return
	AudioManager.play_sfx("ui_confirm")   # 選字確認
	_name += cell
	_advance()


## 輸入成功後自動移到下一個可輸入的位置（跳過 OK 與 DEL，到底繞回第一格）。
func _advance() -> void:
	var r := _sel_row
	var c := _sel_col + 1
	while true:
		if c >= KEY_ROWS[r].size():
			r += 1
			c = 0
			if r >= KEY_ROWS.size():
				r = 0
		if KEY_ROWS[r][c] != OK_CELL and KEY_ROWS[r][c] != DEL_CELL:
			break
		c += 1
	_sel_row = r
	_sel_col = c


## B（鍵盤 S）／鍵盤 ← 鈕：刪掉最後一個字元。名字已空 → 中止起名
## （aborted），launcher 會退回開局閘門吃掉的那枚幣並回二級標題 ——
## 這是街機端唯一的中止入口（ESC 只是開發機鍵盤的逃生口，街機沒有 ESC）。
func _delete() -> void:
	if _name.is_empty():
		aborted.emit()
		return
	_name = _name.substr(0, _name.length() - 1)


## X：一次清空；清掉時輸入框閃一下。名字本來就是空的就沒效果。
func _clear() -> void:
	if _name.is_empty():
		return
	_name = ""
	_flash = 0.3


# ── 繪製 ─────────────────────────────────────────────────

func _draw() -> void:
	# 50% 黑罩：底下是 launcher 畫的二級標題圖，透出一部分當背景
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.0, 0.0, 0.0, 0.5))
	# 起名彈窗圖（RGBA）：只有彈窗區域不透明，鋪滿畫 = 彈窗浮在黑罩上
	if title_image != null:
		draw_texture_rect(title_image, Rect2(Vector2.ZERO, SCREEN), false)
	var font := ThemeDB.fallback_font
	_draw_name(font)
	_draw_keyboard()
	#_center("ARROWS MOVE   A CONFIRM   B DELETE   X CLEAR   ESC CANCEL",
	#	226, 8, Palette.TEXT)


## 名字欄：沿用既有版面（NAME: 標籤畫在彈窗圖上），文字＋底線＋閃爍游標。
## 滿字／空名按 OK／清空時整行閃 WARN 色當回饋。
func _draw_name(font: Font) -> void:
	var col := Palette.WARN if _flash > 0.0 else Palette.NIGHT
	var size := font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var left := 305.0 - size.x * 0.5
	draw_string(font, Vector2(left, 110), _name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	draw_line(Vector2(left - 6, 112), Vector2(left + size.x + 6, 112), Palette.NIGHT, 0.0)
	if fmod(_blink, 0.8) < 0.4:
		draw_rect(Rect2(left + size.x + 4, 100, 6, 12), Palette.MOON)


func _draw_keyboard() -> void:
	for row in KEY_ROWS.size():
		var n_cols: int = KEY_ROWS[row].size()
		for col in n_cols:
			var cell: String = KEY_ROWS[row][col]
			var selected := row == _sel_row and col == _sel_col
			var rect := _cell_rect(row, col)
			if cell == OK_CELL and _ok_shake > 0.0:
				rect.position.x += sin(_ok_shake * 70.0) * 2.0   # 空名按 OK 的抖動
			# OK／DEL 與字元鍵同一套素材：未選中普通底、選中金色底＋WARN 框
			draw_texture_rect(_btn_chosen if selected else _btn, rect, false)
			if selected:
				draw_rect(rect, Palette.WARN, false)
			if cell == DEL_CELL:
				_draw_arrow_left(rect)
			else:
				_center_in(rect, cell, 8, Palette.NIGHT)


## 格子矩形。DEL／OK 是寬鍵：橫向跨兩格（含中間間隙）。寬鍵在資料裡
## 只佔一格索引，繪製起點要補回「前面每顆寬鍵多佔的那一欄」（最後一列：
## DEL 起點在第 6 欄、OK 起點在第 8 欄，兩顆剛好補滿 10 欄）。
func _cell_rect(row: int, col: int) -> Rect2:
	var origin_col := col
	for i in col:
		if _is_wide(KEY_ROWS[row][i]):
			origin_col += 1
	var rect := Rect2(
		_grid_origin.x + origin_col * (KEY_SIZE + KEY_GAP_X),
		_grid_origin.y + row * (KEY_SIZE + KEY_GAP_Y),
		KEY_SIZE, KEY_SIZE)
	if _is_wide(KEY_ROWS[row][col]):
		rect.size.x = KEY_SIZE * 2.0 + KEY_GAP_X
	return rect


## DEL／OK 是寬鍵（橫向佔兩格）。
func _is_wide(cell: String) -> bool:
	return cell == OK_CELL or cell == DEL_CELL


## DEL 鈕的像素左箭頭：5×5 色塊置中（字元格畫文字、這格畫圖示）。
func _draw_arrow_left(rect: Rect2) -> void:
	var pos := rect.position + ((rect.size - Vector2(5.0, 5.0)) * 0.5).floor()
	for y in ARROW_LEFT.size():
		var n_x: int = ARROW_LEFT[y].size()
		for x in n_x:
			if ARROW_LEFT[y][x] == 1:
				draw_rect(Rect2(pos + Vector2(x, y), Vector2.ONE), Palette.NIGHT)


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, col)


## 在指定矩形內水平垂直置中畫文字（鍵盤格／OK 用）。
func _center_in(rect: Rect2, text: String, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font,
		Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + size * 0.30),
		text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, col)
