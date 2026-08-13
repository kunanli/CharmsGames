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


func setup(m: Maze, start_cell: Vector2i) -> void:
	maze = m
	cell = start_cell
	position = maze.cell_center(cell)


## 重新開始一局時清掉殘留的移動狀態
func reset_direction() -> void:
	dir = Vector2i.ZERO
	want = Vector2i.ZERO


func _process(delta: float) -> void:
	if maze == null:
		return
	_read_input()
	_move(delta)


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
		else:
			return

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
		dir = Vector2i.ZERO   # 前面是牆，停下來


func _draw() -> void:
	# Placeholder：之後換成 Sprite2D + 像素素材
	draw_rect(Rect2(-8, -20, 16, 28), Palette.LUNA, false, 1.0)
	draw_rect(Rect2(-5, -17, 10, 8), Palette.LUNA)      # 帽子
	# 帽上的心形徽章：品牌識別，全畫面該發光的三樣東西之一
	draw_rect(Rect2(-1, -15, 2, 2), Palette.LUNA_LIGHT)
