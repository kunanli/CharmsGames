extends Node2D

# ─────────────────────────────────────────────────────────
# Milestone 4：月光能量存入 HUD、主動啟動石化、擊碎暗影猫
#
# 狀態機：READY（開場停頓）→ PLAYING（計時中）→ DYING（被抓到）→ RESULT（結算）
# 被抓到時分數與剩餘時間都保留，只是位置重置；三條命用完才結束。
#
# 三隻貓的個性寫在 cat.gd，這裡只負責生出來、擺位置、每幀餵目標。
# 出生格排在迷宮中央同一條走道上，登場時間錯開 0 / 2.5 / 5 秒，
# 不然三隻會同時撲過來，開場就沒得玩。
#
# 月光能量不是撿到就發動（GDD 的 Xbox 協議）：撿到存進 HUD 最多囤 2 個，
# 按 A 才啟動 8 秒石化，讓玩家可以留著救急。石化期間貓站著不動，
# 撞上去就碎，同一次石化內連續擊碎分數倍增 50→100→200→400。
# ─────────────────────────────────────────────────────────

enum State { READY, PLAYING, DYING, RESULT }

const ROUND_TIME := 60.0      # 一局的秒數
const READY_TIME := 1.5       # 開場停頓秒數
const DYING_TIME := 1.2       # 被抓到後的停頓秒數
const CATCH_DIST := 9.0       # 碰撞判定距離（px），約半格多一點
const START_LIVES := 3

# ── 月光能量與石化（M4）─────────────────────────────────
const MOON_STOCK_MAX := 2     # HUD 最多囤幾個（GDD）
const PETRIFY_TIME := 8.0     # 啟動後石化幾秒
const PETRIFY_WARN := 2.0     # 剩幾秒開始閃爍提示
# 同一次石化內連續擊碎的分數，超過四隻就維持 400
const SCORE_BREAK: Array[int] = [50, 100, 200, 400]

# 迷宮後面那層淡星點。純粹是為了讓視差有東西可以咬 —— 迷宮的底是一塊純色。
# **星點用 FAR 而不是 PEARL**：Fishing/Catch 的星星用 PEARL，但在 Seeker 裡
# PEARL 就是可收集的星塵珍珠本身，用它畫星星等於在場上灑假目標，
# 也違反美術規格書「只有三樣東西該發光」。美術有意見的話這行改 false 就關掉。
const SHOW_STARS := true

const SCORE_BEAN := 10
const SCORE_MOON := 30
const SCORE_CLEAR := 500      # 清空全場珍珠的獎勵

# 寶箱門檻（企劃書：1500 / 3000 / 5000）
const CHEST_BRONZE := 1500
const CHEST_SILVER := 3000
const CHEST_GOLD := 5000


var maze: Maze
var player: Player
var cats: Array[Cat] = []

var state: State = State.READY
var state_timer := 0.0
var time_left := ROUND_TIME
var score := 0
var lives := START_LIVES
var beans_total := 0
var beans_eaten := 0
var game_over := false        # 結算畫面要顯示 GAME OVER 還是 TIME UP

var moon_stock := 0           # HUD 上囤著的月光能量
var petrify_left := 0.0       # 石化還剩幾秒，0 表示沒在石化
var break_chain := 0          # 這一次石化內已經擊碎幾隻
var _prev_skill := false      # A 鍵的邊緣偵測

# Game feel（見 shared/juice.gd）。
# 露娜與貓是子節點，draw_set_transform() 管不到它們，所以需要一個真的容器
# 節點來承載位移 —— 而且**不能**把位移寫進它們的 position，那是移動邏輯
# 與 9px 碰撞判定在用的值。
var _world: Node2D
var _juice := Juice.new(Juice.ARCADE)


func _ready() -> void:
	maze = Maze.new()

	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

	player = Player.new()
	_world.add_child(player)
	player.ate.connect(_on_player_ate)
	player.bumped.connect(_on_player_bumped)

	# 直追的先出場，預判的稍後補上形成夾擊，遊蕩的最後才放出來
	_spawn_cat(Cat.Kind.CHASER, Vector2i(13, 6), 0.0)
	_spawn_cat(Cat.Kind.AMBUSHER, Vector2i(12, 6), 2.5)
	_spawn_cat(Cat.Kind.WANDERER, Vector2i(14, 6), 5.0)

	_start_round()


## M5 之後會在遊戲中途再呼叫這個加貓，所以生成邏輯集中在這裡
func _spawn_cat(kind: Cat.Kind, home: Vector2i, delay: float) -> Cat:
	var cat := Cat.new()
	cat.configure(kind, home, delay)
	_world.add_child(cat)
	cats.append(cat)
	return cat


# ── 局面控制 ────────────────────────────────────────────

func _start_round() -> void:
	maze.reset_items()
	beans_total = maze.bean_count()
	beans_eaten = 0
	score = 0
	lives = START_LIVES
	time_left = ROUND_TIME
	game_over = false
	moon_stock = 0
	_juice.reset()
	_enter_ready()


func _enter_ready() -> void:
	state = State.READY
	state_timer = READY_TIME
	player.setup(maze, Maze.PLAYER_START)
	player.reset_direction()
	player.set_process(false)      # 開場停頓期間不能動
	player.visible = true
	# 石化不跨越死亡，但囤著的月光能量保留 —— 那是玩家掙來的資源
	_end_petrify()
	for cat in cats:
		cat.setup(maze, cat.home_cell)
		cat.set_process(false)


func _enter_playing() -> void:
	state = State.PLAYING
	player.set_process(true)
	for cat in cats:
		cat.set_process(true)


func _enter_dying() -> void:
	state = State.DYING
	state_timer = DYING_TIME
	player.set_process(false)
	for cat in cats:
		cat.set_process(false)


func _enter_result(is_game_over: bool = false) -> void:
	state = State.RESULT
	game_over = is_game_over
	player.set_process(false)
	player.visible = true
	for cat in cats:
		cat.set_process(false)


func _process(delta: float) -> void:
	# 命中頓格：用容器的 process_mode 一次凍住露娜與所有貓。
	# 不要動它們各自的 set_process() —— 那是 READY/DYING/RESULT 狀態機在用的。
	var run := _juice.tick(delta)
	var mode := Node.PROCESS_MODE_INHERIT if run else Node.PROCESS_MODE_DISABLED
	if _world.process_mode != mode:
		_world.process_mode = mode
	if run:
		_run_state(delta)

	# 位移無條件更新 —— 頓格期間畫面凍住但還在抖，那正是打擊感的來源
	_world.position = _juice.world_offset()
	queue_redraw()


func _run_state(delta: float) -> void:
	# 預設把鏡頭帶回中心；PLAYING 分支會在下面覆寫成玩家的朝向。
	# 頓格期間 _run_state 整個不跑，所以鏡頭會保持傾斜穿過凍結 —— 那是刻意的。
	_juice.look(Vector2.ZERO)
	match state:
		State.READY:
			state_timer -= delta
			if state_timer <= 0.0:
				_enter_playing()
		State.PLAYING:
			_read_skill()
			_tick_petrify(delta)
			# 鏡頭往露娜前進方向偏一點；頂著牆時改成往牆的方向壓
			if player.blocked:
				_juice.look(Vector2(player.want) * 0.4)
			else:
				_juice.look(Vector2(player.dir))
			# 每幀把露娜的位置與朝向交給每一隻貓，各自算自己的目標格
			for cat in cats:
				cat.update_target(player.cell, player.dir, delta)
			time_left -= delta
			if time_left <= 0.0:
				time_left = 0.0
				_enter_result()
			else:
				_resolve_contact()
		State.DYING:
			# 露娜閃爍，然後重新開始或結束
			player.visible = fmod(state_timer, 0.24) < 0.12
			state_timer -= delta
			if state_timer <= 0.0:
				if lives > 0:
					_enter_ready()     # 分數與時間都保留
				else:
					_enter_result(true)
		State.RESULT:
			if Input.is_action_just_pressed("ui_accept"):
				_start_round()


# ── 月光能量與石化（M4）─────────────────────────────────

## A 鍵主動啟動。GDD 的 Xbox 協議指定 A，與另兩款的主動技能鍵一致。
func _read_skill() -> void:
	var now := Input.is_key_pressed(KEY_A)
	if now and not _prev_skill:
		_activate_moon()
	_prev_skill = now


func _activate_moon() -> void:
	# 石化中再按不會疊加，也不浪費庫存
	if moon_stock <= 0 or petrify_left > 0.0:
		return
	moon_stock -= 1
	petrify_left = PETRIFY_TIME
	break_chain = 0
	_juice.kick(0.55)
	_juice.freeze(0.12)
	for cat in cats:
		cat.petrify()


func _tick_petrify(delta: float) -> void:
	if petrify_left <= 0.0:
		return
	petrify_left -= delta
	var ending := petrify_left <= PETRIFY_WARN
	for cat in cats:
		cat.petrify_ending = ending
	if petrify_left <= 0.0:
		_end_petrify()


func _end_petrify() -> void:
	petrify_left = 0.0
	break_chain = 0
	for cat in cats:
		cat.petrify_ending = false
		cat.unpetrify()


## 露娜碰到貓：石化的擊碎，沒石化的扣命。
## 一幀最多處理一隻，避免同時撞到兩隻時的行為變得難以預測。
func _resolve_contact() -> void:
	for cat in cats:
		if player.position.distance_to(cat.position) >= CATCH_DIST:
			continue
		if cat.is_breakable():
			_break_cat(cat)
			return
		if cat.is_dangerous():
			_lose_life()
			return


## 同一次石化內連續擊碎，分數倍增 50 → 100 → 200 → 400
func _break_cat(cat: Cat) -> void:
	var tier := mini(break_chain, SCORE_BREAK.size() - 1)
	score += SCORE_BREAK[tier]
	break_chain += 1
	_juice.kick(0.40 + 0.10 * mini(break_chain, 4))
	_juice.freeze(0.06)
	cat.shatter()


## 撞牆。方向性震動 —— 沿撞擊方向抖，玩家才讀得出是撞到哪一邊。
## 不加頓格：頓格會連貓一起停，理論上可以靠撞牆拖慢追兵。
func _on_player_bumped(d: Vector2i) -> void:
	if state == State.PLAYING:
		_juice.kick(0.34, Vector2(d))


func _lose_life() -> void:
	lives -= 1
	# 不加 freeze —— _enter_dying() 本來就把全世界凍 1.2 秒
	_juice.kick(0.90)
	_enter_dying()


func _on_player_ate(_cell: Vector2i, kind: int) -> void:
	match kind:
		Maze.ITEM_BEAN:
			score += SCORE_BEAN
			beans_eaten += 1
		Maze.ITEM_MOON:
			score += SCORE_MOON
			# 撿到不會直接發動，存進 HUD 等玩家按 A（GDD 的 Xbox 協議）
			moon_stock = mini(moon_stock + 1, MOON_STOCK_MAX)
			_juice.kick(0.30)
	if beans_eaten >= beans_total:
		_refill()


## 清空全場：重鋪珍珠並給獎勵（M5 會在這裡再加一隻暗影猫）
func _refill() -> void:
	maze.reset_items()
	maze.items.erase(player.cell)
	beans_total = maze.bean_count()
	beans_eaten = 0
	score += SCORE_CLEAR
	_juice.kick(0.65)
	_juice.freeze(0.12)


func chest_tier() -> String:
	if score >= CHEST_GOLD:
		return "GOLD CHEST"
	elif score >= CHEST_SILVER:
		return "SILVER CHEST"
	elif score >= CHEST_BRONZE:
		return "BRONZE CHEST"
	return "NO CHEST"


# ── 繪製 ────────────────────────────────────────────────

func _draw() -> void:
	# 三層，每層一個位移（見 shared/juice.gd 的分層模型）
	draw_set_transform(_juice.bg_offset())
	_draw_backdrop()
	draw_set_transform(_juice.world_offset())
	# 牆與珍珠畫在這裡，露娜與貓則由 _world 容器位移；
	# 兩者讀的是同一個 world_offset()，所以不會脫格。
	_draw_maze()
	draw_set_transform(Vector2.ZERO)
	_draw_hud()
	_draw_petrify_edge()

	if state == State.READY:
		_draw_center_text("READY!", 130, 24, Palette.GOLD)
	elif state == State.DYING:
		_draw_center_text("CAUGHT!", 130, 22, Palette.WARN)
	elif state == State.RESULT:
		_draw_result()


## 視差層。迷宮本身只是一塊純色底，沒有東西可以做視差，所以補一層淡星點。
func _draw_backdrop() -> void:
	var m := Juice.OVERDRAW
	draw_rect(Rect2(-m, -m, 480.0 + m * 2.0, 270.0 + m * 2.0), Palette.BG)
	if not SHOW_STARS:
		return
	# 固定的偽隨機（跟 Fishing/Catch 同一套寫法），不要每幀跳動
	for i in 22:
		var x := fmod(float(i) * 97.0, 468.0) + 6.0
		var y := fmod(float(i) * 53.0, 258.0) + 6.0
		draw_rect(Rect2(x, y, 1, 1), Palette.FAR)


func _draw_maze() -> void:
	var o := Vector2(Maze.ORIGIN)
	var t := float(Maze.TILE)
	draw_rect(Rect2(o, Vector2(Maze.COLS, Maze.ROWS) * t), Palette.WALL, false, 1.0)
	for b in Maze.BLOCKS:
		draw_rect(Rect2(o + Vector2(b.position) * t, Vector2(b.size) * t), Palette.WALL, false, 1.0)

	for c in maze.items:
		var center := maze.cell_center(c)
		if maze.items[c] == Maze.ITEM_MOON:
			draw_circle(center, 4.0, Palette.MOON)
		else:
			draw_circle(center, 1.5, Palette.PEARL)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font

	# 左：剩餘時間，最後 10 秒轉為警示色
	var secs := int(ceil(time_left))
	var time_col := Palette.WARN if secs <= 10 else Palette.TEXT
	draw_string(font, Vector2(16, 20), "TIME %d:%02d" % [secs / 60, secs % 60],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, time_col)

	# 中：分數
	draw_string(font, Vector2(0, 20), "SCORE %06d" % score,
		HORIZONTAL_ALIGNMENT_CENTER, 480, 12, Palette.TEXT)

	# 右：生命（三顆圓點）
	for i in lives:
		draw_circle(Vector2(400 + i * 12, 16), 3.5, Palette.LUNA)

	# 右下角：珍珠進度
	draw_string(font, Vector2(0, 264), "BEANS %d/%d" % [beans_eaten, beans_total],
		HORIZONTAL_ALIGNMENT_RIGHT, 464, 8, Palette.TEXT_DIM)

	# 左下角：囤著的月光能量（最多 2 個），空的畫成暗框
	for i in MOON_STOCK_MAX:
		var c := Vector2(22 + i * 14, 258)
		if i < moon_stock:
			draw_circle(c, 5.0, Palette.MOON)
			draw_circle(c + Vector2(-2, -1), 4.0, Palette.BG)
		else:
			draw_arc(c, 5.0, 0.0, TAU, 14, Palette.TEXT_DIM, 1.0)
	if moon_stock > 0 and petrify_left <= 0.0:
		draw_string(font, Vector2(50, 262), "PRESS A",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.MOON)

	# 石化倒數與連擊
	if petrify_left > 0.0:
		draw_string(font, Vector2(0, 34), "PETRIFIED %.1f" % petrify_left,
			HORIZONTAL_ALIGNMENT_CENTER, 480, 10, Palette.MOON)
		if break_chain > 0:
			draw_string(font, Vector2(0, 46), "BREAK x%d" % break_chain,
				HORIZONTAL_ALIGNMENT_CENTER, 480, 10, Palette.GOLD)


## 石化剩 2 秒時畫面邊緣閃爍提示（GDD 的 UI 需求）
func _draw_petrify_edge() -> void:
	if petrify_left <= 0.0 or petrify_left > PETRIFY_WARN:
		return
	if fmod(petrify_left, 0.24) >= 0.12:
		return
	var col := Color(Palette.MOON, 0.75)
	for i in 3:
		draw_rect(Rect2(i, i, 480 - i * 2, 270 - i * 2), col, false, 1.0)


func _draw_result() -> void:
	# 半透明遮罩，讓迷宮沉下去
	# 用色盤的最深夜色壓半透明，不是自己調一個新的深藍
	draw_rect(Rect2(0, 0, 480, 270), Color(Palette.NIGHT, 0.82))

	var title := "GAME OVER" if game_over else "TIME UP"
	var title_col := Palette.WARN if game_over else Palette.GOLD
	_draw_center_text(title, 96, 22, title_col)
	_draw_center_text("SCORE  %06d" % score, 134, 18, Palette.TEXT)
	_draw_center_text(chest_tier(), 162, 14, Palette.MOON)
	_draw_center_text("PRESS ENTER TO PLAY AGAIN", 200, 10, Palette.TEXT_DIM)


func _draw_center_text(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, 480, size, col)
