extends Node2D

# ─────────────────────────────────────────────────────────
# Milestone 3c：三隻暗影猫，各自不同的追擊個性
#
# 狀態機：READY（開場停頓）→ PLAYING（計時中）→ DYING（被抓到）→ RESULT（結算）
# 被抓到時分數與剩餘時間都保留，只是位置重置；三條命用完才結束。
#
# 三隻貓的個性寫在 cat.gd，這裡只負責生出來、擺位置、每幀餵目標。
# 出生格排在迷宮中央同一條走道上，登場時間錯開 0 / 2.5 / 5 秒，
# 不然三隻會同時撲過來，開場就沒得玩。
# ─────────────────────────────────────────────────────────

enum State { READY, PLAYING, DYING, RESULT }

const ROUND_TIME := 60.0      # 一局的秒數
const READY_TIME := 1.5       # 開場停頓秒數
const DYING_TIME := 1.2       # 被抓到後的停頓秒數
const CATCH_DIST := 9.0       # 碰撞判定距離（px），約半格多一點
const START_LIVES := 3

const SCORE_BEAN := 10
const SCORE_MOON := 30
const SCORE_CLEAR := 500      # 清空全場珍珠的獎勵

# 寶箱門檻（企劃書：1500 / 3000 / 5000）
const CHEST_BRONZE := 1500
const CHEST_SILVER := 3000
const CHEST_GOLD := 5000

const COL_BG := Color("1E1C46")
const COL_WALL := Color("6E82D2")
const COL_BEAN := Color("F0E2B4")
const COL_MOON := Color("A0DCFF")
const COL_TEXT := Color("F0F4FF")
const COL_DIM := Color("8890C0")
const COL_LIFE := Color("EEB4D2")
const COL_WARN := Color("FF9A6A")
const COL_GOLD := Color("FFD37A")

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


func _ready() -> void:
	maze = Maze.new()

	player = Player.new()
	add_child(player)
	player.ate.connect(_on_player_ate)

	# 直追的先出場，預判的稍後補上形成夾擊，遊蕩的最後才放出來
	_spawn_cat(Cat.Kind.CHASER, Vector2i(13, 6), 0.0)
	_spawn_cat(Cat.Kind.AMBUSHER, Vector2i(12, 6), 2.5)
	_spawn_cat(Cat.Kind.WANDERER, Vector2i(14, 6), 5.0)

	_start_round()


## M5 之後會在遊戲中途再呼叫這個加貓，所以生成邏輯集中在這裡
func _spawn_cat(kind: Cat.Kind, home: Vector2i, delay: float) -> Cat:
	var cat := Cat.new()
	cat.configure(kind, home, delay)
	add_child(cat)
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
	_enter_ready()


func _enter_ready() -> void:
	state = State.READY
	state_timer = READY_TIME
	player.setup(maze, Maze.PLAYER_START)
	player.reset_direction()
	player.set_process(false)      # 開場停頓期間不能動
	player.visible = true
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
	match state:
		State.READY:
			state_timer -= delta
			if state_timer <= 0.0:
				_enter_playing()
		State.PLAYING:
			# 每幀把露娜的位置與朝向交給每一隻貓，各自算自己的目標格
			for cat in cats:
				cat.update_target(player.cell, player.dir, delta)
			time_left -= delta
			if time_left <= 0.0:
				time_left = 0.0
				_enter_result()
			elif _check_caught():
				_lose_life()
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

	queue_redraw()


## 露娜與任何一隻暗影猫距離夠近就算被抓到
func _check_caught() -> bool:
	for cat in cats:
		if player.position.distance_to(cat.position) < CATCH_DIST:
			return true
	return false


func _lose_life() -> void:
	lives -= 1
	_enter_dying()


func _on_player_ate(_cell: Vector2i, kind: int) -> void:
	match kind:
		Maze.ITEM_BEAN:
			score += SCORE_BEAN
			beans_eaten += 1
		Maze.ITEM_MOON:
			score += SCORE_MOON
			# M4 會在這裡觸發石化狀態
	if beans_eaten >= beans_total:
		_refill()


## 清空全場：重鋪珍珠並給獎勵（M5 會在這裡再加一隻暗影猫）
func _refill() -> void:
	maze.reset_items()
	maze.items.erase(player.cell)
	beans_total = maze.bean_count()
	beans_eaten = 0
	score += SCORE_CLEAR


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
	draw_rect(Rect2(0, 0, 480, 270), COL_BG)
	_draw_maze()
	_draw_hud()

	if state == State.READY:
		_draw_center_text("READY!", 130, 24, COL_GOLD)
	elif state == State.DYING:
		_draw_center_text("CAUGHT!", 130, 22, COL_WARN)
	elif state == State.RESULT:
		_draw_result()


func _draw_maze() -> void:
	var o := Vector2(Maze.ORIGIN)
	var t := float(Maze.TILE)
	draw_rect(Rect2(o, Vector2(Maze.COLS, Maze.ROWS) * t), COL_WALL, false, 1.0)
	for b in Maze.BLOCKS:
		draw_rect(Rect2(o + Vector2(b.position) * t, Vector2(b.size) * t), COL_WALL, false, 1.0)

	for c in maze.items:
		var center := maze.cell_center(c)
		if maze.items[c] == Maze.ITEM_MOON:
			draw_circle(center, 4.0, COL_MOON)
		else:
			draw_circle(center, 1.5, COL_BEAN)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font

	# 左：剩餘時間，最後 10 秒轉為警示色
	var secs := int(ceil(time_left))
	var time_col := COL_WARN if secs <= 10 else COL_TEXT
	draw_string(font, Vector2(16, 20), "TIME %d:%02d" % [secs / 60, secs % 60],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, time_col)

	# 中：分數
	draw_string(font, Vector2(0, 20), "SCORE %06d" % score,
		HORIZONTAL_ALIGNMENT_CENTER, 480, 12, COL_TEXT)

	# 右：生命（三顆圓點）
	for i in lives:
		draw_circle(Vector2(400 + i * 12, 16), 3.5, COL_LIFE)

	# 右下角：珍珠進度
	draw_string(font, Vector2(0, 264), "BEANS %d/%d" % [beans_eaten, beans_total],
		HORIZONTAL_ALIGNMENT_RIGHT, 464, 8, COL_DIM)


func _draw_result() -> void:
	# 半透明遮罩，讓迷宮沉下去
	draw_rect(Rect2(0, 0, 480, 270), Color(0.06, 0.05, 0.16, 0.82))

	var title := "GAME OVER" if game_over else "TIME UP"
	var title_col := COL_WARN if game_over else COL_GOLD
	_draw_center_text(title, 96, 22, title_col)
	_draw_center_text("SCORE  %06d" % score, 134, 18, COL_TEXT)
	_draw_center_text(chest_tier(), 162, 14, COL_MOON)
	_draw_center_text("PRESS ENTER TO PLAY AGAIN", 200, 10, COL_DIM)


func _draw_center_text(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, 480, size, col)
