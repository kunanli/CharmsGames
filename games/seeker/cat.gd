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

# ─────────────────────────────────────────────
# 動畫：S_Cat.tscn（畫師交付的 chase 動畫，8 幀 @9fps、240×184 畫布）。
# 三種個性共用同一套貼圖與動畫（2026-09 企劃指定）。
# 動畫不自己播 —— 由 _process 用場景定義的 fps 手動推幀：
# set_process(false) 凍結貓時畫面也凍住，跟狀態機的慣例一致。
# FRAME_BOXES 是每幀的角色包圍盒（alpha>32，在 240×184 畫布上量的），
# 用於「內容中心對齊節點原點」的歸一化 —— 貓浮在格子中央（中心錨點），
# 跟露娜的腳底錨點不同。畫師改圖時這 8 個數字要重測。
# ─────────────────────────────────────────────
const CAT_SCENE := preload("res://assets/AnimationScene/S_Cat.tscn")
const ANIM_CHASE := &"chase"
## 顯示尺寸：內容最長邊縮放到 26px（約 1.7 格；2026-09 企劃要求比原 30px
## 調小一點）。碰撞判定用格子中心距離（9px），畫多大都不影響判定。
const SHOW_SIZE := 26.0
const FRAME_BOXES: Array[Rect2] = [
	Rect2(46, 44, 136, 112),   # S_Cat_Chase_1
	Rect2(42, 40, 148, 116),   # S_Cat_Chase_2
	Rect2(42, 56, 132, 100),   # S_Cat_Chase_3
	Rect2(50, 28, 140, 112),   # S_Cat_Chase_4
	Rect2(42, 56, 140, 100),   # S_Cat_Chase_5
	Rect2(42, 56, 148, 100),   # S_Cat_Chase_6
	Rect2(42, 44, 132, 112),   # S_Cat_Chase_7
	Rect2(50, 28, 140, 112),   # S_Cat_Chase_8
]

var _view: Node2D
var _anim: AnimatedSprite2D
var _show_scale := 1.0
var _anim_time := 0.0
var _face_right := false            # 源圖貓朝左，向右移動時水平鏡像


func _ready() -> void:
	_view = CAT_SCENE.instantiate()
	_anim = _view.get_node("AnimatedSprite2D") as AnimatedSprite2D
	_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var max_dim := 0.0
	for b in FRAME_BOXES:
		max_dim = maxf(max_dim, b.size.x)
		max_dim = maxf(max_dim, b.size.y)
	_show_scale = SHOW_SIZE / max_dim
	# 縮放必須在第一幀就設好 —— 沒設的話會以 240×184 原尺寸畫出巨無霸暗影猫。
	_anim.scale = Vector2(_show_scale, _show_scale)
	_anim.pause()                      # 幀由 _process 手動推進（見 _update_visual）
	_anim.frame_changed.connect(_apply_frame_anchor)
	_apply_frame_anchor()
	add_child(_view)


## 幀歸一化：每幀的角色內容中心對到節點原點（貓的中心錨點）。
func _apply_frame_anchor() -> void:
	var b: Rect2 = FRAME_BOXES[_anim.frame % FRAME_BOXES.size()]
	var ts: Vector2 = _anim.sprite_frames.get_frame_texture(ANIM_CHASE, _anim.frame).get_size()
	_anim.offset = Vector2(
		ts.x * 0.5 - b.get_center().x,
		ts.y * 0.5 - b.get_center().y)


## 設定個性。三種貓速度不同，外觀共用同一套 S_Cat.tscn 的 chase 動畫
## （2026-09 企劃指定三隻同貼圖，畫面上的辨識目前只能靠行為）。
func configure(k: Kind, home: Vector2i, delay: float) -> void:
	kind = k
	home_cell = home
	release_delay = delay
	match kind:
		Kind.CHASER:
			speed = 60.0
		Kind.AMBUSHER:
			speed = 66.0
		Kind.WANDERER:
			speed = 54.0


func setup(m: Maze, start_cell: Vector2i) -> void:
	maze = m
	cell = start_cell
	position = maze.cell_center(cell)
	# 貼圖縮小畫到螢幕，必須用最近鄰保持像素顆粒（線性濾波會糊）
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	_face_right = false
	_anim_time = 0.0
	_anim.frame = 0
	_apply_frame_anchor()


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
## 一次石化就能刷到 1550 分。回到 ACTIVE 就沒有這個問題，
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

	# 碎掉了：倒數重生（重生規則見 _revive）。visible 已關，視覺不用更新
	if status == Status.BROKEN:
		revive_left -= delta
		if revive_left <= 0.0:
			_revive()
		return

	# 石化：站著不動當靶子。動畫凍住，但石化色要繼續呼吸／閃白
	if status == Status.PETRIFIED:
		_update_visual(delta)
		return

	# 登場前在出生格待命，畫面上以半透明表示還沒啟動
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			modulate.a = 1.0
		_update_visual(delta)
		return

	if dir == Vector2i.ZERO:
		dir = _choose_dir()
		if dir == Vector2i.ZERO:
			_update_visual(delta)
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

	_update_visual(delta)


## 視覺更新：chase 推幀、依橫向移動方向鏡像、石化色。
func _update_visual(delta: float) -> void:
	if status == Status.PETRIFIED:
		# 半透明藍白緩慢呼吸（美術規格書 3.2）；剩 2 秒改成閃白版本
		var t := Time.get_ticks_msec() / 1000.0
		var col := Palette.MOON
		var alpha := 0.55 + sin(t * 4.0) * 0.15
		if petrify_ending:
			col = Palette.TEXT
			alpha = 1.0 if fmod(t, 0.24) < 0.12 else 0.35
		_anim.self_modulate = Color(col, alpha)
		return                 # 石化凍結：不推幀、不轉向
	_anim.self_modulate = Color.WHITE
	# 橫向移動時照方向鏡像：源圖貓朝左，向右走要翻面。
	# 用 scale.x 負號繞原點鏡像（跟露娜同一套）—— 內容中心歸一化在 x=0，
	# 鏡像原地翻面，逐幀的歸一化 offset 也會跟著一起翻。
	if dir.x != 0:
		_face_right = dir.x > 0
	_anim_time += delta
	var fps := _anim.sprite_frames.get_animation_speed(ANIM_CHASE)
	var f := int(_anim_time * fps) % FRAME_BOXES.size()
	if f != _anim.frame:
		_anim.frame = f
	var flip := -1.0 if _face_right else 1.0
	var want_scale := Vector2(_show_scale * flip, _show_scale)
	if _anim.scale != want_scale:
		_anim.scale = want_scale


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
