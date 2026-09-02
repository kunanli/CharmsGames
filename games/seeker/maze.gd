class_name Maze
extends RefCounted

# ─────────────────────────────────────────────────────────
# 迷宮資料層：只負責「哪裡是牆、哪裡有東西」，不負責畫圖。
# 障礙塊每局隨機生成（_generate_blocks，2026-09 起），中央 Logo 牆固定；
# BLOCKS 陣列是生成失敗時的後備地圖，也是形狀詞彙與 sim 的對照基準。
# ─────────────────────────────────────────────────────────

const LEVEL_SIZE := Vector2(330.0, 210.0)      # 關卡像素尺寸（22×14 格）
const COLS := 22                              # 迷宮寬（含外框牆）
const ROWS := 14                              # 迷宮高（含外框牆）
# CELL_SIZE 剛好是 15×15 正方形，珍珠素材 15×15 正好一格一顆
const CELL_SIZE := Vector2(LEVEL_SIZE.x / COLS, LEVEL_SIZE.y / ROWS)
const ORIGIN := Vector2(75.0, 46.0)           # 關卡左上角在 480x270 畫面上的位置

# 後備障礙地圖（2026-09 前的固定版本；每局改由 _generate_blocks 隨機生成，
# 生成失敗才退回這份）：Rect2i(x, y, 寬, 高)，單位是 tile。
# 規則：每塊之間至少隔一格，塊可以貼外框（x 範圍 1~20、y 範圍 1~12）。
# 中央 Logo 牆（LOGO_TOP_LEFT + LOGO_SIZE，5×2 格）也是障礙，守同一條規則。
# 只要守住這條規則，所有走道就保證連通。
const BLOCKS: Array[Rect2i] = [
	Rect2i(3, 2, 3, 2),   Rect2i(10, 2, 2, 2),  Rect2i(13, 2, 4, 2),
	Rect2i(3, 6, 4, 2),   Rect2i(19, 4, 2, 2),  Rect2i(16, 6, 2, 2),
	Rect2i(7, 9, 3, 1),   Rect2i(13, 9, 3, 1),
]

# 月光能量的位置（四個角落）
const MOON_CELLS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(COLS - 2, 1),
	Vector2i(1, ROWS - 2), Vector2i(COLS - 2, ROWS - 2),
]

# 露娜的出生格
const PLAYER_START := Vector2i(10, 10)

# 貓窩：2×2 格的建築，每局隨機位置（_generate_blocks 先抽牠，長條與它
# 至少隔一格）。貓不再有固定出生格 —— 三隻都從貓窩正下方的走道格出現
# （見 cat_spawn_cell()）。
const CAVE_SIZE := Vector2i(2, 2)
# 生成失敗時的後備貓窩位置（與固定 BLOCKS、Logo 都保持間隔，理論上用不到）
const FALLBACK_CAVE := Rect2i(2, 9, 2, 2)

# ── 隨機生成（2026-09）：中央 Logo 牆固定，其餘障礙每局重抽 ──
# 規則沿用原本的走道保證，並守住 TileMap 素材的表現力邊界：
#   ．障礙一律是 **1 行或 1 列的長條**（GEN_SHAPES，隨機翻轉方向）——
#     不生成多行多列的塊，也不會有 1×1（tile 素材畫不出孤立方塊）
#   ．障礙一律與外框隔 1 格：**最外圈走道（x/y = 1 與 COLS-2/ROWS-2）
#     永遠淨空**，外圈一圈一定鋪得到珍珠
#   ．長條彼此（含 Logo 牆）至少隔一格 —— 走道連通的不變式
#   ．四角月光、露娜出生格、貓出生格受保護不被壓住
#   ．總障礙面積對齊舊固定地圖的 40 格，珍珠量與難度基準才不會跑掉
#   ．生成完用 BFS 驗證所有走道連通，不通就整團重抽（64 次失敗退回 BLOCKS）
const GEN_TOTAL_AREA := 40
const GEN_MAX_BLOCKS := 18
const GEN_SHAPES: Array[Vector2i] = [
	Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
]

# 中央 Logo 牆：品牌圖放在這裡，佔 5×1 格，與所有障礙塊至少保持一格空隙
# （見 BLOCKS 規則）。LOGO_CELL 是中心錨點，LOGO_TOP_LEFT 是牆的左上角格。
# 不鋪珍珠。**牆格不鋪 tile** —— 畫面上僅保留品牌圖本身（seeker.gd 的
# _logo_view），碰撞照舊是牆。
const LOGO_CELL := Vector2i(10, 6)      # 中心格（錨點）
const LOGO_SIZE := Vector2i(5, 1)       # 牆的尺寸（5×1 格）
const LOGO_TOP_LEFT := LOGO_CELL - LOGO_SIZE / 2

const ITEM_NONE := 0
const ITEM_BEAN := 1
const ITEM_MOON := 2

var walls: Dictionary = {}   # Vector2i -> true
var items: Dictionary = {}   # Vector2i -> ITEM_BEAN / ITEM_MOON
var open_cells: Array[Vector2i] = []   # 所有走道格，建好就不再變動
var cave_rect := Rect2i()    # 貓窩左上角格（_generate_blocks 每局抽，size 恆為 CAVE_SIZE）
var _rng := RandomNumberGenerator.new()


## rng_seed 傳正值可重現同一張地圖（除錯／測試用），不傳＝每局隨機
func _init(rng_seed: int = -1) -> void:
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	# 先把貓窩落到後備位置：之後無論 _build_walls／_generate_blocks 發生什麼
	# （包含被執行期錯誤打斷），cave_rect 都不會停在空值 (0,0)——
	# 貼圖不會被畫到迷宮左上角、貓也不會生在框上。
	cave_rect = FALLBACK_CAVE
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
	# 障礙長條：這局隨機生成（失敗會退回固定的 BLOCKS，貓窩退回 FALLBACK_CAVE）
	for b in _generate_blocks():
		for x in range(b.position.x, b.position.x + b.size.x):
			for y in range(b.position.y, b.position.y + b.size.y):
				walls[Vector2i(x, y)] = true
	# 貓窩：2×2 建築（_generate_blocks 順便抽出位置），也是障礙
	for x in range(cave_rect.position.x, cave_rect.position.x + CAVE_SIZE.x):
		for y in range(cave_rect.position.y, cave_rect.position.y + CAVE_SIZE.y):
			walls[Vector2i(x, y)] = true
	# 中央 Logo 牆：品牌圖要一直顯示，不能讓角色踩過去
	for x in range(LOGO_TOP_LEFT.x, LOGO_TOP_LEFT.x + LOGO_SIZE.x):
		for y in range(LOGO_TOP_LEFT.y, LOGO_TOP_LEFT.y + LOGO_SIZE.y):
			walls[Vector2i(x, y)] = true


## 貓的出生格：貓窩正下方那一格（seeker.gd 的 _spawn_cat 用，三隻共用，
## 靠 0 / 2.5 / 5 秒的登場延遲先後出現）。長條跟貓窩至少隔一格，
## 這格保證是走道。
func cat_spawn_cell() -> Vector2i:
	return Vector2i(cave_rect.position.x, cave_rect.position.y + CAVE_SIZE.y)


## 隨機長出這局的地形：先抽貓窩（2×2 建築），再抽 1 行或 1 列的長條
## （隨機翻轉方向）。放置規則：彼此、與 Logo 牆至少隔一格；一律與外框
## 隔 1 格；不壓住受保護格（四角月光、露娜出生格）。每團生成完用 BFS
## 驗證所有走道連通，不通就整團重抽；64 次都失敗才退回固定的 BLOCKS
## （貓窩退回 FALLBACK_CAVE）。
## 回傳長條清單；貓窩寫進成員 cave_rect（_build_walls 要用）。
func _generate_blocks() -> Array[Rect2i]:
	# 先落到後備位置再開始抽：就算下面被執行期錯誤打斷，貓窩也會停在
	# 合法位置（FALLBACK_CAVE），不會出現「窩貼在左上角、貓生在框上」。
	cave_rect = FALLBACK_CAVE
	var logo_rect := Rect2i(LOGO_TOP_LEFT, LOGO_SIZE)
	# 保護格：露娜出生格與四角月光。貓的出生格在貓窩四周，長條本來就跟
	# 貓窩至少隔一格，那些格保證淨空，不用另外保護。
	var protected: Array[Vector2i] = [PLAYER_START]
	protected.append_array(MOON_CELLS)
	for attempt in 64:
		var placed: Array[Rect2i] = [logo_rect]
		var cave := _place_random(CAVE_SIZE, placed, protected)
		if cave.size == Vector2i.ZERO:
			continue                 # 貓窩擺不下去（理論上不會），整團重抽
		placed.append(cave)
		var area := 0
		var stuck := false
		while area < GEN_TOTAL_AREA - 4 and placed.size() - 1 < GEN_MAX_BLOCKS:
			var shape := GEN_SHAPES[_rng.randi_range(0, GEN_SHAPES.size() - 1)]
			if shape.x != shape.y and _rng.randf() < 0.5:
				shape = Vector2i(shape.y, shape.x)   # 長條隨機轉向
			var r := _place_random(shape, placed, protected)
			if r.size == Vector2i.ZERO:
				stuck = true                         # 擺不下了，整團重抽
				break
			placed.append(r)
			area += shape.x * shape.y
		if not stuck and area >= GEN_TOTAL_AREA - 4 \
				and _all_open_reachable(placed):
			cave_rect = cave
			return placed.slice(2)   # 前兩個是 Logo 牆與貓窩，只回傳長條
	push_warning("Maze 隨機生成連續失敗，退回固定障礙地圖")
	cave_rect = FALLBACK_CAVE
	return BLOCKS


## 在不撞規則的前提下隨機抽一個位置放 shape；放不下去回傳 size 為 0 的 Rect2i
func _place_random(shape: Vector2i, placed: Array[Rect2i],
		protected: Array[Vector2i]) -> Rect2i:
	for attempt in 200:
		# 障礙一律與外框隔 1 格：格子範圍 x 2~19、y 2~11，
		# 最外圈走道（x/y = 1 與 COLS-2/ROWS-2）永遠淨空
		var x := _rng.randi_range(2, COLS - 2 - shape.x)
		var y := _rng.randi_range(2, ROWS - 2 - shape.y)
		var r := Rect2i(x, y, shape.x, shape.y)
		var expanded := r.grow(1)                    # 至少隔一格的不變式
		var hits := false
		for other in placed:
			if expanded.intersects(other):
				hits = true
				break
		if not hits:
			for p in protected:
				if r.has_point(p):
					hits = true
					break
		if not hits:
			return r
	return Rect2i()


## 從露娜出生格 BFS，驗證候選地圖的每一格走道都連得到（珍珠要吃得到全場、
## 清空獎勵才可能達成）。placed 第 0 個是 Logo 牆，一起算進牆裡。
func _all_open_reachable(placed: Array[Rect2i]) -> bool:
	var wall_set := {}
	for x in COLS:
		wall_set[Vector2i(x, 0)] = true
		wall_set[Vector2i(x, ROWS - 1)] = true
	for y in ROWS:
		wall_set[Vector2i(0, y)] = true
		wall_set[Vector2i(COLS - 1, y)] = true
	for r in placed:
		for x in range(r.position.x, r.position.x + r.size.x):
			for y in range(r.position.y, r.position.y + r.size.y):
				wall_set[Vector2i(x, y)] = true
	if wall_set.has(PLAYER_START):
		return false
	var seen := {PLAYER_START: true}
	var queue: Array[Vector2i] = [PLAYER_START]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= COLS or n.y >= ROWS:
				continue
			if not wall_set.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen.size() == COLS * ROWS - wall_set.size()


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
	# 出生格不放東西，避免一開場就自動吃掉；Logo 格是牆，本就不在 open_cells 裡
	items.erase(PLAYER_START)


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
