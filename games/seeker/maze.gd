class_name Maze
extends RefCounted

# ─────────────────────────────────────────────────────────
# 迷宮資料層：只負責「哪裡是牆、哪裡有東西」，不負責畫圖。
# 要改迷宮外觀，只需要動下面的 BLOCKS 陣列。
# ─────────────────────────────────────────────────────────

const TILE := 16                      # 一格 16 px
const COLS := 28                      # 迷宮寬（含外框牆）
const ROWS := 14                      # 迷宮高（含外框牆）
const ORIGIN := Vector2i(16, 32)      # 迷宮左上角在 480x270 畫面上的位置

# 障礙塊：Rect2i(x, y, 寬, 高)，單位是 tile。
# 規則：每塊之間至少隔一格，且不要碰到外框（x 範圍 1~26、y 範圍 1~12）。
# 只要守住這條規則，所有走道就保證連通。
const BLOCKS: Array[Rect2i] = [
	Rect2i(2, 2, 4, 2),   Rect2i(8, 2, 3, 2),   Rect2i(13, 2, 2, 4),
	Rect2i(17, 2, 3, 2),  Rect2i(22, 2, 4, 2),
	Rect2i(2, 6, 3, 3),   Rect2i(7, 5, 4, 2),   Rect2i(17, 5, 4, 2),
	Rect2i(23, 6, 3, 3),
	Rect2i(7, 9, 3, 3),   Rect2i(12, 8, 4, 2),  Rect2i(18, 9, 3, 3),
	Rect2i(2, 11, 3, 1),  Rect2i(23, 11, 3, 1),
]

# 月光能量的位置（四個角落）
const MOON_CELLS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(COLS - 2, 1),
	Vector2i(1, ROWS - 2), Vector2i(COLS - 2, ROWS - 2),
]

# 露娜的出生格
const PLAYER_START := Vector2i(14, 11)

const ITEM_NONE := 0
const ITEM_BEAN := 1
const ITEM_MOON := 2

var walls: Dictionary = {}   # Vector2i -> true
var items: Dictionary = {}   # Vector2i -> ITEM_BEAN / ITEM_MOON
var open_cells: Array[Vector2i] = []   # 所有走道格，建好就不再變動


func _init() -> void:
	_build_walls()
	_collect_open_cells()
	reset_items()


func _build_walls() -> void:
	walls.clear()
	# 外框
	for x in COLS:
		walls[Vector2i(x, 0)] = true
		walls[Vector2i(x, ROWS - 1)] = true
	for y in ROWS:
		walls[Vector2i(0, y)] = true
		walls[Vector2i(COLS - 1, y)] = true
	# 障礙塊
	for b in BLOCKS:
		for x in range(b.position.x, b.position.x + b.size.x):
			for y in range(b.position.y, b.position.y + b.size.y):
				walls[Vector2i(x, y)] = true


## 把所有走道格收成一個陣列，鋪珍珠與遊蕩貓抽目標都靠它
func _collect_open_cells() -> void:
	open_cells.clear()
	for x in range(1, COLS - 1):
		for y in range(1, ROWS - 1):
			var c := Vector2i(x, y)
			if not walls.has(c):
				open_cells.append(c)


## 重新鋪滿珍珠與月光能量（清空全場後會再呼叫一次）
func reset_items() -> void:
	items.clear()
	for c in open_cells:
		items[c] = ITEM_BEAN
	for c in MOON_CELLS:
		if not walls.has(c):
			items[c] = ITEM_MOON
	# 出生格不放東西，避免一開始就自動吃掉
	items.erase(PLAYER_START)


## 這一格能不能走
func is_open(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= COLS or c.y >= ROWS:
		return false
	return not walls.has(c)


## 格子座標 → 該格中心的像素座標
func cell_center(c: Vector2i) -> Vector2:
	return Vector2(ORIGIN) + Vector2(c) * TILE + Vector2(TILE, TILE) * 0.5


## 隨機挑一格走道（遊蕩貓用來抽下一個目標）
func random_open_cell(rng: RandomNumberGenerator) -> Vector2i:
	if open_cells.is_empty():
		return PLAYER_START
	return open_cells[rng.randi_range(0, open_cells.size() - 1)]


func bean_count() -> int:
	var n := 0
	for v in items.values():
		if v == ITEM_BEAN:
			n += 1
	return n


## 吃掉這一格的東西，回傳被吃到的類型（沒有就是 ITEM_NONE）
func take_item(c: Vector2i) -> int:
	if not items.has(c):
		return ITEM_NONE
	var kind: int = items[c]
	items.erase(c)
	return kind
