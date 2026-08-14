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

## ACTIVE 會追人並且碰到扣命；PETRIFIED 站著不動、碰到會被擊碎；
## BROKEN 是碎掉了，5 秒後在中央重生，這段期間不畫也不判定。
enum Status { ACTIVE, PETRIFIED, BROKEN }

const REVIVE_TIME := 5.0        # 被擊碎後幾秒於中央重生（GDD）
const REVIVE_GRACE := 1.0       # 重生後半透明待命幾秒，給玩家反應時間

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

var status: Status = Status.ACTIVE
var revive_left := 0.0              # BROKEN 狀態還要等幾秒才重生
var petrify_ending := false         # 石化剩 2 秒，畫成閃白版本

var _hold := 0.0                    # 還要等幾秒才登場
var _wander_cell := Vector2i.ZERO   # 遊蕩貓目前晃去哪
var _wander_timer := 0.0
var _rng := RandomNumberGenerator.new()

var s_enemy1: Texture2D = preload("res://assets/seeker/S_Enemy1.png")
var s_enemy2: Texture2D = preload("res://assets/seeker/S_Enemy2.png")


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
	status = Status.ACTIVE
	revive_left = 0.0
	petrify_ending = false
	visible = true
	_rng.randomize()
	modulate.a = HOLD_ALPHA if _hold > 0.0 else 1.0


# ── 石化與擊碎（M4）──────────────────────────────────────

## 月光能量啟動：站著不動，等著被撞碎
func petrify() -> void:
	if status == Status.BROKEN:
		return
	status = Status.PETRIFIED
	petrify_ending = false
	dir = Vector2i.ZERO       # 石化就是變成石頭，停在原地


## 石化時間到，還活著的貓恢復追擊
func unpetrify() -> void:
	petrify_ending = false
	if status == Status.PETRIFIED:
		status = Status.ACTIVE


## 被露娜撞碎：消失 5 秒後於出生格（中央）重生
func shatter() -> void:
	status = Status.BROKEN
	revive_left = REVIVE_TIME
	petrify_ending = false
	visible = false
	dir = Vector2i.ZERO


## 重生：一律回到 ACTIVE，就算石化還沒結束也一樣。
##
## 為什麼不讓牠以石化狀態回來 —— 三隻的出生格在中央緊鄰，
## 石化重生會變成「站在中央等 5 秒，三隻一起彈回來再撞一輪」，
## 一次石化就能刷到 1550 分（比銅寶箱門檻還多）。回到 ACTIVE 就沒有這個問題，
## 而且紫色跟石化的藍白一眼就分得出來，玩家不會誤判。
##
## 重生後給 1 秒的半透明待命（沿用登場延遲那套），
## 免得正在中央連撞的玩家被無預警冒出來的貓秒扣一條命。
func _revive() -> void:
	cell = home_cell
	position = maze.cell_center(cell)
	dir = Vector2i.ZERO
	visible = true
	status = Status.ACTIVE
	_hold = REVIVE_GRACE
	modulate.a = HOLD_ALPHA


## 會不會扣露娜一條命
func is_dangerous() -> bool:
	return status == Status.ACTIVE and _hold <= 0.0


## 撞上去會不會碎
func is_breakable() -> bool:
	return status == Status.PETRIFIED


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

	# 碎掉了：倒數重生（重生規則見 _revive）
	if status == Status.BROKEN:
		revive_left -= delta
		if revive_left <= 0.0:
			_revive()
		return

	# 石化：站著不動當靶子
	if status == Status.PETRIFIED:
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
	if status == Status.BROKEN:
		return

	# Placeholder：三個個性用不同亮度與剪影，之後換成 Sprite2D + 像素素材
	if status == Status.PETRIFIED:
		_draw_petrified()
		return

	_draw_enemy_texture(Color.WHITE)


## 石化：半透明藍白緩慢閃爍（美術規格書 3.2）。
## 剩 2 秒改成閃白版本，讓玩家知道時間快到了。
func _draw_petrified() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var body := Palette.MOON
	var alpha := 0.55 + sin(t * 4.0) * 0.15          # 緩慢呼吸
	if petrify_ending:
		body = Palette.TEXT                           # 閃白
		alpha = 1.0 if fmod(t, 0.24) < 0.12 else 0.35
	_draw_enemy_texture(Color(body, alpha))


func _draw_enemy_texture(modulate_color: Color) -> void:
	var texture := s_enemy2 if kind == Kind.WANDERER else s_enemy1
	if texture == null:
		return
	var size := texture.get_size()
	draw_texture(texture, -size * 0.5, modulate_color)


## 個性的剪影特徵。石化時要跟著換成石化色，不然會露出原本的紫色。
func _draw_accent(col: Color) -> void:
	match kind:
		Kind.AMBUSHER:
			# 額前一對尖角，暗示牠會抄你前面
			draw_line(Vector2(-6, -7), Vector2(-4, -10), col, 1.0)
			draw_line(Vector2(6, -7), Vector2(4, -10), col, 1.0)
		Kind.WANDERER:
			# 身後拖一條尾巴，看起來就是在閒晃
			draw_line(Vector2(7, 3), Vector2(11, 0), col, 1.0)
