class_name Player
extends Node2D

# ─────────────────────────────────────────────────────────
# 露娜：Pac-Man 式的格子移動
# 不使用物理碰撞，純數學判斷，所以不會有卡牆角、抖動的問題。
# ─────────────────────────────────────────────────────────

const SPEED := 72.0   # px/s，一秒走 4.5 格

var maze: Maze
var cell := Vector2i.ZERO         # 目前「出發的那一格」
var dir := Vector2i.ZERO          # 正在移動的方向
var want := Vector2i.ZERO         # 玩家想要的方向（到路口才會生效）

signal ate(cell: Vector2i, kind: int)
## 用 72 px/s 撞上牆的那一瞬間。只在「移動中被擋下」時觸發一次。
signal bumped(dir: Vector2i)

## 停著、而且想去的方向是牆。按著方向鍵頂牆時會一直是 true。
## 這個**不發 signal** —— 它每幀都成立，發 signal 會變成每秒 60 次的閃頻。
var blocked := false

# 撞牆的擠壓變形（見 shared/fx.gd）。只影響繪製，不碰 position。
const SQUASH_TIME := 0.20
var _squash := 0.0
var _squash_axis := Vector2.ZERO

# ─────────────────────────────────────────────────────────
# 跑步動畫：S_Player_walk.png 是畫師的 8 倍大圖（2 行 × 4 列）。
#   列 = 行走循環 4 幀；行 = 兩個循環版本，WALK_ROW 換一個字即可切換。
#   幀源矩形已做「腳底貼底 + 水平居中」歸一化，消除畫師每幀的放置誤差，
#   播放起來才不會左右上下抖。
# ─────────────────────────────────────────────────────────
const WALK_ROW := 0
## 顯示尺寸：貼圖自適應縮放到 16×32（美術規格的幀大小，也正好是走廊寬度）——
## 比例取 min(16/寬, 32/高)，不變形地塞進 16×32 的框裡。
const SHOW_SIZE := Vector2(16.0, 32.0)
## 幀播放順序：源圖的列是從右往左排的，照 0,1,2,3 播會倒著走（實機確認）。
const FRAME_ORDER := [3, 2, 1, 0]
const ANIM_FPS := 8.0
const WALK_FRAMES := [
	[Rect2(48, 50, 331, 424), Rect2(424, 50, 331, 424), Rect2(824, 50, 331, 424), Rect2(1184, 50, 331, 424)],
	[Rect2(54, 532, 337, 429), Rect2(439, 532, 337, 429), Rect2(826, 532, 337, 429), Rect2(1188, 532, 337, 429)],
]

var s_player_walk: Texture2D = preload("res://assets/seeker/S_Player_walk.png")
var facing := Vector2i.DOWN   # 最後的移動方向（源圖角色朝左，向右移動時水平鏡像）
var _frame := 0
var _anim_time := 0.0


func setup(m: Maze, start_cell: Vector2i) -> void:
	maze = m
	cell = start_cell
	position = maze.cell_center(cell)
	# 貼圖縮小畫到螢幕，必須用最近鄰保持像素顆粒（線性濾波會糊）
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## 重新開始一局時清掉殘留的移動狀態
func reset_direction() -> void:
	dir = Vector2i.ZERO
	want = Vector2i.ZERO
	blocked = false
	_squash = 0.0
	facing = Vector2i.DOWN
	_frame = 0
	_anim_time = 0.0


func _process(delta: float) -> void:
	if maze == null:
		return
	if _squash > 0.0:
		_squash = maxf(0.0, _squash - delta / SQUASH_TIME)
		# 擠壓動畫要在 0.2 秒內連續重繪（position 變換不保證觸發 _draw 重跑）
		queue_redraw()
	_read_input()
	_move(delta)
	_update_anim(delta)


## 跑步動畫：移動中推進幀，停下來回到第 0 幀；面向跟著移動方向轉。
func _update_anim(delta: float) -> void:
	if dir != Vector2i.ZERO:
		facing = dir
		_anim_time += delta
		var f := int(_anim_time * ANIM_FPS) % WALK_FRAMES[WALK_ROW].size()
		if f != _frame:
			_frame = f
			queue_redraw()
	elif want != Vector2i.ZERO:
		facing = want   # 頂著牆按方向鍵時也轉向
	else:
		_anim_time = 0.0


func _read_input() -> void:
	var new_want := want
	# 只吃方向鍵。M4 之後 A 鍵是「啟動石化」的主動技能（GDD 的 Xbox 協議），
	# 原本的 WASD 會跟它打架，而 GDD 本來就只指定方向鍵與左搖桿。
	if Input.is_action_pressed("ui_left"):
		new_want = Vector2i.LEFT
	elif Input.is_action_pressed("ui_right"):
		new_want = Vector2i.RIGHT
	elif Input.is_action_pressed("ui_up"):
		new_want = Vector2i.UP
	elif Input.is_action_pressed("ui_down"):
		new_want = Vector2i.DOWN
	want = new_want

	# 特例：反方向可以立刻掉頭，不用等到下一格
	if dir != Vector2i.ZERO and want == -dir:
		cell += dir      # 原本正在前往的那一格，變成新的出發格
		dir = want


func _move(delta: float) -> void:
	# 停住的時候，只要想去的方向能走就出發
	if dir == Vector2i.ZERO:
		if want != Vector2i.ZERO and maze.is_open(cell + want):
			dir = want
			blocked = false
		else:
			blocked = want != Vector2i.ZERO
			return
	blocked = false

	var target := maze.cell_center(cell + dir)
	var to_target := target - position
	var step := SPEED * delta

	if to_target.length() <= step:
		position = target
		cell += dir
		_arrive_at_cell()
	else:
		position += to_target.normalized() * step


func _arrive_at_cell() -> void:
	var kind := maze.take_item(cell)
	if kind != Maze.ITEM_NONE:
		ate.emit(cell, kind)

	# 到了路口才判斷轉彎
	if want != Vector2i.ZERO and maze.is_open(cell + want):
		dir = want
	if not maze.is_open(cell + dir):
		# 撞上去了：發震動，並讓露娜貼著牆壓扁一下
		_squash = 1.0
		_squash_axis = Vector2(dir)
		bumped.emit(dir)
		dir = Vector2i.ZERO   # 前面是牆，停下來


func _draw() -> void:
	var src: Rect2 = WALK_FRAMES[WALK_ROW][FRAME_ORDER[_frame]]
	# 自適應縮放（8 倍大圖 → 塞進 16×32 的顯示框）與左右鏡像合成進 transform。
	# 擠壓變形：撞到哪一邊就往哪一邊壓扁。這比震動的資訊量更大 ——
	# 玩家看得出是撞到左牆還右牆，而且畫面完全沒動，不會暈。
	var s := minf(SHOW_SIZE.x / src.size.x, SHOW_SIZE.y / src.size.y)
	var scale := Vector2(s, s)
	# 源圖角色本身朝左：向右移動時才需要水平鏡像
	if facing.x > 0:
		scale.x = -scale.x
	if _squash > 0.0:
		scale *= Fx.squash(_squash, _squash_axis)
	draw_set_transform(Vector2.ZERO, 0.0, scale)
	# 腳底錨點不變：腳貼線在 position.y + 8（與舊占位圖一致）。
	# rect 用未縮放座標，transform 負責縮放；8.0 / s 讓縮放後腳線恰好落在 +8。
	if s_player_walk == null:
		return
	var dest := Rect2(-src.size.x * 0.5, 8.0 / s - src.size.y, src.size.x, src.size.y)
	draw_texture_rect_region(s_player_walk, dest, src, Color.WHITE, false)
