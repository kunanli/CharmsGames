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

# ─────────────────────────────────────────────
# 跑步動畫：S_Player.tscn（畫師交付的 walk 動畫場景，8 幀）。
# 動畫不自己播 —— 由 _process 用場景定義的 fps 手動推幀：
# set_process(false) 凍結角色時畫面也凍住，跟狀態機的慣例一致。
# FRAME_BOXES 是每幀的角色包圍盒（alpha>32，在 464×464 畫布上量的），
# 用於「腳底貼底 + 水平居中」歸一化 —— 畫師每幀的擺位有 ±20px 誤差，
# 不歸一化播放起來會上下左右抖（跟舊 WALK_FRAMES 同一套做法；
# 畫師改圖時用腳本重測這 8 個數字）。
# ─────────────────────────────────────────────
const S_PLAYER_SCENE := preload("res://assets/AnimationScene/S_Player.tscn")
const ANIM_NAME := &"walk"
## 顯示寬度：貼圖自適應縮放到 16px 寬（走廊寬度，跟舊版同一條規則），
## 高度照比例 —— 新圖比舊圖寬，實際高約 18px。腳底錨點維持 +8。
const SHOW_W := 16.0
const FRAME_BOXES := [
	Rect2(72, 39, 363, 397),   # S_P_Walk_1.png
	Rect2(107, 38, 334, 404),  # S_P_Walk_2.png
	Rect2(106, 40, 329, 390),  # S_P_Walk_3.png
	Rect2(81, 37, 359, 397),   # S_P_Walk_4.png
	Rect2(77, 30, 361, 399),   # S_P_Walk_5.png
	Rect2(108, 39, 334, 404),  # S_P_Walk_6.png
	Rect2(94, 39, 338, 379),   # S_P_Walk_7.png
	Rect2(72, 39, 363, 397),   # S_P_Walk_8.png
]

var facing := Vector2i.DOWN   # 最後的移動方向（源圖角色朝左，向右移動時水平鏡像）
var _anim_time := 0.0
var _view: Node2D
var _anim: AnimatedSprite2D
var _show_scale := 1.0        # 所有幀共用的縮放（取最寬那幀當基準）


func _ready() -> void:
	_view = S_PLAYER_SCENE.instantiate()
	_anim = _view.get_node("AnimatedSprite2D") as AnimatedSprite2D
	_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var max_w := 0.0
	for b in FRAME_BOXES:
		max_w = maxf(max_w, b.size.x)
	_show_scale = SHOW_W / max_w
	# 縮放必須在第一幀就設好：READY 期間 _process 沒在跑，_update_anim 不會
	# 執行 —— 沒設的話開場會以貼圖原尺寸（464×464）畫出一個巨無霸露娜。
	_anim.scale = Vector2(_show_scale, _show_scale)
	_anim.pause()                          # 幀由 _process 手動推進（見 _update_anim）
	_anim.frame_changed.connect(_apply_frame_anchor)
	_apply_frame_anchor()
	add_child(_view)


## 幀歸一化：每幀的角色中心對到玩家座標（x=0）、腳底對到 +8（跟舊版錨點一致）。
## centered=true 的畫布中心落在 offset，換算回未縮放座標要 ÷_show_scale。
func _apply_frame_anchor() -> void:
	var b: Rect2 = FRAME_BOXES[_anim.frame % FRAME_BOXES.size()]
	var ts: Vector2 = _anim.sprite_frames.get_frame_texture(ANIM_NAME, _anim.frame).get_size()
	_anim.offset = Vector2(
		ts.x * 0.5 - b.get_center().x,
		ts.y * 0.5 - b.end.y + 8.0 / _show_scale)


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
	_anim_time = 0.0
	if _anim.frame != 0:
		_anim.frame = 0


func _process(delta: float) -> void:
	if maze == null:
		return
	if _squash > 0.0:
		_squash = maxf(0.0, _squash - delta / SQUASH_TIME)
	_read_input()
	_move(delta)
	_update_anim(delta)


## 跑步動畫：移動中推進幀，停下來回到第 0 幀；面向跟著移動方向轉。
func _update_anim(delta: float) -> void:
	if dir != Vector2i.ZERO:
		facing = dir
		_anim_time += delta
		var fps := _anim.sprite_frames.get_animation_speed(ANIM_NAME)
		var f := int(_anim_time * fps) % FRAME_BOXES.size()
		if f != _anim.frame:
			_anim.frame = f
	elif want != Vector2i.ZERO:
		facing = want   # 頂著牆按方向鍵時也轉向
	else:
		_anim_time = 0.0
		if _anim.frame != 0:
			_anim.frame = 0
	# 鏡像：源圖角色朝左，向右移動時水平鏡像（scale.x 負號繞原點鏡像；
	# 角色水平居中在 x=0，鏡像就原地翻面）。擠壓變形疊在縮放上。
	var flip := -1.0 if facing.x > 0 else 1.0
	var sq := Fx.squash(_squash, _squash_axis)
	var want_scale := Vector2(_show_scale * flip * sq.x, _show_scale * sq.y)
	if want_scale != _anim.scale:
		_anim.scale = want_scale


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
