extends Node2D

# ─────────────────────────────────────────────────────────
# 玩家名稱輸入屏（純 _draw 繪製，不建 Control 節點）。
# 疊在二級標題上的半透明 overlay，三層從下到上：
#   1. launcher 在 NAME_INPUT 模式仍會畫二級標題圖（底層）
#   2. 這裡蓋一層 50% 黑罩 —— 底下的二級畫面透得出來
#   3. 各遊戲自己的起名彈窗圖（RGBA，只有彈窗區域不透明，四周透出黑罩＋二級頁）
# 功能文字疊在最上層。
# 只收可印字元（A-Z / 0-9 / 空白），統一英文大寫 —— 專案 HUD 一律英文。
# 名字清洗統一走 CurrentPlayerSession.sanitize_player_name()。
#
# 按鍵：
#   A-Z / 0-9 / SPACE  輸入（最多 CurrentPlayerSession.MAX_NAME_LEN 字）
#   BACKSPACE          刪除
#   ← →                切換難度（EASY / HARD 兩檔）
#   ENTER              確認 → confirmed(名字, 難度)；空名字只提示不發
#   ESC                取消 → cancelled
# ─────────────────────────────────────────────────────────

signal confirmed(name: String, difficulty_id: String, difficulty_name: String)
signal cancelled

const SCREEN := Vector2(480, 270)

const DIFF_IDS := ["easy", "hard"]
const DIFF_NAMES := ["EASY", "HARD"]

var title_image: Texture2D       # 各遊戲的起名彈窗圖（RGBA，彈窗區域不透明）

var _name := ""
var _difficulty := 0             # 0 = EASY、1 = HARD（起名界面選，只當標籤記錄）
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
		KEY_LEFT, KEY_RIGHT:
			_difficulty = 1 - _difficulty
		KEY_ENTER, KEY_KP_ENTER:
			var clean := CurrentPlayerSession.sanitize_player_name(_name)
			if clean.is_empty():
				_error = "NAME REQUIRED"
				_error_timer = 1.2
			else:
				confirmed.emit(clean, DIFF_IDS[_difficulty], DIFF_NAMES[_difficulty])
		_:
			var u := key.unicode
			if u < 32 or u > 126:
				return                # 非可印字元（含中文輸入法）不收
			if _name.length() >= CurrentPlayerSession.MAX_NAME_LEN:
				return
			_name += String.chr(u).to_upper()


func _draw() -> void:
	# 50% 黑罩：底下是 launcher 畫的二級標題圖，透出一部分當背景
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.0, 0.0, 0.0, 0.5))
	# 起名彈窗圖（RGBA）：只有彈窗區域不透明，鋪滿畫 = 彈窗浮在黑罩上
	if title_image != null:
		draw_texture_rect(title_image, Rect2(Vector2.ZERO, SCREEN), false)
	var font := ThemeDB.fallback_font

	#_center("ENTER YOUR NAME", 72, 16, Palette.GOLD)
	#_center("THIS NAME GOES ON THE LEADERBOARD", 92, 8, Palette.TEXT_DIM)

	# 輸入框：文字 + 底線 + 閃爍游標
	var size := font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var left := 305.0 - size.x * 0.5
	draw_string(font, Vector2(left, 110), _name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.NIGHT)
	draw_line(Vector2(left - 6, 112), Vector2(left + size.x + 6, 112), Palette.TEXT, 0.0)
	if fmod(_blink, 0.8) < 0.4:
		draw_rect(Rect2(left + size.x + 4, 100, 6, 12), Palette.MOON)

	# 難度選擇：← → 切換，選中項用 [ ] 標出
	var diff_text := "                           "
	for i in DIFF_NAMES.size():
		diff_text += ("[%s]  " if i == _difficulty else "%s  ") % DIFF_NAMES[i]
	_center(diff_text, 170, 10, Palette.BG)

	_center("A-Z 0-9 SPACE  BACKSPACE  ENTER OK  ESC CANCEL", 226, 8, Palette.BG)
	if _error != "":
		_center(_error, 168, 10, Palette.WARN)


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, col)
