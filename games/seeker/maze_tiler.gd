class_name MazeTiler
extends RefCounted

# ─────────────────────────────────────────────────────────
# 邏輯迷宮 → TileMap 美術：把「哪格是牆」的邏輯地圖自動鋪成
# 兩層 TileMapLayer（MazeBase 基礎牆在下、MazeCorner 轉角疊加在上）。
#
# 碰撞照舊以邏輯地圖（Maze.walls）為準，這兩層純粹是視覺，
# 不產生任何物理；TileSet 直接沿用 tile_maze.tscn 裡那顆
# （80×80、單一 atlas source 0），不另建新的 TileSet，
# tile_maze.tscn 場景本身也不改。
#
# 拼接規則（只看牆格的四鄰，出界視為走道）：
#   上下都是走道 → 橫向帶：左端／中間／右端
#   左右都是走道 → 縱向帶：頂部／中間／底部
#   橫向與縱向在此格都延續（90° 轉角、T 形、十字）
#     → MazeBase 疊橫向 tile（右鄰是牆用左端、左鄰是牆用右端、
#        兩側都是牆用中間）＋ MazeCorner 疊「縱向牆中間1」
#   中間1／中間2 可互換，按座標奇偶交替取，避免相鄰兩格重複
#
# 素材無法表現的結構：孤立 1×1 牆塊（四鄰都是走道）——
# 8 個 tile 全是「帶」類，沒有獨立方塊可用。build() 會把這種格
# 收進回傳的 missing 陣列，邏輯地圖應避免出現 1×1 牆塊。
# ─────────────────────────────────────────────────────────

const TILE_SCENE_PATH := "res://assets/seeker/Map/TileMap/tile_maze.tscn"
const TILE_PX := 80.0            # 素材單格像素
const SOURCE_ID := 0             # TileSet 裡唯一的 atlas source

# atlas 座標（S_Map_Tile.png 是 4×5 格 80px，只有這 8 格有內容）
const T_H_LEFT := Vector2i(0, 0)     # 橫向牆左端（圓角朝左）
const T_H_MID1 := Vector2i(1, 0)     # 橫向牆中間1
const T_H_MID2 := Vector2i(2, 0)     # 橫向牆中間2
const T_H_RIGHT := Vector2i(3, 0)    # 橫向牆右端
const T_V_TOP := Vector2i(0, 1)      # 縱向牆頂部
const T_V_MID1 := Vector2i(0, 2)     # 縱向牆中間1（＝轉角疊加用的那格）
const T_V_MID2 := Vector2i(0, 3)     # 縱向牆中間2
const T_V_BOTTOM := Vector2i(0, 4)   # 縱向牆底部
const T_CORNER := T_V_MID1           # 90° 轉角統一疊「縱向牆中間1」


## 建立兩層 TileMapLayer，共用 tile_maze.tscn 的 TileSet。
## origin：迷宮左上角在畫面上的位置；cell_px：邏輯格邊長
## （Seeker 用 Maze.ORIGIN 與 Maze.CELL_SIZE.x）。
## 回傳 {"root", "base", "corner"}，root 已 add 進 parent。
static func create_layers(parent: Node, origin: Vector2, cell_px: float) -> Dictionary:
	var packed: PackedScene = load(TILE_SCENE_PATH)
	var demo := packed.instantiate() as TileMap
	var tile_set: TileSet = demo.tile_set
	demo.free()                   # 只借場景裡的 TileSet 資源，節點本身不要

	var root := Node2D.new()
	root.name = "Maze"
	root.position = origin
	var s := cell_px / TILE_PX
	root.scale = Vector2(s, s)

	var base := TileMapLayer.new()
	base.name = "MazeBase"
	base.tile_set = tile_set
	# 貼圖縮小畫到螢幕，必須用最近鄰保持像素顆粒（線性濾波會糊）
	base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(base)

	var corner := TileMapLayer.new()
	corner.name = "MazeCorner"
	corner.tile_set = tile_set
	corner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(corner)        # 後 add → 疊在 MazeBase 上面

	parent.add_child(root)
	return {"root": root, "base": base, "corner": corner}


## 依邏輯牆格鋪滿兩層。walls：Vector2i -> true（同 Maze.walls）。
## 回傳無法表現的牆格（目前只有孤立 1×1），空陣列代表全部鋪完。
static func build(base: TileMapLayer, corner: TileMapLayer, walls: Dictionary,
		cols: int, rows: int) -> Array[Vector2i]:
	base.clear()
	corner.clear()
	var missing: Array[Vector2i] = []
	for y in rows:
		for x in cols:
			var c := Vector2i(x, y)
			if not walls.has(c):
				continue
			var l := walls.has(Vector2i(x - 1, y))
			var r := walls.has(Vector2i(x + 1, y))
			var u := walls.has(Vector2i(x, y - 1))
			var d := walls.has(Vector2i(x, y + 1))
			if not u and not d:
				# 橫向帶：上下都是走道
				if not l and not r:
					missing.append(c)          # 孤立 1×1：沒有對應素材
				elif r and not l:
					base.set_cell(c, SOURCE_ID, T_H_LEFT)
				elif l and not r:
					base.set_cell(c, SOURCE_ID, T_H_RIGHT)
				else:
					base.set_cell(c, SOURCE_ID, _h_mid(x))
			elif not l and not r:
				# 縱向帶：左右都是走道
				if d and not u:
					base.set_cell(c, SOURCE_ID, T_V_TOP)
				elif u and not d:
					base.set_cell(c, SOURCE_ID, T_V_BOTTOM)
				else:
					base.set_cell(c, SOURCE_ID, _v_mid(y))
			else:
				# 90° 轉角／T 形／十字：橫向 tile 當底＋縱向中間1 疊加
				base.set_cell(c, SOURCE_ID, _h_base(l, r, x))
				corner.set_cell(c, SOURCE_ID, T_CORNER)
	return missing


## 一份 ASCII 邏輯地圖直接生出整組圖層（# = 牆、. = 走道）。
## 回傳 create_layers 的結果，另加 "missing"／"cols"／"rows"。
static func build_ascii(parent: Node, map_text: String, origin: Vector2,
		cell_px: float) -> Dictionary:
	var m := parse_ascii(map_text)
	var layers := create_layers(parent, origin, cell_px)
	layers["missing"] = build(layers.base, layers.corner, m.walls, m.cols, m.rows)
	layers["cols"] = m.cols
	layers["rows"] = m.rows
	return layers


## 解析 ASCII 地圖："#" 是牆，其餘字元是走道。
## 回傳 {"walls": Dictionary, "cols": int, "rows": int}。
static func parse_ascii(map_text: String) -> Dictionary:
	var walls := {}
	var cols := 0
	var rows := 0
	for line in map_text.split("\n"):
		line = line.strip_edges(false, true)   # 去行尾 CR／空白，保留行首
		if line.is_empty():
			continue
		cols = maxi(cols, line.length())
		for x in line.length():
			if line[x] == "#":
				walls[Vector2i(x, rows)] = true
		rows += 1
	return {"walls": walls, "cols": cols, "rows": rows}


# 橫向中間1／中間2 按座標奇偶交替，相鄰兩格不會重複
static func _h_mid(x: int) -> Vector2i:
	return T_H_MID1 if x % 2 == 0 else T_H_MID2


static func _v_mid(y: int) -> Vector2i:
	return T_V_MID1 if y % 2 == 0 else T_V_MID2


## 轉角／T 形／十字格的底層橫向 tile：
## 右鄰是牆 → 這格是橫向帶的左端；左鄰是牆 → 右端；
## 兩側都是牆（橫向貫穿）→ 中間。
static func _h_base(l: bool, r: bool, x: int) -> Vector2i:
	if r and not l:
		return T_H_LEFT
	if l and not r:
		return T_H_RIGHT
	return _h_mid(x)
