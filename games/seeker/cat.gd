class_name Cat
extends Node2D

# ─────────────────────────────────────────────────────────
# 暗影猫：格子移動 + 三種追擊個性（M3c）
#
# 三隻貓跑的是「同一套」移動規則，差別只在怎麼算目標格：
#
#   移動規則（跟小精靈的鬼一樣簡單，但意外地難纏）：
#     1. 每次抵達格子中心時，看四個方向哪些能走
#     2. 排除「回頭路」——不准原地掉頭，這是關鍵，
#        沒有這條規則的話貓會在原地來回抖動
#     3. 剩下的選項中，挑「走過去之後離目標最近」的那個
#     4. 死路才允許回頭
#
#   目標格算法：
#     CHASER   直追  目標 = 露娜所在格
#     AMBUSHER 預判  目標 = 露娜前方 4 格（會和直追貓自然形成夾擊）
#     WANDERER 遊蕩  目標 = 隨機走道格，但露娜靠近到 6 格內就撲上去
#
# 沒有路徑搜尋、沒有 A*。難纏感來自三隻貓從不同方向包夾，
# 不是來自單隻貓有多聰明。
# ─────────────────────────────────────────────────────────

enum Kind { CHASER, AMBUSHER, WANDERER }

const AMBUSH_LEAD := 4          # 預判貓瞄準露娜前方幾格
const WANDER_RETARGET := 2.5    # 遊蕩貓多久重抽一次目標（秒）
const WANDER_POUNCE := 6        # 遊蕩貓在幾格內會改成直追

const HOLD_ALPHA := 0.45        # 還沒登場時的半透明程度

var maze: Maze
var kind: Kind = Kind.CHASER
var speed := 60.0
var body_col := Palette.CAT
var fill_col := Color(0, 0, 0, 0)   # 只有遊蕩貓有填色
var home_cell := Vector2i.ZERO      # 出生格，每次重生都回到這裡
var release_delay := 0.0            # 出生後等幾秒才動，用來錯開三隻貓的登場

var cell := Vector2i.ZERO
var dir := Vector2i.ZERO
var target_cell := Vector2i.ZERO    # 由 update_target() 每幀算出來

var _hold := 0.0                    # 還要等幾秒才登場
var _wander_cell := Vector2i.ZERO   # 遊蕩貓目前晃去哪
var _wander_timer := 0.0
var _rng := RandomNumberGenerator.new()


## 設定個性。速度與外觀都跟著個性走，讓玩家一眼認得出是哪一隻。
##
## 顏色只能從色盤的三個暗影猫紫挑（美術規格書第三條，不准自己調中間色），
## 所以三隻的辨識度主要靠亮度與剪影，不是靠色相。反正玩家真正用來定位
## 威脅的是那雙黃眼睛 —— 那是全畫面唯一的暖色，三隻都有。
func configure(k: Kind, home: Vector2i, delay: float) -> void:
	kind = k
	home_cell = home
	release_delay = delay
	fill_col = Color(0, 0, 0, 0)
	match kind:
		Kind.CHASER:
			speed = 60.0
			body_col = Palette.CAT        # 身體主色：基準款，穩穩跟在屁股後面
		Kind.AMBUSHER:
			speed = 66.0
			body_col = Palette.CAT_GLOW   # 最亮的紫：最快，負責抄前面
		Kind.WANDERER:
			speed = 54.0
			body_col = Palette.CAT        # 最慢，靠填滿暗部色做出「潛伏」的重量感
			fill_col = Palette.CAT_DARK


func setup(m: Maze, start_cell: Vector2i) -> void:
	maze = m
	cell = start_cell
	position = maze.cell_center(cell)
	dir = Vector2i.ZERO
	target_cell = start_cell
	_hold = release_delay
	_wander_cell = start_cell
	_wander_timer = 0.0
	_rng.randomize()
	modulate.a = HOLD_ALPHA if _hold > 0.0 else 1.0


## 由 main.gd 每幀呼叫（只在 PLAYING 狀態）。三種個性各自算自己的目標格。
func update_target(player_cell: Vector2i, player_dir: Vector2i, delta: float) -> void:
	match kind:
		Kind.CHASER:
			target_cell = player_cell
		Kind.AMBUSHER:
			# 露娜站著不動時 player_dir 是零，這時自然退化成直追
			target_cell = _clamp_cell(player_cell + player_dir * AMBUSH_LEAD)
		Kind.WANDERER:
			_wander_timer -= delta
			if _wander_timer <= 0.0 or _wander_cell == cell:
				_wander_cell = maze.random_open_cell(_rng)
				_wander_timer = WANDER_RETARGET
			# 露娜晃進附近就放棄亂逛，直接撲上去
			if _cell_dist(cell, player_cell) <= WANDER_POUNCE:
				target_cell = player_cell
			else:
				target_cell = _wander_cell


func _process(delta: float) -> void:
	if maze == null:
		return

	# 登場前在出生格待命，畫面上以半透明表示還沒啟動
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			modulate.a = 1.0
		return

	if dir == Vector2i.ZERO:
		dir = _choose_dir()
		if dir == Vector2i.ZERO:
			return

	var target := maze.cell_center(cell + dir)
	var to_target := target - position
	var step := speed * delta

	if to_target.length() <= step:
		position = target
		cell += dir
		dir = _choose_dir()
	else:
		position += to_target.normalized() * step


func _choose_dir() -> Vector2i:
	# 順序是經典小精靈的優先級：上 → 左 → 下 → 右
	# 距離相同時會照這個順序決定，讓行為可預測
	var options: Array[Vector2i] = []
	for d in [Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT]:
		if dir != Vector2i.ZERO and d == -dir:
			continue                      # 不准回頭
		if maze.is_open(cell + d):
			options.append(d)

	if options.is_empty():
		# 死路，這時才允許回頭
		if dir != Vector2i.ZERO and maze.is_open(cell - dir):
			return -dir
		return Vector2i.ZERO

	var best := options[0]
	var best_dist := INF
	for d in options:
		var dist := Vector2(cell + d).distance_squared_to(Vector2(target_cell))
		if dist < best_dist:
			best_dist = dist
			best = d
	return best


## 把目標格夾在迷宮內部，免得預判點跑到外框外面讓距離失真
func _clamp_cell(c: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(c.x, 1, Maze.COLS - 2),
		clampi(c.y, 1, Maze.ROWS - 2))


## 曼哈頓距離（單位是格），只用來判斷遊蕩貓要不要撲上去
func _cell_dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _draw() -> void:
	# Placeholder：三個個性用不同亮度與剪影，之後換成 Sprite2D + 像素素材
	if fill_col.a > 0.0:
		draw_rect(Rect2(-7, -7, 14, 14), fill_col)
	draw_rect(Rect2(-7, -7, 14, 14), body_col, false, 1.0)
	draw_circle(Vector2(-3, -2), 1.5, Palette.CAT_EYE)
	draw_circle(Vector2(3, -2), 1.5, Palette.CAT_EYE)
	match kind:
		Kind.AMBUSHER:
			# 額前一對尖角，暗示牠會抄你前面
			draw_line(Vector2(-6, -7), Vector2(-4, -10), body_col, 1.0)
			draw_line(Vector2(6, -7), Vector2(4, -10), body_col, 1.0)
		Kind.WANDERER:
			# 身後拖一條尾巴，看起來就是在閒晃
			draw_line(Vector2(7, 3), Vector2(11, 0), body_col, 1.0)
