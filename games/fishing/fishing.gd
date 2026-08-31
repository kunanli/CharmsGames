extends Node2D

# ─────────────────────────────────────────────────────────
# CharmsFishing —— 黃金礦工式夜釣（依 Guides/CharmsFishing.docx 實作）
#
# 玩家只做一個決定：什麼時候放線。鉤子自己擺，放出去就不能取消，
# 收線速度由勾到的東西決定 —— 所有的取捨都壓在「時間」這一個資源上。
# 沒有生命值，犯錯只會浪費秒數，這是刻意跟 Seeker 的三條命互補。
#
# 畫面分層（GDD）：天空 96px／水下 174px，水面線在 y=96。
# 鉤子支點固定在船底 (240, 96)，±75° 擺動，單趟週期 2.4 秒，
# 最後 15 秒擺速 +15% 製造收尾壓力。
#
# 座標一律用 Vector2（像素）—— 這款沒有格子，不會有 Vector2i 混用問題。
# ─────────────────────────────────────────────────────────

signal round_finished(score: int, duration: float, game_over: bool)

enum State { READY, PLAYING, RESULT }
enum Hook { SWING, EXTEND, RETRACT }
enum Kind { JUNK_FISH, SMALL_PEARL, BIG_FISH, STARDUST, CHARM, ROCK, SHADOW_FISH }

const ROUND_TIME := 60.0
# 開場停頓：ReadyGo 淡入 0.25s＋動畫 24幀@14fps≈1.71s＋0.05s 緩衝（播完才開場）
const READY_TIME := ReadyGo.FADE_SECONDS + ReadyGo.ANIM_SECONDS + 0.05

# ── 畫面配置 ────────────────────────────────────────────
const SCREEN := Vector2(480, 270)
const SURFACE_Y := 96.0                    # 水面線：天空 96 / 水下 174
const PIVOT := Vector2(240.0, 96.0)        # 鉤子支點（船底）
const WATER_L := 6.0
const WATER_R := 474.0
const WATER_B := 266.0

# ── 鉤子 ────────────────────────────────────────────────
const MAX_ANGLE_DEG := 75.0
const SWING_PERIOD := 2.4                  # 一趟來回的秒數
const RUSH_TIME := 15.0                    # 剩幾秒開始加速
const RUSH_SWING := 1.15                   # 擺速 ×1.15
const LINE_MIN := 12.0                     # 待機時的線長
const LINE_MAX := 205.0
const EXTEND_SPEED := 150.0
const RETRACT_EMPTY := 210.0               # 空鉤回收速度

# ── 月光能量 ────────────────────────────────────────────
const MOON_USES := 3
const MOON_BOOST := 3.0                    # 勾到寶物時收線 ×3

# ── 水層（y 範圍）───────────────────────────────────────
# 注意水層不是等面積的：鉤子從 (240,96) 以 ±75° 掃，可及範圍是一個倒三角形，
# 越淺越窄。淺層實際只有約 10000px²（放得下約 13 個），中層與深層各有其兩倍。
# 淺層的物件數要照這個來配，不然會有一堆生不出來。
const SHALLOW := Vector2(112, 158)
const MID := Vector2(162, 208)
const DEEP := Vector2(212, 258)

# ── 族群補充 ────────────────────────────────────────────
# 這些種類撈走後會有新的游進來，回到同一個水層。
#
# 為什麼要有這個：GDD 把星塵珍珠固定 4~5 顆、Charm 固定 2~3 顆，
# 盤面總值上限因此只有約 3070 分 —— 不補充的話，撈得再快也會撞到
# 天花板（模擬過：抓走盤面 91% 的機器人也只有 2800）。
# 有限的寶物（星塵珍珠／Charm）維持 GDD 的固定顆數不動，只讓魚群回補，
# 這樣 60 秒的上限就取決於玩家手速而不是盤面大小，也符合「湖裡的魚會游進來」。
const RESPAWN_DELAY := 2.2
const RESPAWN_KINDS := {
	Kind.JUNK_FISH: SHALLOW,
	Kind.SMALL_PEARL: SHALLOW,
	Kind.BIG_FISH: Vector2(162, 258),
	Kind.ROCK: Vector2(162, 258),
	Kind.SHADOW_FISH: MID,
}


## 水下的一個物件。大魚與暗影猫魚會橫向游動，其餘固定不動。
class Item:
	var kind: int
	var pos := Vector2.ZERO
	var size := Vector2(16, 16)
	var vx := 0.0
	var phase := 0.0        # 呼吸光暈 / 游動擺尾的相位

	func rect() -> Rect2:
		return Rect2(pos - size * 0.5, size)


var state: State = State.READY
var state_timer := READY_TIME
var time_left := ROUND_TIME
var score := 0

var hook_state: Hook = Hook.SWING
var swing_t := 0.0
var angle := 0.0                 # 0 = 正下方，正值往右
var line_len := LINE_MIN
var carried: Item = null         # 正在收線的獵物，空鉤為 null
var moon_left := MOON_USES
var moon_active := false         # 這一趟收線有沒有吃到月光加速

var items: Array[Item] = []
var _respawns: Array = []        # 排隊等著游進來的族群物件
var _defs := {}                  # Kind -> 分數 / 收線速度 / 尺寸 / 顏色
var _rng := RandomNumberGenerator.new()

# 分數飄字
var _pop_text := ""
var _pop_col := Color.WHITE
var _pop_timer := 0.0

# 輸入邊緣偵測（沿用專案慣例：輪詢 Input，不用 _input 事件）
var _prev_cast := false
var _prev_moon := false

# Game feel（見 shared/juice.gd）
var _juice := Juice.new(Juice.ARCADE)
var _fx := Fx.new()                 # 粒子（見 shared/fx.gd）
var _rushed := false                # 最後 15 秒的加速只提示一次
var _line_flash := 0.0              # 勾中時釣線閃一下（GDD 指定的表現）
var _score_shown := 0.0             # HUD 上滾動中的分數

var bg_texture : Texture2D = preload("res://assets/fishing/F_BG.jpg");
var s_ui_kuang: Texture2D = preload("res://assets/UI/UI_KUANG.png")
var s_score_frame: Texture2D = preload("res://assets/UI/SCORE_FRAME.png")
var _textures := {
	Kind.JUNK_FISH: preload("res://assets/catch/CC_04.png"),
	Kind.SMALL_PEARL: preload("res://assets/fishing/F_Perl1.png"),
	Kind.STARDUST: preload("res://assets/fishing/F_stardust.png"),
	Kind.CHARM: preload("res://assets/fishing/F_CHARM.png"),
	Kind.ROCK: preload("res://assets/catch/CC_05.png"),
	Kind.SHADOW_FISH: preload("res://assets/fishing/F_SHADOW_FISH.png"),
	Kind.BIG_FISH: preload("res://assets/fishing/F_SHADOW_FISH.png"),
}

var _item_sizes := {
	Kind.JUNK_FISH: Vector2(30, 30),
	Kind.SMALL_PEARL: Vector2(30, 30),
	Kind.STARDUST: Vector2(35, 35),
	Kind.CHARM: Vector2(20, 20),
	Kind.ROCK: Vector2(40, 40),
	Kind.SHADOW_FISH: Vector2(20, 20),
	Kind.BIG_FISH: Vector2(35, 35),
}




func _ready() -> void:
	_rng.randomize()
	_build_defs()
	_start_round()


## 物件資料表（GDD 的「水下物件表」）
## 收線速度就是 GDD 的「重量」欄位：輕→快、中→普通、重→慢、極重→極慢。
func _build_defs() -> void:
	_defs = {
		Kind.JUNK_FISH:   {"score": 10,  "pull": 165.0, "size": Vector2(16, 16), "col": Palette.WALL,       "label": "FISH"},
		Kind.SMALL_PEARL: {"score": 50,  "pull": 165.0, "size": Vector2(16, 16), "col": Palette.PEARL,      "label": "PEARL"},
		# GDD 寫「大魚 16×32」，但橫向游動的魚應該是寬大於高，
		# 這裡採 32×16。若美術真的要交 16 寬 32 高的直立魚，改這一行即可。
		Kind.BIG_FISH:    {"score": 100, "pull": 58.0,  "size": Vector2(32, 16), "col": Palette.WALL_DARK,  "label": "BIG FISH"},
		Kind.STARDUST:    {"score": 200, "pull": 105.0, "size": Vector2(16, 16), "col": Palette.PEARL,      "label": "STARDUST"},
		Kind.CHARM:       {"score": 500, "pull": 105.0, "size": Vector2(16, 16), "col": Palette.GOLD,       "label": "CHARM"},
		Kind.ROCK:        {"score": 0,   "pull": 34.0,  "size": Vector2(16, 16), "col": Palette.FAR,        "label": "ROCK"},
		Kind.SHADOW_FISH: {"score": 0,   "pull": 105.0, "size": Vector2(16, 16), "col": Palette.CAT,        "label": "-3 SEC"},
	}


func _score_of(k: int) -> int:
	return int(_defs[k]["score"])


func _is_treasure(k: int) -> bool:
	# 月光能量要判斷「寶物還是廢物」：有分數的是寶物，石頭與暗影猫魚是廢物
	return _score_of(k) > 0


# ── 局面控制 ────────────────────────────────────────────

func _start_round() -> void:
	score = 0
	time_left = ROUND_TIME
	moon_left = MOON_USES
	swing_t = 0.0
	_pop_timer = 0.0
	_juice.reset()
	_fx.clear()
	_rushed = false
	_line_flash = 0.0
	_score_shown = 0.0
	_reset_hook()
	_populate()
	state = State.READY
	state_timer = READY_TIME
	ReadyGo.create(self)          # 開場 READY 動畫：淡入→播完→淡出→自行釋放


## 本局結束：把成績交給 launcher，由它提交排行榜並打開面板。
## 發完之後 launcher 會在下一幀釋放本節點，遊戲自己不需要清場。
## duration = 純遊玩秒數（READY 停頓不算），三款一致。
func _finish_round() -> void:
	round_finished.emit(score, ROUND_TIME - time_left, false)


func _reset_hook() -> void:
	hook_state = Hook.SWING
	line_len = LINE_MIN
	carried = null
	moon_active = false


## 依 GDD 的「配置」欄鋪放水下物件。
##
## 星塵珍珠與 Charm 是 GDD 明寫「每局固定 N 顆」的有限寶物，撈完就沒了；
## 雜魚／小珍珠／大魚／石頭／暗影猫魚屬於「族群」，撈走後會有新的游進來
## （見 _schedule_respawn）。這是為了讓 60 秒的計分上限取決於玩家手速，
## 而不是取決於盤面總值 —— 詳見下方 RESPAWN_KINDS 的註解。
func _populate() -> void:
	items.clear()
	_respawns.clear()
	_spawn_many(Kind.JUNK_FISH, 8, SHALLOW)                      # 淺層，數量最多
	_spawn_many(Kind.SMALL_PEARL, 5, SHALLOW)                    # 淺層
	_spawn_many(Kind.BIG_FISH, 4, Vector2(MID.x, DEEP.y))        # 中／深層，會游動
	_spawn_many(Kind.STARDUST, _rng.randi_range(4, 5), MID)      # 中層，固定 4~5 顆
	_spawn_many(Kind.CHARM, _rng.randi_range(2, 3), DEEP)        # 深層，固定 2~3 顆
	_spawn_many(Kind.ROCK, 6, Vector2(MID.x, DEEP.y))            # 中／深層干擾物
	_spawn_many(Kind.SHADOW_FISH, 2, MID)                        # 中層，會主動靠近鉤子


func _spawn_many(kind: int, count: int, band: Vector2) -> void:
	for i in count:
		_spawn_one(kind, band)


## 放一隻到 band 這個水層裡。找不到合法位置就放棄，寧可少一隻也不要疊在一起
## 或是生出一隻永遠撈不到的。
func _spawn_one(kind: int, band: Vector2) -> void:
	var size: Vector2 = _defs[kind]["size"]
	var it := Item.new()
	it.kind = kind
	it.size = size
	it.phase = _rng.randf() * TAU
	if kind == Kind.BIG_FISH:
		it.vx = 20.0 * (1.0 if _rng.randf() < 0.5 else -1.0)
	elif kind == Kind.SHADOW_FISH:
		it.vx = 12.0 * (1.0 if _rng.randf() < 0.5 else -1.0)

	# 兩段式：先要求物件之間留 4px 空隙，真的擠不下就退讓成「不重疊即可」。
	# 不這樣做的話，族群補充在滿場時會靜靜地失敗，魚群會隨著時間越來越稀。
	for margin in [4.0, 0.0]:
		for _try in 40:
			it.pos = Vector2(
				_rng.randf_range(WATER_L + size.x, WATER_R - size.x),
				_rng.randf_range(band.x, band.y))
			if _reachable(it) and not _overlaps(it, margin):
				items.append(it)
				return


## 這個位置鉤得到嗎？
## 兩件事會讓物件變成永遠撈不到的死內容：
##   1. 超出 ±75° 的擺動範圍 —— 淺層最外側的兩端就在錐形外面
##   2. 直線距離超過最大線長 —— 深層最外側會超過 205px
## 兩者都留一點餘裕，免得卡在剛好邊緣。
func _reachable(it: Item) -> bool:
	var d := it.pos - PIVOT
	if d.y <= 0.0:
		return false
	if absf(atan2(d.x, d.y)) > deg_to_rad(MAX_ANGLE_DEG - 4.0):
		return false
	return d.length() <= LINE_MAX - 10.0


func _overlaps(candidate: Item, margin: float) -> bool:
	var r := candidate.rect().grow(margin)
	for other in items:
		if r.intersects(other.rect()):
			return true
	return false


## 族群類的物件被撈走後，隔一段時間會有新的游進來。
func _schedule_respawn(kind: int) -> void:
	if not RESPAWN_KINDS.has(kind):
		return
	_respawns.append({"kind": kind, "timer": RESPAWN_DELAY, "band": RESPAWN_KINDS[kind]})


func _tick_respawns(delta: float) -> void:
	var i := _respawns.size() - 1
	while i >= 0:
		var r: Dictionary = _respawns[i]
		r["timer"] -= delta
		if r["timer"] <= 0.0:
			_spawn_one(int(r["kind"]), r["band"] as Vector2)
			_respawns.remove_at(i)
		i -= 1


func _process(delta: float) -> void:
	# tick() 回 false 代表這一幀在命中頓格中，遊戲邏輯整個停住
	var run := _juice.tick(delta)
	if run:
		_run_state(delta)
		_fx.update(delta)
	if _pop_timer > 0.0:
		_pop_timer -= delta
	if _line_flash > 0.0:
		_line_flash -= delta
	# 分數滾動：小魚幾乎瞬間，Charm（+500）會滾個 0.3 秒
	_score_shown = move_toward(_score_shown, float(score),
		maxf(150.0, absf(float(score) - _score_shown) * 3.0) * delta)
	queue_redraw()


func _run_state(delta: float) -> void:
	_juice.look(Vector2.ZERO)     # PLAYING 會覆寫；其他狀態鏡頭回正
	match state:
		State.READY:
			state_timer -= delta
			if state_timer <= 0.0:
				state = State.PLAYING
		State.PLAYING:
			_tick_play(delta)
		State.RESULT:
			# 結算與重開由 launcher 的排行榜面板接手，這裡只負責發過信號
			pass


func _tick_play(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		state = State.RESULT
		_score_shown = 0.0         # 結算的總分從 0 滾上去
		_finish_round()
		return

	if not _rushed and time_left <= RUSH_TIME:
		_rushed = true
		_juice.kick(0.35)          # 擺速 +15% 的那一刻給個提示

	_read_input()
	_move_items(delta)
	_tick_respawns(delta)

	match hook_state:
		Hook.SWING:
			_swing(delta)
		Hook.EXTEND:
			_extend(delta)
		Hook.RETRACT:
			_retract(delta)


func _read_input() -> void:
	# 放線：A / 空白 / 方向鍵下（GDD 指定 A，方向鍵下為備用）
	var cast_now := (Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_SPACE)
		or Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_ENTER))
	if cast_now and not _prev_cast and hook_state == Hook.SWING:
		hook_state = Hook.EXTEND      # 放出去就不能取消，這是決策的代價
	_prev_cast = cast_now

	# 左右探看湖面。只做水平 —— 垂直漂移會讓 y=96 的水面線上下滑，
	# 在固定鏡頭的釣魚遊戲裡看起來像船在沉。
	var pan := 0.0
	if Input.is_action_pressed("ui_left"):
		pan -= 1.0
	if Input.is_action_pressed("ui_right"):
		pan += 1.0
	_juice.look(Vector2(pan, 0.0))

	# 月光能量：B（X 也接受）。GDD 指定只在收線途中可用。
	var moon_now := Input.is_key_pressed(KEY_B) or Input.is_key_pressed(KEY_X)
	if moon_now and not _prev_moon:
		_use_moon()
	_prev_moon = moon_now


func _use_moon() -> void:
	# 空鉤時按了不扣次數，避免手殘浪費
	if hook_state != Hook.RETRACT or carried == null or moon_left <= 0:
		return
	moon_left -= 1
	if _is_treasure(carried.kind):
		moon_active = true            # 寶物：收線 ×3
		_juice.kick(0.40)
		_juice.freeze(0.08)
		_fx.burst(_hook_pos(), 16, Palette.MOON, 90.0, 0.6, 3.0, 0.15)
		_pop("MOONLIGHT x3", Palette.MOON)
	else:
		carried = null                # 廢物：直接丟掉，空鉤快速收回止損
		moon_active = false
		_juice.kick(0.30)
		_pop("DROPPED", Palette.MOON)


func _swing(delta: float) -> void:
	var rate := RUSH_SWING if time_left <= RUSH_TIME else 1.0
	swing_t += delta * rate
	angle = deg_to_rad(MAX_ANGLE_DEG) * sin(TAU * swing_t / SWING_PERIOD)
	line_len = LINE_MIN


func _hook_dir() -> Vector2:
	# angle = 0 指向正下方，正值往右
	return Vector2(sin(angle), cos(angle))


func _hook_pos() -> Vector2:
	return PIVOT + _hook_dir() * line_len


func _extend(delta: float) -> void:
	line_len += EXTEND_SPEED * delta
	var tip := _hook_pos()

	# 碰到任何物件即自動回收
	for it in items:
		if it.rect().has_point(tip):
			AudioManager.play_sfx("fishing_catch")   # 魚鉤撞上任何物件
			carried = it
			carried.pos = tip + Vector2(0, 6)
			items.erase(it)
			_schedule_respawn(it.kind)   # 族群類的，讓新的一隻在收線期間游進來
			# 力道與重量成反比（pull 就是 GDD 的重量欄）：還沒看清楚就先
			# 感覺到鉤到什麼。石頭最重最慢最不值錢，撞得最兇。
			var pull := float(_defs[it.kind]["pull"])
			var hit := clampf(0.75 - pull / 320.0, 0.20, 0.75)
			_juice.kick(hit, _hook_dir())
			_juice.freeze(0.05 + hit * 0.10)
			_line_flash = 0.14
			# 水中的碎屑：重力壓很低，看起來才像在水裡飄而不是掉下去
			_fx.burst(tip, int(6 + hit * 10), Palette.WALL_LIGHT,
				40.0 + hit * 50.0, 0.5, 2.0, 0.12)
			hook_state = Hook.RETRACT
			return

	# 到最大長度或碰到水域邊界就空手收回
	if (line_len >= LINE_MAX or tip.x <= WATER_L or tip.x >= WATER_R
			or tip.y >= WATER_B):
		hook_state = Hook.RETRACT


func _retract(delta: float) -> void:
	var speed := RETRACT_EMPTY
	if carried != null:
		speed = float(_defs[carried.kind]["pull"])
		if moon_active:
			speed *= MOON_BOOST

	line_len -= speed * delta
	if line_len > LINE_MIN:
		if carried != null:
			carried.pos = _hook_pos() + Vector2(0, 6)   # 獵物跟著鉤子走
		return

	# 收回船上，這時才結算
	line_len = LINE_MIN
	if carried != null:
		_land(carried)
	else:
		# 空鉤的失落感。放在這裡而不是 _reset_hook() ——
		# 後者也被 _start_round() 呼叫，會變成每局開場都震一下。
		_juice.kick(0.20, Vector2.UP)
	_reset_hook()


## 獵物上船：加分或扣時間
func _land(it: Item) -> void:
	if it.kind == Kind.SHADOW_FISH:
		AudioManager.play_sfx("fishing_boom")        # 暗影猫魚：扣時間
		time_left = maxf(0.0, time_left - 3.0)
		_juice.kick(0.80)
		_juice.freeze(0.12)
		_fx.burst(PIVOT, 16, Palette.WARN, 100.0, 0.6, 3.0, 0.7)
		_pop("-3 SEC", Palette.WARN)
	else:
		var gained := _score_of(it.kind)
		score += gained
		if gained > 0:
			AudioManager.play_sfx("fishing_gainpoints")   # 上船加分
			var col: Color = Palette.GOLD if it.kind == Kind.CHARM else Palette.TEXT
			if it.kind == Kind.CHARM:
				_juice.kick(0.55)
				_juice.freeze(0.10)
				_fx.burst(PIVOT, 22, Palette.GOLD, 115.0, 0.75, 3.0, 0.55)
			elif it.kind == Kind.STARDUST:
				_juice.kick(0.35)
				_juice.freeze(0.05)
				_fx.burst(PIVOT, 12, Palette.PEARL, 85.0, 0.55, 2.0, 0.5)
			else:
				_fx.burst(PIVOT, 5, Palette.TEXT, 55.0, 0.35, 2.0, 0.6)
			_pop("+%d" % gained, col)
		else:
			_pop("+0", Palette.TEXT_DIM)


func _pop(text: String, col: Color) -> void:
	_pop_text = text
	_pop_col = col
	_pop_timer = 0.9


func _move_items(delta: float) -> void:
	var tip := _hook_pos()
	var line_out := hook_state != Hook.SWING
	for it in items:
		it.phase += delta
		if it.vx == 0.0:
			continue

		if it.kind == Kind.SHADOW_FISH and line_out:
			# 全場唯一會主動靠近鉤子的目標：線放出來時往鉤頭靠
			var toward := signf(tip.x - it.pos.x)
			it.pos.x += toward * 26.0 * delta
			it.pos.y += signf(tip.y - it.pos.y) * 10.0 * delta
		else:
			it.pos.x += it.vx * delta

		# 碰到水域左右邊界就掉頭
		var half := it.size.x * 0.5
		if it.pos.x < WATER_L + half:
			it.pos.x = WATER_L + half
			it.vx = absf(it.vx)
		elif it.pos.x > WATER_R - half:
			it.pos.x = WATER_R - half
			it.vx = -absf(it.vx)
		it.pos.y = clampf(it.pos.y, SURFACE_Y + 14.0, WATER_B - 6.0)


# ── 繪製 ────────────────────────────────────────────────

func _draw() -> void:
	# 三層，每層一個位移（見 shared/juice.gd 的分層模型）
	draw_set_transform(_juice.bg_offset())
	_draw_sky()                        # 天空／月亮／星星／遠山：視差層
	draw_set_transform(_juice.world_offset())
	#_draw_water()                      # 水面線跟世界同步，船才不會浮起來
	for it in items:
		_draw_item(it)
	_draw_line_and_hook()
	_draw_boat()
	_fx.draw(self)                     # 粒子屬於 WORLD 層
	draw_set_transform(Vector2.ZERO)
	_draw_ui_frame()
	_draw_hud()
	_draw_urgency()

	if state == State.RESULT:
		_draw_result()


## 全螢幕邊框圖（美術出圖 1920×1080，拉伸到 480×270）。
## 畫在 HUD 文字之下：邊框上緣的實心條不會蓋掉時間／分數。
## 放在位移恆為 0 的 HUD 層 —— 左右探看湖面時邊框不會跟著畫面飄。
func _draw_ui_frame() -> void:
	if s_ui_kuang == null:
		return
	draw_texture_rect(s_ui_kuang, Rect2(0, 0, 480, 270), false)


## 視差層。天空底色要往下延伸超過水面線 —— 水體是畫在 WORLD 層的，
## 兩層分離時如果天空只畫到 y=96，水面線附近就會裂開一條沒人畫的縫。
func _draw_sky() -> void:
	var m := Juice.OVERDRAW
	draw_rect(Rect2(-m, -m, SCREEN.x + m * 2.0, SURFACE_Y + m * 2.0), Palette.BG)
	# 彎月
	draw_circle(Vector2(402, 30), 13.0, Palette.MOON)
	draw_circle(Vector2(396, 26), 12.0, Palette.BG)
	# 星點（用相位固定的偽隨機，不要每幀跳動）
	for i in 26:
		var x := fmod(float(i) * 79.0, 470.0) + 5.0
		var y := fmod(float(i) * 37.0, 74.0) + 6.0
		draw_rect(Rect2(x, y, 1, 1), Palette.PEARL)
	# 遠山剪影：多跑一輪並往左移，補上多畫出來的那一圈
	for i in 8:
		var bx := float(i) * 72.0 - 10.0 - Juice.OVERDRAW
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx, SURFACE_Y), Vector2(bx + 38, SURFACE_Y - 26),
			Vector2(bx + 76, SURFACE_Y)]), Palette.FAR)
			
	draw_texture_rect(bg_texture, Rect2(2, 15, SCREEN.x -2, SCREEN.y - 10), false)


## 水體屬於 WORLD 而不是背景 —— 船釘在水面線上，兩者必須共用同一個位移。
#func _draw_water() -> void:
#	var m := Juice.OVERDRAW
#	draw_rect(Rect2(-m, SURFACE_Y, SCREEN.x + m * 2.0, SCREEN.y - SURFACE_Y + m),
#		Palette.NIGHT)
#	draw_line(Vector2(-m, SURFACE_Y), Vector2(SCREEN.x + m, SURFACE_Y),
#		Palette.WALL_DARK, 1.0)
#	# 三條水層分隔線，讓深度一眼可讀
#	for y: float in [SHALLOW.y + 4.0, MID.y + 4.0]:
#		draw_line(Vector2(-m, y), Vector2(SCREEN.x + m, y), Palette.FAR, 1.0)

func _draw_centered_texture(
		texture: Texture2D,
		center: Vector2,
		size: Vector2
	) -> void:

	if texture == null:
		return

	draw_texture_rect(
		texture,
		Rect2(center - size * 0.5, size),
		false
	)

func _draw_item(it: Item) -> void:
	var texture: Texture2D = _textures.get(it.kind)
	if texture == null:
		return

	var size : Vector2 = _item_sizes.get(it.kind, texture.get_size())
	_draw_centered_texture(texture, it.pos, size)




func _draw_line_and_hook() -> void:
	var tip := _hook_pos()
	# 星光釣線：亮青白 1px。勾中的瞬間整條線閃一次白（GDD 指定）。
	var line_col: Color = Palette.TEXT if _line_flash > 0.0 else Palette.MOON
	var line_w := 2.0 if _line_flash > 0.0 else 1.0
	draw_line(PIVOT, tip, line_col, line_w)
	# 鉤頭是小星星
	draw_circle(tip, 2.5, Palette.TEXT)
	draw_rect(Rect2(tip.x - 3.5, tip.y - 0.5, 7, 1), Palette.MOON)
	draw_rect(Rect2(tip.x - 0.5, tip.y - 3.5, 1, 7), Palette.MOON)
	# 掛在鉤上的獵物。位置在 _extend()/_retract() 更新，
	# **不要在這裡改** —— _draw() 裡改遊戲狀態的話，鏡頭位移會被寫進
	# carried.pos 再被 _retract() 讀回去，讓獵物的真實位置被污染。
	if carried != null:
		_draw_item(carried)


func _draw_boat() -> void:
	# 船身
	draw_colored_polygon(PackedVector2Array([
		Vector2(212, SURFACE_Y - 10), Vector2(268, SURFACE_Y - 10),
		Vector2(260, SURFACE_Y), Vector2(220, SURFACE_Y)]), Palette.NEAR)
	draw_line(Vector2(212, SURFACE_Y - 10), Vector2(268, SURFACE_Y - 10),
		Palette.WALL_DARK, 1.0)
	# 露娜（坐姿 placeholder）＋帽上的心形徽章
	draw_rect(Rect2(233, SURFACE_Y - 26, 14, 16), Palette.LUNA, false, 1.0)
	draw_rect(Rect2(230, SURFACE_Y - 32, 20, 6), Palette.LUNA)
	draw_rect(Rect2(239, SURFACE_Y - 31, 2, 2), Palette.LUNA_LIGHT)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var secs := int(ceil(time_left))
	var time_col: Color = Palette.WARN if secs <= 10 else Palette.LUNA
	# 最後 10 秒每秒脈動一次，像心跳
	var tsize := 20
	if secs <= 10 and state == State.PLAYING:
		tsize = int(12.0 + (1.0 - fmod(time_left, 1.0)) * 4.0)
	draw_string(font, Vector2(25, 37), "%d:%02d" % [secs / 60, secs % 60],
		HORIZONTAL_ALIGNMENT_LEFT, -1, tsize, time_col)
	# 中：分數（滾動中的值）。背景框在 1920×1080 設計座標 (768,70)、
	# 文字 baseline (990,92)，除以 4 到邏輯畫面（同 launcher 慣例）。
	var fsize := s_score_frame.get_size() / 4.0
	draw_texture_rect(s_score_frame, Rect2(192.0, 17.5, fsize.x, fsize.y), false)
	draw_string(font, Vector2(215.0, 34.0), "%06d" % int(round(_score_shown)),
		HORIZONTAL_ALIGNMENT_CENTER, fsize.x, 12, Palette.LUNA)
	# 鉤子深度（水面下幾 px）
	var depth := int(maxf(0.0, _hook_pos().y - SURFACE_Y))
	draw_string(font, Vector2(0, 18), "DEPTH %03d" % depth,
		HORIZONTAL_ALIGNMENT_RIGHT, SCREEN.x - 12, 12, Palette.TEXT_DIM)

	# 月光能量剩餘次數：右下三顆月亮
	for i in MOON_USES:
		var c := Vector2(432 + i * 14, 254)
		if i < moon_left:
			draw_circle(c, 5.0, Palette.MOON)
			draw_circle(c + Vector2(-2, -1), 4.0, Palette.NIGHT)
		else:
			draw_circle(c, 5.0, Palette.FAR)

	if _pop_timer > 0.0:
		# 飄字：越接近消失越往上飄
		var rise := (0.9 - _pop_timer) * 18.0
		_center(_pop_text, 150 - rise, 16, _pop_col)


## 最後 10 秒的收尾張力：四周壓一圈越來越深的暗角。純氛圍，不擋視線。
func _draw_urgency() -> void:
	if state != State.PLAYING or time_left > 10.0:
		return
	var k := (10.0 - time_left) / 10.0
	var band := 10.0 + k * 14.0
	var base := 0.10 + k * 0.28
	for i in int(band):
		var a := base * (1.0 - float(i) / band)
		draw_rect(Rect2(i, i, SCREEN.x - i * 2, SCREEN.y - i * 2),
			Color(Palette.NIGHT, a), false, 1.0)


func _draw_result() -> void:
	# 壓暗背景 —— TIME UP 文字與分數由 launcher 的 Game Over 動畫層畫
	# （ui/game_over.gd），這裡只負責讓遊戲場景沉下去
	# （遊戲節點會保留到動畫播完，見 launcher._open_game_over）。
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(Palette.NIGHT, 0.82))


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, col)
