extends Node2D

# ─────────────────────────────────────────────────────────
# 局終 Game Over 動畫（三款遊戲共用一份）。
#
# 背景是保留在場景中的遊戲節點：launcher 開本界面時把遊戲暫停
# （process_mode = DISABLED，畫面定格在最後一幀）、**不釋放**，
# 動畫播完進排行榜前才釋放 —— 畫面停留在遊戲場景，不會回退到
# 二級標題。遊戲自己的 RESULT 壓暗遮罩仍會畫（遊戲節點還在畫）。
#
# 本檔**只**畫 GAME OVER／TIME UP 文字的淡入淡出：
#   0.35 秒淡入 → 全亮停留至第 1 秒 → 0.3 秒淡出 → 自動進排行榜。
# 不顯示分數／名字／排名 —— 那些交給排行榜面板。
# ─────────────────────────────────────────────────────────

signal leaderboard_requested

const SCREEN := Vector2(480, 270)

const FADE_IN := 0.35          # 淡入時長
const HOLD_UNTIL := 1.0        # 全亮停留到這個時刻（從開始算起）
const FADE_OUT := 0.30         # 淡出時長
const TOTAL := HOLD_UNTIL + FADE_OUT   # 播完自動進排行榜

const TEXT_SIZE := 22          # 與遊戲原 RESULT 大字同尺寸
const TEXT_Y := 96.0           # 基線，與遊戲原 RESULT 大字同位置

var game_over := false         # true 顯示 GAME OVER，false 顯示 TIME UP

var _elapsed := 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= TOTAL:
		set_process(false)
		leaderboard_requested.emit()
		return
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var title := "GAME OVER" if game_over else "TIME UP"
	var col := Palette.WARN if game_over else Palette.GOLD
	var alpha := 0.0
	if _elapsed < FADE_IN:
		alpha = _elapsed / FADE_IN
	elif _elapsed < HOLD_UNTIL:
		alpha = 1.0
	else:
		alpha = 1.0 - (_elapsed - HOLD_UNTIL) / FADE_OUT
	draw_string(font, Vector2(0, TEXT_Y), title,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, TEXT_SIZE,
		Color(col, alpha))
