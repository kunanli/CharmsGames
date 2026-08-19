class_name Maze
extends RefCounted

# ─────────────────────────────────────────────────────────
# 迷宮資料層：只負責「哪裡是牆、哪裡有東西」，不負責畫圖。
# 要改迷宮外觀，只需要動下面的 BLOCKS 陣列。
# ─────────────────────────────────────────────────────────

const LEVEL_SIZE := Vector2(330.0, 210.0)      # 關卡像素尺寸（22×14 格）
const COLS := 22                              # 迷宮寬（含外框牆）
const ROWS := 14                              # 迷宮高（含外框牆）
# CELL_SIZE 剛好是 15×15 正方形，珍珠素材 15×15 正好一格一顆
const CELL_SIZE := Vector2(LEVEL_SIZE.x / COLS, LEVEL_SIZE.y / ROWS)
const ORIGIN := Vector2(75.0, 46.0)           # 關卡左上角在 480x270 畫面上的位置

# 障礙塊：Rect2i(x, y, 寬, 高)，單位是 tile。
# 規則：每塊之間至少隔一格，且不要碰到外框（x 範圍 1~20、y 範圍 1~12）。
# 只要守住這條規則，所有走道就保證連通。
const BLOCKS: Array[Rect2i] = [
	Rect2i(3, 2, 3, 2),   Rect2i(8, 2, 2, 3),   Rect2i(13, 2, 4, 2),
	Rect2i(3, 6, 4, 2),   Rect2i(11, 5, 3, 2),  Rect2i(16, 6, 2, 2),
	Rect2i(7, 9, 3, 1),   Rect2i(13, 9, 3, 1),
]

# 月光能量的位置（四個角落）
const MOON_CELLS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(COLS - 2, 1),
	Vector2i(1, ROWS - 2), Vector2i(COLS - 2, ROWS - 2),
]

# 露娜的出生格
const PLAYER_START := Vector2i(10, 10)

# 中央 Logo 的固定格：保留給品牌圖。不鋪珍珠、也不是障礙物（要一直保持走道格）。
# Logo 圖還沒進場，seeker.gd 先在這裡畫一個佔位框。
const LOGO_CELL := Vector2i(10, 6)

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
	# 出生格與中央 Logo 格不放東西，避免一開場就自動吃掉或蓋住 Logo
	items.erase(PLAYER_START)
	items.erase(LOGO_CELL)


## 這一格能不能走
func is_open(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= COLS or c.y >= ROWS:
		return false
	return not walls.has(c)


## 格子座標 → 該格中心的像素座標
func cell_center(c: Vector2i) -> Vector2:
	return ORIGIN + Vector2(c) * CELL_SIZE + CELL_SIZE * 0.5


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
