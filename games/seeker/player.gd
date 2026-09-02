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
# 動畫：S_Player.tscn（畫師交付，三段各 7 幀 @9fps、300×300 畫布）：
#   walk      跑步循環（移動中推幀，停下來回第 0 幀）
#   hitwall   撞牆播一次（bumped 觸發；露娜重新起步會打斷）
#   getcaught 被暗影猫抓住播一次（seeker 的 DYING 觸發）
# 動畫不自己播 —— 由 _process 用場景定義的 fps 手動推幀：
# set_process(false) 凍結角色時畫面也凍住，跟狀態機的慣例一致。
# tscn 裡三段都設了循環，「播一次」由 play_oneshot()/tick_anim() 夾在
# 最後一幀實現，不去改美術的場景檔。
# FRAME_BOXES 是每幀的角色包圍盒（alpha>32，在 300×300 畫布上量的，
# 2026-09 換新圖（S_Girl_Run／HitWall／Getcaught）時重測），用於
# 「腳底貼底 + 水平居中」歸一化 —— 畫師每幀的擺位有誤差，不歸一化
# 播放起來會上下左右抖。畫師改圖時這 21 個數字要重測。
# ─────────────────────────────────────────────
const S_PLAYER_SCENE := preload("res://assets/AnimationScene/S_Player.tscn")
const ANIM_WALK := &"walk"
const ANIM_HITWALL := &"hitwall"
const ANIM_GETCAUGHT := &"getcaught"
## 顯示寬度：walk 最寬幀縮放到 16px（走廊寬度，跟舊版同一條規則）。
## hitwall／getcaught 最寬幀 212px（walk 196），同一縮放下約 17px ——
## 一次性動畫瞬間寬一點沒關係，三段動畫的角色大小必須一致。
const SHOW_W := 16.0
const FRAME_BOXES := {
	&"walk": [
		Rect2(53, 45, 196, 216),   # S_Girl_Run_0
		Rect2(61, 46, 180, 227),   # S_Girl_Run_1
		Rect2(69, 37, 180, 212),   # S_Girl_Run_2
		Rect2(73, 37, 184, 216),   # S_Girl_Run_3
		Rect2(45, 41, 196, 212),   # S_Girl_Run_4
		Rect2(73, 41, 180, 216),   # S_Girl_Run_5
		Rect2(81, 37, 180, 208),   # S_Girl_Run_6
	],
	&"hitwall": [
		Rect2(52, 37, 196, 216),   # S_Girl_HitWall_1
		Rect2(20, 29, 200, 240),   # S_Girl_HitWall_2
		Rect2(64, 5, 168, 236),    # S_Girl_HitWall_3
		Rect2(80, 4, 180, 237),    # S_Girl_HitWall_4
		Rect2(80, 65, 188, 180),   # S_Girl_HitWall_5
		Rect2(84, 121, 208, 124),  # S_Girl_HitWall_6
		Rect2(84, 121, 208, 124),  # S_Girl_HitWall_7
	],
	&"getcaught": [
		Rect2(41, 53, 196, 216),   # S_Girl_Getcaught_1
		Rect2(10, 45, 212, 240),   # S_Girl_Getcaught_2
		Rect2(54, 21, 176, 236),   # S_Girl_Getcaught_3
		Rect2(70, 17, 180, 240),   # S_Girl_Getcaught_4
		Rect2(70, 81, 188, 180),   # S_Girl_Getcaught_5
		Rect2(74, 137, 208, 124),  # S_Girl_Getcaught_6
		Rect2(74, 137, 208, 124),  # S_Girl_Getcaught_7
	],
}

var facing := Vector2i.DOWN   # 最後的橫向移動方向（源圖角色朝左，向右移動時水平鏡像；上下移動不變）
var _anim_time := 0.0
var _view: Node2D
var _anim: AnimatedSprite2D
var _show_scale := 1.0        # 三段動畫共用的縮放（walk 最寬幀 = SHOW_W）
var _oneshot := &""           # 正在播的一次性動畫；&"" = walk 循環
var _oneshot_time := 0.0


func _ready() -> void:
	_view = S_PLAYER_SCENE.instantiate()
	_anim = _view.get_node("AnimatedSprite2D") as AnimatedSprite2D
	_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var max_w := 0.0
	for b in FRAME_BOXES[ANIM_WALK]:
		max_w = maxf(max_w, b.size.x)
	_show_scale = SHOW_W / max_w
	# 縮放必須在第一幀就設好：READY 期間 _process 沒在跑，_update_anim 不會
	# 執行 —— 沒設的話開場會以貼圖原尺寸（300×300）畫出一個巨無霸露娜。
	_anim.scale = Vector2(_show_scale, _show_scale)
	_anim.pause()                          # 幀由 _process 手動推進（見 _update_anim）
	_anim.frame_changed.connect(_apply_frame_anchor)
	_apply_frame_anchor()
	add_child(_view)


## 幀歸一化：每幀的角色中心對到玩家座標（x=0）、腳底對到 +8（跟舊版錨點一致）。
## centered=true 的畫布中心落在 offset，換算回未縮放座標要 ÷_show_scale。
func _apply_frame_anchor() -> void:
	var anim := _anim.animation
	var boxes: Array = FRAME_BOXES[anim]
	var b: Rect2 = boxes[_anim.frame % boxes.size()]
	var ts: Vector2 = _anim.sprite_frames.get_frame_texture(anim, _anim.frame).get_size()
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
	_to_walk()


func _process(delta: float) -> void:
	if maze == null:
		return
	if _squash > 0.0:
		_squash = maxf(0.0, _squash - delta / SQUASH_TIME)
	_read_input()
	_move(delta)
	_update_anim(delta)


## 動畫主邏輯：
## 1. 一次性動畫播放中 → 推幀（露娜重新起步會打斷 hitwall 回到走路）
## 2. 移動中 → walk 推幀；面向跟著移動方向轉
func _update_anim(delta: float) -> void:
	if _oneshot != &"":
		# getcaught 只會在 DYING 播（那時 _process 已凍），這裡只會是 hitwall
		if dir != Vector2i.ZERO and _oneshot == ANIM_HITWALL:
			_to_walk()
		else:
			tick_anim(delta)
			_update_flip_scale()   # 撞牆擠壓照常衰減，不會卡在變形裡
			return
	if dir != Vector2i.ZERO:
		if dir.x != 0:
			facing = dir   # 只有橫向移動才改面向：上下移動保持原本的左右朝向
		if _anim.animation != ANIM_WALK:
			_to_walk()
		_anim_time += delta
		var fps := _anim.sprite_frames.get_animation_speed(ANIM_WALK)
		var count := _anim.sprite_frames.get_frame_count(ANIM_WALK)
		var f := int(_anim_time * fps) % count
		if f != _anim.frame:
			_anim.frame = f
	elif want != Vector2i.ZERO and want.x != 0:
		facing = want   # 頂著牆按左右方向鍵時也轉向（按上下不變）
	else:
		_anim_time = 0.0
		if _anim.frame != 0:
			_anim.frame = 0
	_update_flip_scale()


## 切回 walk 循環並歸零推幀時間
func _to_walk() -> void:
	_oneshot = &""
	_oneshot_time = 0.0
	_anim_time = 0.0
	_anim.animation = ANIM_WALK
	_anim.frame = 0
	_apply_frame_anchor()


## 播一段一次性動畫（hitwall／getcaught）：播完停在最後一幀。
func play_oneshot(anim: StringName) -> void:
	_oneshot = anim
	_oneshot_time = 0.0
	_anim.animation = anim
	_anim.frame = 0
	_apply_frame_anchor()


## 一次性動畫推幀。PLAYING 時由本節點 _process 呼叫；DYING 時角色被
## set_process(false) 凍住，由 seeker 的 DYING 分支代呼叫。
func tick_anim(delta: float) -> void:
	if _oneshot == &"":
		return
	_oneshot_time += delta
	var fps := _anim.sprite_frames.get_animation_speed(_oneshot)
	var last := _anim.sprite_frames.get_frame_count(_oneshot) - 1
	var f := mini(int(_oneshot_time * fps), last)
	if f != _anim.frame:
		_anim.frame = f


## 鏡像與擠壓變形：源圖角色朝左，向右移動時水平鏡像（scale.x 負號繞原點鏡像；
## 角色水平居中在 x=0，鏡像就原地翻面）。
func _update_flip_scale() -> void:
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
		# 撞上去了：播 hitwall 動畫＋發震動，並讓露娜貼著牆壓扁一下
		_squash = 1.0
		_squash_axis = Vector2(dir)
		bumped.emit(dir)
		play_oneshot(ANIM_HITWALL)
		dir = Vector2i.ZERO   # 前面是牆，停下來
