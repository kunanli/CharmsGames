extends Node2D

# ─────────────────────────────────────────────────────────
# Milestone 4：月光能量存入 HUD、主動啟動石化、擊碎暗影猫
#
# 狀態機：READY（開場停頓）→ PLAYING（計時中）→ DYING（被抓到）→ RESULT（結算）
# 被抓到時分數與剩餘時間都保留，只是位置重置；三條命用完才結束。
#
# 三隻貓的個性寫在 cat.gd，這裡只負責生出來、擺位置、每幀餵目標。
# 出生格繞著中央 Logo 牆排（左、右、下），登場時間錯開 0 / 2.5 / 5 秒，
# 不然三隻會同時撲過來，開場就沒得玩。
#
# 月光能量不是撿到就發動（GDD 的 Xbox 協議）：撿到存進 HUD 最多囤 2 個，
# 按 A 才啟動 8 秒石化，讓玩家可以留著救急。石化期間貓站著不動，
# 撞上去就碎，同一次石化內連續擊碎分數倍增 50→100→200→400。
# ─────────────────────────────────────────────────────────

signal round_finished(score: int, duration: float, game_over: bool)

enum State { READY, PLAYING, DYING, RESULT }

const ROUND_TIME := 60.0      # 一局的秒數
# 開場停頓：ReadyGo 淡入 0.25s＋動畫 24幀@14fps≈1.71s＋0.05s 緩衝（播完才開場）
const READY_TIME := ReadyGo.FADE_SECONDS + ReadyGo.ANIM_SECONDS + 0.05
const DYING_TIME := 1.2       # 被抓到後的停頓秒數
const CATCH_DIST := 9.0       # 碰撞判定距離（px），約半格多一點
const START_LIVES := 3

# ── 月光能量與石化（M4）─────────────────────────────────
const MOON_STOCK_MAX := 2     # HUD 最多囤幾個（GDD）
const PETRIFY_TIME := 5.0     # 啟動後石化幾秒（2026-09 企劃：8 秒改 5 秒）
const PETRIFY_WARN := 2.0     # 剩幾秒開始閃爍提示
# 同一次石化內連續擊碎的分數，超過四隻就維持 400
const SCORE_BREAK: Array[int] = [50, 100, 200, 400]

# 迷宮後面的視差層。以前迷宮底是一塊純色，需要程式畫星點才有東西可以咬；
# S_MAP.png 全屏背景進場後這層由美術的圖承擔，程式星點關掉。
# 美術想要回星點的話這行改 true 就開。
const SHOW_STARS := false

const SCORE_BEAN := 10
const SCORE_MOON := 30
const SCORE_CLEAR := 500      # 清空全場珍珠的獎勵


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
# 牆體（TileMap）、品牌 Logo、狀態覆蓋層也是子節點，排在 _world 之前：
# 牆畫在角色下面，狀態覆蓋層畫在牆上面、角色下面 —— 跟原本 _draw 的順序一致。
var _tiler_root: Node2D          # 迷宮牆體（maze_tiler.gd 生成的兩層 TileMapLayer）
var _logo_view: Sprite2D         # 中央 Logo 牆的品牌貼圖（疊在 tile 牆上）
var _overlay: Node2D             # 結算壓暗／CAUGHT!／收尾暗角／石化閃邊
var _world: Node2D
var _juice := Juice.new(Juice.ARCADE)
var _fx := Fx.new()               # 粒子（見 shared/fx.gd）
var _score_shown := 0.0           # HUD 上滾動中的分數，會追上 score
var _heart_fade := 0.0            # 剛失去的愛心淡出動畫剩餘秒數（0 = 沒在播）
var _heart_fade_slot := -1        # 正在播動畫的愛心格位
var _moon_fade := 0.0             # 剛用掉的月光圖示淡出動畫剩餘秒數（0 = 沒在播）
var _moon_fade_slot := -1         # 正在播動畫的月光格位

var s_bg: Texture2D = preload("res://assets/seeker/Map/S_MAP.png")
var s_perl: Texture2D = preload("res://assets/seeker/S_Perl.png")
var s_moon: Texture2D = preload("res://assets/seeker/S_Moon.png")
var s_logo: Texture2D = preload("res://assets/seeker/Map/S_Hinder_logo.png")
var s_ui_kuang: Texture2D = preload("res://assets/UI/UI_KUANG.png")
var s_score_frame: Texture2D = preload("res://assets/UI/SCORE_FRAME.png")
var s_heart_ui: Texture2D = preload("res://assets/UI/HEART.png")


func _ready() -> void:
	maze = Maze.new()
	# 貼圖縮小畫到螢幕，必須用最近鄰保持像素顆粒（線性濾波會糊）
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# 迷宮牆體：邏輯地圖（maze.walls）→ TileMap 自動拼接（maze_tiler.gd）。
	# 外框格不鋪 —— S_MAP 的彩繪邊框照舊當外框；Logo 牆格也不鋪 —— 僅保留
	# 品牌圖本身。想整座迷宮都改用 tile，把 inner_walls 換成 maze.walls。
	var tiler := MazeTiler.create_layers(self, Maze.ORIGIN, Maze.CELL_SIZE.x)
	_tiler_root = tiler.root
	var logo_rect := Rect2i(Maze.LOGO_TOP_LEFT, Maze.LOGO_SIZE)
	var inner_walls := {}
	for c: Vector2i in maze.walls:
		var skip := c.x == 0 or c.y == 0 or c.x == Maze.COLS - 1 or c.y == Maze.ROWS - 1 \
			or logo_rect.has_point(c)
		if not skip:
			inner_walls[c] = true
	var missing := MazeTiler.build(tiler.base, tiler.corner, inner_walls,
		Maze.COLS, Maze.ROWS)
	if not missing.is_empty():
		push_warning("MazeTiler：%d 個牆格沒有對應素材 %s" % [missing.size(), missing])

	# 品牌 Logo：牆格不鋪 tile，貼圖照原比例（寬 5 格、高 31.25px）畫在
	# Logo 牆列的正中央。仍用 Sprite2D 疊在圖層上、位移跟 _world 同步。
	_logo_view = Sprite2D.new()
	_logo_view.texture = s_logo
	_logo_view.scale = Vector2.ONE * (Maze.LOGO_SIZE.x * Maze.CELL_SIZE.x / s_logo.get_size().x)
	add_child(_logo_view)

	# 結算壓暗、CAUGHT!、收尾暗角、石化閃邊原本畫在 _draw 尾端（牆之上），
	# 搬進子節點 _overlay 才不會被 TileMap 蓋住；排在 _world 之前維持原層級。
	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

	# 直追的先出場，預判的稍後補上形成夾擊，遊蕩的最後才放出來。
	# 出生格繞著中央 Logo 牆排（左、右、下，Maze.CAT_HOMES），登場時間
	# 錯開 0 / 2.5 / 5 秒，不然三隻會同時撲過來，開場就沒得玩。
	_spawn_cat(Cat.Kind.CHASER, Maze.CAT_HOMES[0], 0.0)
	_spawn_cat(Cat.Kind.AMBUSHER, Maze.CAT_HOMES[1], 2.5)
	_spawn_cat(Cat.Kind.WANDERER, Maze.CAT_HOMES[2], 5.0)

	# 露娜最後 add —— 子節點後加的畫在上面，玩家動畫疊在暗影猫之上，
	# 被抓時貼在貓身上播的 getcaught 才不會被貓蓋住
	player = Player.new()
	_world.add_child(player)
	player.ate.connect(_on_player_ate)
	player.bumped.connect(_on_player_bumped)

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
	_fx.clear()
	_score_shown = 0.0
	_heart_fade = 0.0
	_heart_fade_slot = -1
	_moon_fade = 0.0
	_moon_fade_slot = -1
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
	ReadyGo.create(self)          # 開場 READY 動畫：淡入→播完→淡出→自行釋放


func _enter_playing() -> void:
	state = State.PLAYING
	player.set_process(true)
	for cat in cats:
		cat.set_process(true)


func _enter_dying() -> void:
	state = State.DYING
	state_timer = DYING_TIME
	player.set_process(false)
	# 被抓動畫（getcaught）：角色節點凍住了，幀由 _run_state 的 DYING 分支代推；
	# 播完停在最後一幀，重生時 reset_direction() 切回 walk
	player.play_oneshot(&"getcaught")
	for cat in cats:
		cat.set_process(false)


func _enter_result(is_game_over: bool = false) -> void:
	state = State.RESULT
	game_over = is_game_over
	_score_shown = 0.0             # 結算的總分從 0 滾上去
	player.set_process(false)
	player.visible = true
	for cat in cats:
		cat.set_process(false)
	# 把成績交給 launcher：它提交排行榜、打開面板，之後釋放本節點。
	# duration = 純遊玩秒數（READY／DYING 停頓不算），三款一致。
	round_finished.emit(score, ROUND_TIME - time_left, is_game_over)


func _process(delta: float) -> void:
	# 命中頓格：用容器的 process_mode 一次凍住露娜與所有貓。
	# 不要動它們各自的 set_process() —— 那是 READY/DYING/RESULT 狀態機在用的。
	var run := _juice.tick(delta)
	var mode := Node.PROCESS_MODE_INHERIT if run else Node.PROCESS_MODE_DISABLED
	if _world.process_mode != mode:
		_world.process_mode = mode
	if run:
		_run_state(delta)
		_fx.update(delta)          # 頓格期間粒子也跟著凍住，那正是頓格的用意

	# 分數滾動：數字追上去而不是直接跳。速度跟差距成正比，所以吃珍珠（+10）
	# 幾乎是瞬間，擊碎連擊或清空全場（+400/+500）會滾個 0.3 秒 ——
	# 大分數才需要「賺到」的感覺，小分數滾起來只會拖。
	# 放在頓格外面，純表現不受凍結影響。
	_score_shown = move_toward(_score_shown, float(score),
		maxf(150.0, absf(float(score) - _score_shown) * 3.0) * delta)

	# 愛心與月光圖示的淡出動畫：純表現，不受命中頓格影響
	if _heart_fade > 0.0:
		_heart_fade = maxf(0.0, _heart_fade - delta)
	if _moon_fade > 0.0:
		_moon_fade = maxf(0.0, _moon_fade - delta)

	# 位移無條件更新 —— 頓格期間畫面凍住但還在抖，那正是打擊感的來源
	_world.position = _juice.world_offset()
	# 牆與 Logo 跟 _world 吃同一個位移 —— 接觸雙方共用同一層，不會脫格。
	# Logo 用 LOGO_CELL（中心錨點）對位：centered=true，貼圖中心 = 牆列中心。
	_tiler_root.position = Maze.ORIGIN + _juice.world_offset()
	_logo_view.position = maze.cell_center(Maze.LOGO_CELL) + _juice.world_offset()
	_overlay.queue_redraw()
	queue_redraw()


func _run_state(delta: float) -> void:
	# **Seeker 不做自動鏡頭跟隨。** 實機試玩的結論：迷宮裡玩家要靠牆的位置
	# 定位，畫面自己在飄會讓人暈 —— 眼睛沒有可以錨定的東西。
	# 對照組是 Fishing：那裡的鏡頭是玩家按方向鍵「主動探看」，就很舒服。
	# 規則：**玩家主動觸發的鏡頭移動可以，自動跟隨的不行。** 不要再加回來。
	# 撞擊震動保留 —— 那是離散事件，不是持續位移，不會暈。
	_juice.look(Vector2.ZERO)
	match state:
		State.READY:
			state_timer -= delta
			if state_timer <= 0.0:
				_enter_playing()
		State.PLAYING:
			_read_skill()
			_tick_petrify(delta)
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
			# getcaught 動畫播一次（節點凍住，這裡代推幀），播完停在最後一幀。
			# 原本在這裡做的露娜閃爍由動畫取代 —— 閃爍會把動畫眨得一斷一斷。
			player.tick_anim(delta)
			state_timer -= delta
			if state_timer <= 0.0:
				if lives > 0:
					_enter_ready()     # 分數與時間都保留
				else:
					_enter_result(true)
		State.RESULT:
			# 結算與重開由 launcher 的排行榜面板接手，這裡只負責發過信號
			pass


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
	# 剛用掉的那顆月光圖示播「1 秒放大 1.25 倍＋淡出」（格位 = 用掉後的 moon_stock）
	_moon_fade = 1.0
	_moon_fade_slot = moon_stock
	petrify_left = PETRIFY_TIME
	break_chain = 0
	_juice.kick(0.55)
	_juice.freeze(0.12)
	_fx.burst(player.position, 20, Palette.MOON, 120.0, 0.7, 3.0, 0.2)
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
	# 碎裂成星塵消散（美術規格書 3.2 指定的表現）
	_fx.burst(cat.position, 14, Palette.MOON, 95.0, 0.55, 3.0, 0.35)
	_fx.burst(cat.position, 8, Palette.PEARL, 70.0, 0.7, 2.0, 0.25)
	cat.shatter()


## 撞牆。方向性震動 —— 沿撞擊方向抖，玩家才讀得出是撞到哪一邊。
## 不加頓格：頓格會連貓一起停，理論上可以靠撞牆拖慢追兵。
func _on_player_bumped(d: Vector2i) -> void:
	if state == State.PLAYING:
		_juice.kick(0.34, Vector2(d))
		# 撞擊點噴一點碎屑，方向沿著牆面散開
		var n := Vector2(d)
		_fx.burst(player.position + n * 7.0, 5, Palette.WALL_LIGHT,
			55.0, 0.3, 2.0, 0.8, n.angle() + PI, PI * 0.7)


func _lose_life() -> void:
	AudioManager.play_sfx("maze_player_hurt")   # 被暗影猫抓住扣命
	lives -= 1
	# 剛失去的那顆愛心播「1 秒放大 1.5 倍＋淡出」（格位 = 少掉後的 lives）
	_heart_fade = 1.0
	_heart_fade_slot = lives
	# 不加 freeze —— _enter_dying() 本來就把全世界凍 1.2 秒
	_juice.kick(0.90)
	_fx.burst(player.position, 18, Palette.LUNA, 110.0, 0.6, 3.0, 0.6)
	_enter_dying()


func _on_player_ate(_cell: Vector2i, kind: int) -> void:
	match kind:
		Maze.ITEM_BEAN:
			AudioManager.play_sfx("maze_pickup_perl")   # 撿起星塵珍珠
			score += SCORE_BEAN
			beans_eaten += 1
			# 一局 205 顆，所以只給 2 顆極小的閃光 —— 再多就變成整片雜訊
			_fx.burst(player.position, 2, Palette.PEARL, 34.0, 0.26, 2.0, 0.4)
		Maze.ITEM_MOON:
			AudioManager.play_sfx("maze_pickup_heart")   # 撿起月光能量（場上畫成月亮）
			score += SCORE_MOON
			# 撿到不會直接發動，存進 HUD 等玩家按 A（GDD 的 Xbox 協議）
			moon_stock = mini(moon_stock + 1, MOON_STOCK_MAX)
			_juice.kick(0.30)
			_fx.burst(player.position, 12, Palette.MOON, 80.0, 0.5, 3.0, 0.3)
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
	_fx.burst(player.position, 26, Palette.GOLD, 130.0, 0.8, 3.0, 0.5)


# ── 繪製 ────────────────────────────────────────────────

func _draw() -> void:
	# 三層，每層一個位移（見 shared/juice.gd 的分層模型）
	draw_set_transform(_juice.bg_offset())
	_draw_backdrop()
	draw_set_transform(_juice.world_offset())
	# 珍珠畫在這裡；牆改由 _tiler_root 的 TileMap 圖層繪製，露娜與貓由
	# _world 容器位移 —— 讀的都是同一個 world_offset()，所以不會脫格。
	_draw_maze()
	_fx.draw(self)                     # 粒子屬於 WORLD 層
	draw_set_transform(Vector2.ZERO)
	_draw_ui_frame()
	_draw_hud()
	# 收尾暗角／石化閃邊／CAUGHT!／結算壓暗改畫在 _overlay（子節點，
	# 疊在 tile 牆與 Logo 之上、露娜與貓之下），每幀在 _process 重畫。


## 視差層。迷宮的底是 S_MAP.png 全屏背景（1920×1080 美術出圖，4 倍設計稿），
## ÷4 拉伸到 480×270 —— 圖裡的迷宮區域已對齊 Maze.ORIGIN×4，拉伸後正好
## 貼上程式畫的牆（等比縮放，不變形）。
func _draw_backdrop() -> void:
	var m := Juice.OVERDRAW
	draw_rect(Rect2(-m, -m, 480.0 + m * 2.0, 270.0 + m * 2.0), Palette.BG)
	draw_texture_rect(s_bg, Rect2(5, 13, 480, 270), false)
	if not SHOW_STARS:
		return
	# 固定的偽隨機（跟 Fishing/Catch 同一套寫法），不要每幀跳動
	for i in 22:
		var x := fmod(float(i) * 97.0, 468.0) + 6.0
		var y := fmod(float(i) * 53.0, 258.0) + 6.0
		draw_rect(Rect2(x, y, 1, 1), Palette.FAR)


## 全螢幕邊框圖（美術出圖 1920×1080，拉伸到 480×270）。
## 畫在 HUD 文字之下：邊框上緣的實心條不會蓋掉時間／分數。
func _draw_ui_frame() -> void:
	if s_ui_kuang == null:
		return
	draw_texture_rect(s_ui_kuang, Rect2(0, 0, 480, 270), false)


func _draw_maze() -> void:
	# 牆體（障礙塊＋中央 Logo 牆）由 _tiler_root 的 TileMap 圖層繪製，
	# 迷宮外框由 S_MAP 的彩繪邊框承擔；Logo 貼圖在 _logo_view。這裡只畫道具。
	for c in maze.items:
		var center := maze.cell_center(c)
		if maze.items[c] == Maze.ITEM_MOON:
			_draw_centered_texture(s_moon, center, ITEM_SHOW)
		else:
			_draw_centered_texture(s_perl, center, ITEM_SHOW)


## 場上道具（星塵珍珠／月光能量）的顯示尺寸：兩張都是 220×220 美術圖，
## 等比縮到 15px 見方 —— 迷宮格只有 15×15，原尺寸畫下去會蓋掉隔壁格。
## 舊版珍珠是 15×15 原生尺寸，內容物約 11px，縮到 15px 後視覺大小一致。
const ITEM_SHOW := 15.0


func _draw_centered_texture(texture: Texture2D, center: Vector2, size: float) -> void:
	if texture == null:
		return
	draw_texture_rect(texture, Rect2(center - Vector2(size, size) * 0.5,
		Vector2(size, size)), false)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font

	# 左：剩餘時間。最後 10 秒轉警示色，並隨秒數脈動 ——
	# 原本這 10 秒在畫面上完全沒有變化，時間到就突然結束。
	var secs := int(ceil(time_left))
	var urgent := secs <= 10 and state == State.PLAYING
	var time_col := Palette.WARN if secs <= 10 else Palette.LUNA
	var tsize := 20
	if urgent:
		# 每一秒放大一次再縮回去，像心跳
		tsize = int(12.0 + (1.0 - fmod(time_left, 1.0)) * 4.0)
	draw_string(font, Vector2(25, 37), "%d:%02d" % [secs / 60, secs % 60],
		HORIZONTAL_ALIGNMENT_LEFT, -1, tsize, time_col)

	# 中：分數（滾動中的值，不是瞬間跳到位）。背景框在 1920×1080 設計座標
	# (768,70)、文字 baseline (990,92)，除以 4 到邏輯畫面（同 launcher 慣例）。
	var fsize := s_score_frame.get_size() / 4.0
	draw_texture_rect(s_score_frame, Rect2(192.0, 17.5, fsize.x, fsize.y), false)
	draw_string(font, Vector2(213.0, 34.0), " %06d" % int(round(_score_shown)),
		HORIZONTAL_ALIGNMENT_CENTER, fsize.x, 12, Palette.LUNA)

	# 右：生命愛心。HEART.png（80×68 設計稿 ÷4 = 20×17）。剛失去的那顆播
	# 1 秒「放大 1.5 倍＋淡出」，播完後與其他空位一樣畫成暗色愛心。
	var heart_size := s_heart_ui.get_size() / 4.0
	for i in START_LIVES:
		var c := Vector2(404 + i * 22, 30)
		if i < lives:
			_draw_heart(c, heart_size, 1.0)
		elif i == _heart_fade_slot and _heart_fade > 0.0:
			var k := 1.0 - _heart_fade          # 0 → 1
			_draw_heart(c, heart_size * (1.0 + 0.5 * k), 1.0 - k)
		else:
			_draw_heart(c, heart_size, 0.22)

	# 右下角：珍珠進度
	#draw_string(font, Vector2(0, 254), "BEANS %d/%d" % [beans_eaten, beans_total],
	#	HORIZONTAL_ALIGNMENT_RIGHT, 464, 8, Palette.TEXT_DIM)

	# 左下角：囤著的月光能量（最多 2 個）。S_Moon.png（220×220 美術圖縮到
	# 14px 顯示）—— 跟右上的愛心同一套規則：有庫存全亮、空位畫成暗色、
	# 剛用掉的那顆播「放大＋淡出」。間距 20px 比舊程式圓形（r=5、間距 14）寬，
	# 兩顆月亮才不會黏在一起。
	var moon_size := Vector2(14, 14)
	for i in MOON_STOCK_MAX:
		var c := Vector2(24 + i * 20, 258)
		if i < moon_stock:
			_draw_moon(c, moon_size, 1.0)
		elif i == _moon_fade_slot and _moon_fade > 0.0:
			var k := 1.0 - _moon_fade          # 0 → 1
			_draw_moon(c, moon_size * (1.0 + 0.25 * k), 1.0 - k)
		else:
			_draw_moon(c, moon_size, 0.22)
	if moon_stock > 0 and petrify_left <= 0.0:
		draw_string(font, Vector2(30, 250), "PRESS A",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.CAT)

	# 石化倒數與連擊
	if petrify_left > 0.0:
		draw_string(font, Vector2(0, 55), "PETRIFIED %.1f" % petrify_left,
			HORIZONTAL_ALIGNMENT_CENTER, 480, 10, Palette.CAT_DARK)
		if break_chain > 0:
			draw_string(font, Vector2(0, 46), "BREAK x%d" % break_chain,
				HORIZONTAL_ALIGNMENT_CENTER, 480, 10, Palette.BG)


## 狀態覆蓋層（畫在 _overlay 上）：收尾暗角、石化閃邊、被抓提示、結算壓暗。
## 這幾樣得疊在 TileMap 牆與 Logo 之上，又要在露娜與貓之下 —— 本來畫在
## _draw 尾端就夠，牆改成子節點後必須跟著升成子節點才不被蓋住。
func _draw_overlay() -> void:
	_draw_urgency(_overlay)
	_draw_petrify_edge(_overlay)
	if state == State.DYING:
		_draw_center_text(_overlay, "CAUGHT!", 130, 22, Palette.WARN)
	elif state == State.RESULT:
		# 半透明遮罩，讓迷宮沉下去 —— GAME OVER／TIME UP 文字與分數由
		# launcher 的 Game Over 動畫層畫（ui/game_over.gd），這裡只負責
		# 壓暗背景（遊戲節點會保留到動畫播完，見 launcher._open_game_over）。
		# 用色盤的最深夜色壓半透明，不是自己調一個新的深藍
		_overlay.draw_rect(Rect2(0, 0, 480, 270), Color(Palette.NIGHT, 0.82))


## 最後 10 秒的收尾張力：畫面四周壓一圈越來越深的暗角。
## 純粹是氛圍，不擋視線 —— 迷宮的可視範圍完全沒被吃掉。
func _draw_urgency(on: CanvasItem) -> void:
	if state != State.PLAYING or time_left > 10.0:
		return
	var k := (10.0 - time_left) / 10.0        # 0 → 1
	var band := 10.0 + k * 14.0
	var col := Color(Palette.NIGHT, 0.10 + k * 0.28)
	for i in int(band):
		var a := col.a * (1.0 - float(i) / band)
		on.draw_rect(Rect2(i, i, 480 - i * 2, 270 - i * 2), Color(Palette.NIGHT, a), false, 1.0)


## 石化剩 2 秒時畫面邊緣閃爍提示（GDD 的 UI 需求）
func _draw_petrify_edge(on: CanvasItem) -> void:
	if petrify_left <= 0.0 or petrify_left > PETRIFY_WARN:
		return
	if fmod(petrify_left, 0.24) >= 0.12:
		return
	var col := Color(Palette.MOON, 0.75)
	for i in 3:
		on.draw_rect(Rect2(i, i, 480 - i * 2, 270 - i * 2), col, false, 1.0)


func _draw_heart(center: Vector2, size: Vector2, alpha: float) -> void:
	if s_heart_ui == null:
		return
	draw_texture_rect(s_heart_ui, Rect2(center - size * 0.5, size), false,
		Color(1, 1, 1, alpha))


func _draw_moon(center: Vector2, size: Vector2, alpha: float) -> void:
	if s_moon == null:
		return
	draw_texture_rect(s_moon, Rect2(center - size * 0.5, size), false,
		Color(1, 1, 1, alpha))


func _draw_center_text(on: CanvasItem, text: String, y: float, size: int, col: Color) -> void:
	on.draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, 480, size, col)
