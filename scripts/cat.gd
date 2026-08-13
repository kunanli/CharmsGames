class_name Cat
extends Node2D

# ─────────────────────────────────────────────────────────
# 暗影猫：格子移動 + 貪婪追逐
#
# AI 規則（跟小精靈的鬼一樣簡單，但意外地難纏）：
#   1. 每次抵達格子中心時，看四個方向哪些能走
#   2. 排除「回頭路」——不准原地掉頭，這是關鍵，
#      沒有這條規則的話貓會在原地來回抖動
#   3. 剩下的選項中，挑「走過去之後離目標最近」的那個
#   4. 死路才允許回頭
#
# 沒有路徑搜尋、沒有 A*，就是這四條。難纏感來自多隻貓從不同
# 方向包夾，不是來自單隻貓有多聰明。
# ─────────────────────────────────────────────────────────

const SPEED := 60.0    # px/s，比露娜的 72 慢一點，讓玩家跑得掉

const COL_BODY := Color("A878DC")
const COL_EYE := Color("FFE066")

var maze: Maze
var cell := Vector2i.ZERO
var dir := Vector2i.ZERO
var target_cell := Vector2i.ZERO    # 由 main.gd 每幀更新成露娜的位置


func setup(m: Maze, start_cell: Vector2i) -> void:
	maze = m
	cell = start_cell
	position = maze.cell_center(cell)
	dir = Vector2i.ZERO


func _process(delta: float) -> void:
	if maze == null:
		return

	if dir == Vector2i.ZERO:
		dir = _choose_dir()
		if dir == Vector2i.ZERO:
			return

	var target := maze.cell_center(cell + dir)
	var to_target := target - position
	var step := SPEED * delta

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


func _draw() -> void:
	# Placeholder：紫色身體 + 兩隻黃眼睛
	draw_rect(Rect2(-7, -7, 14, 14), COL_BODY, false, 1.0)
	draw_circle(Vector2(-3, -2), 1.5, COL_EYE)
	draw_circle(Vector2(3, -2), 1.5, COL_EYE)
