extends Node2D

# ─────────────────────────────────────────────────────────
# Charm Catch —— 接珠寶躲炸彈（依 Guides/CharmsCatch.docx 實作）
#
# 三款中最直覺的一款：只有左右兩個方向。張力全靠 Combo 倍率與
# 每 15 秒一跳的落速撐出來。
#
# GDD 的數字跟舊版 CLAUDE.md 有出入，這裡一律以 GDD 為準：
#   基礎速度 60 px/s（不是 92），A 鍵衝刺 ×1.8 且鬆開後有 0.5 秒冷卻，
#   6 條軌道每軌 80px，同軌連續生成間隔不得低於 0.6 秒。
#
# 座標一律用 Vector2（像素）。
# ─────────────────────────────────────────────────────────

enum State { READY, PLAYING, RESULT }
enum Kind { JEWEL, STARDUST, CHARM, BOMB, MOON }

const ROUND_TIME := 60.0
const READY_TIME := 1.5
const SCREEN := Vector2(480, 270)

# ── 露娜 ────────────────────────────────────────────────
const MOVE_SPEED := 60.0            # GDD：基礎 60 px/s
const DASH_MULT := 1.8              # 按住 A 衝刺 ×1.8
const DASH_COOLDOWN := 0.5          # 鬆開後 0.5 秒冷卻
const LUNA_Y := 236.0               # 站立的地面線
const BASKET := Vector2(36, 8)      # 提籃頂面判定框 36×8
const BASKET_DY := -14.0            # 判定框相對露娜中心的高度

# ── 掉落區 ──────────────────────────────────────────────
const LANES := 6
const LANE_W := 80.0                # 6 × 80 = 480
const LANE_MIN_GAP := 0.6           # 同一軌道連續生成的最小間隔
const SPAWN_Y := -10.0
const KILL_Y := 262.0               # 掉到這條線以下就算漏接

# ── 生命與護盾 ──────────────────────────────────────────
const START_LIVES := 3
const SHIELD_TIME := 8.0
const SHIELD_WARN := 2.0            # 剩 2 秒開始閃爍
const MOON_MAX_PER_ROUND := 3       # 每局最多出現 3 個月光能量

# ── Combo ───────────────────────────────────────────────
const COMBO_STEP := 5               # 每 5 連 +1 倍率
const COMBO_MAX := 5                # 上限 ×5

# ── 寶箱門檻（GDD：1500 / 3000 / 5000，與 Seeker 同）────
const CHEST_BRONZE := 1500
const CHEST_SILVER := 3000
const CHEST_GOLD := 5000

# ── 難度曲線（GDD 表格，每 15 秒一段）───────────────────
# 落速 / 同屏上限 / 炸彈比例 / Charm 出現率倍數 / 生成間隔
#
# 前四欄照抄 GDD。gap（生成間隔）是 GDD 沒寫的，必須另外定 ——
# 「同屏上限」是上限不是目標：一路生到頂會變成每秒掉 2.6 顆，
# 一局灑出 57 顆有價物而玩家最多接得到 24 顆（43%），
# 於是平均每 3.8 秒斷一次 Combo，但疊到 ×2 需要連續 12 秒不漏。
# 結果就是 Combo 這個「拉開分差的關鍵」整局都停在 ×1。
# 把生成間隔獨立出來、讓同屏數平常低於上限，上限只在爆量時才咬到，
# 才是「上限」該有的語意。難度遞增仍然由落速與炸彈比例負責。
const PHASES := [
	{"speed": 60.0,  "max_on": 2, "bomb": 0.10, "charm_mult": 1.0, "gap": Vector2(1.6, 2.2)},
	{"speed": 80.0,  "max_on": 3, "bomb": 0.20, "charm_mult": 1.0, "gap": Vector2(1.4, 2.0)},
	{"speed": 100.0, "max_on": 4, "bomb": 0.30, "charm_mult": 1.0, "gap": Vector2(1.2, 1.8)},
	{"speed": 120.0, "max_on": 5, "bomb": 0.35, "charm_mult": 2.0, "gap": Vector2(1.0, 1.5)},
]
const PHASE_LEN := 15.0
const CHARM_EVERY := 15.0           # Charm 每 15 秒必定出現 1 個


## 一顆掉落物
class Drop:
	var kind: int
	var pos := Vector2.ZERO
	var lane := 0
	var phase := 0.0

	func rect() -> Rect2:
		return Rect2(pos - Vector2(8, 8), Vector2(16, 16))


var state: State = State.READY
var state_timer := READY_TIME
var time_left := ROUND_TIME
var score := 0
var lives := START_LIVES
var combo := 0                      # 連續接到有價物的次數
var multiplier := 1

var luna_x := 240.0
var dash_cd := 0.0
var was_dashing := false

var shield_left := 0.0
var moons_spawned := 0

var drops: Array[Drop] = []
var _lane_last: Array[float] = []   # 每軌上次生成後過了幾秒
var _spawn_timer := 0.0
var _charm_timer := CHARM_EVERY
var _rng := RandomNumberGenerator.new()

var _flash := 0.0                   # 吃到炸彈的紅閃
var _pop_text := ""
var _pop_col := Color.WHITE
var _pop_timer := 0.0
var _pop_at := Vector2.ZERO

var _prev_burst := false

# Game feel（見 shared/juice.gd）。位移只作用在繪製，不碰任何遊戲數值。
var _juice := Juice.new(Juice.ARCADE)
var _at_wall := false               # 去抖：貼著邊界時只在「剛撞上」那一幀 kick
var _last_phase := 0


func _ready() -> void:
	_rng.randomize()
	_start_round()


func _start_round() -> void:
	score = 0
	lives = START_LIVES
	combo = 0
	multiplier = 1
	time_left = ROUND_TIME
	luna_x = 240.0
	dash_cd = 0.0
	shield_left = 0.0
	moons_spawned = 0
	drops.clear()
	_lane_last.clear()
	for i in LANES:
		_lane_last.append(LANE_MIN_GAP)
	_spawn_timer = 0.6
	_charm_timer = CHARM_EVERY
	_flash = 0.0
	_pop_timer = 0.0
	_juice.reset()
	_at_wall = false
	_last_phase = 0
	state = State.READY
	state_timer = READY_TIME


# ── 難度分段 ────────────────────────────────────────────

func _phase_index() -> int:
	var elapsed := ROUND_TIME - time_left
	return clampi(int(elapsed / PHASE_LEN), 0, PHASES.size() - 1)


func _phase() -> Dictionary:
	return PHASES[_phase_index()]


func _process(delta: float) -> void:
	# tick() 回 false 代表這一幀在命中頓格中，遊戲邏輯整個停住。
	# 純表現用的計時器留在下面、不受影響。
	var run := _juice.tick(delta)
	if run:
		_run_state(delta)

	if _pop_timer > 0.0:
		_pop_timer -= delta
	if _flash > 0.0:
		_flash -= delta
	queue_redraw()


func _run_state(delta: float) -> void:
	match state:
		State.READY:
			state_timer -= delta
			if state_timer <= 0.0:
				state = State.PLAYING
		State.PLAYING:
			_tick_play(delta)
		State.RESULT:
			if Input.is_action_just_pressed("ui_accept"):
				_start_round()


func _tick_play(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		state = State.RESULT
		return

	var ph_now := _phase_index()
	if ph_now != _last_phase:
		_last_phase = ph_now
		_juice.kick(0.32)          # 每 15 秒一次的段落推進，給一個節奏點

	_move_luna(delta)
	_tick_shield(delta)
	_tick_spawn(delta)
	_move_drops(delta)


# ── 露娜 ────────────────────────────────────────────────

func _move_luna(delta: float) -> void:
	var dir := 0.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_LEFT):
		dir -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_RIGHT):
		dir += 1.0

	# 衝刺：按住 A。放開才開始算 0.5 秒冷卻，冷卻中按了也沒用。
	var want_dash := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_SHIFT)
	if dash_cd > 0.0:
		dash_cd -= delta
	var dashing := want_dash and dash_cd <= 0.0
	if was_dashing and not dashing:
		dash_cd = DASH_COOLDOWN
	was_dashing = dashing

	var speed := MOVE_SPEED * (DASH_MULT if dashing else 1.0)
	# 走到畫面邊界：撞上去的那一幀給一記水平震動，貼著不放不會重複觸發。
	# 衝刺撞牆比走路撞牆更兇 —— 撞得多用力，地圖就晃多大。
	var want_x := luna_x + dir * speed * delta
	var clamped := clampf(want_x, 12.0, SCREEN.x - 12.0)
	if dir != 0.0 and not is_equal_approx(want_x, clamped):
		if not _at_wall:
			_juice.kick(0.55 if dashing else 0.34, Vector2.RIGHT)
			_juice.freeze(0.05 if dashing else 0.03)
		_at_wall = true
	else:
		_at_wall = false
	luna_x = clamped
	# 鏡頭往移動方向偏一點。只做水平 —— 垂直會讓露娜跟地面線脫開。
	_juice.look(Vector2(dir, 0.0))

	# 主動引爆護盾：清掉畫面上所有炸彈但不加分
	var burst := Input.is_key_pressed(KEY_B) or Input.is_key_pressed(KEY_X)
	if burst and not _prev_burst:
		_burst_shield()
	_prev_burst = burst


func _burst_shield() -> void:
	if shield_left <= 0.0:
		return
	var cleared := 0
	var kept: Array[Drop] = []
	for d in drops:
		if d.kind == Kind.BOMB:
			cleared += 1
		else:
			kept.append(d)
	drops = kept
	shield_left = 0.0
	if cleared > 0:
		_juice.kick(minf(0.45 + 0.06 * cleared, 0.80))
		_juice.freeze(0.12)
		_pop("BURST! x%d" % cleared, Palette.MOON, Vector2(240, 150))


func _tick_shield(delta: float) -> void:
	if shield_left > 0.0:
		shield_left = maxf(0.0, shield_left - delta)


func _basket_rect() -> Rect2:
	# 判定只看提籃頂面，從側邊擦過不算
	return Rect2(luna_x - BASKET.x * 0.5, LUNA_Y + BASKET_DY, BASKET.x, BASKET.y)


# ── 掉落物 ──────────────────────────────────────────────

func _tick_spawn(delta: float) -> void:
	for i in LANES:
		_lane_last[i] += delta

	_charm_timer -= delta
	_spawn_timer -= delta

	var ph := _phase()
	if drops.size() >= int(ph["max_on"]):
		return

	# Charm 每 15 秒必定出現一個，優先於一般生成
	if _charm_timer <= 0.0:
		if _spawn(Kind.CHARM):
			_charm_timer = CHARM_EVERY
		return

	if _spawn_timer > 0.0:
		return
	if _spawn(_roll_kind(ph)):
		var gap: Vector2 = ph["gap"]
		_spawn_timer = _rng.randf_range(gap.x, gap.y)


## 依 GDD 的比例抽一個掉落物種類
func _roll_kind(ph: Dictionary) -> int:
	if _rng.randf() < float(ph["bomb"]):
		return Kind.BOMB
	# 月光能量每局最多 3 個
	if moons_spawned < MOON_MAX_PER_ROUND and _rng.randf() < 0.06:
		return Kind.MOON
	# 末段 Charm 出現率 ×2（必定出現的那一個之外的額外機會）
	if _rng.randf() < 0.04 * float(ph["charm_mult"]):
		return Kind.CHARM
	# 其餘是珠寶與星塵珍珠，珠寶出現率最高
	return Kind.JEWEL if _rng.randf() < 0.72 else Kind.STARDUST


## 找一條「距離上次生成夠久」的軌道放下去。找不到就這幀不生成。
##
## 有價物還多一條限制：必須落在「接得到前一顆之後還追得上」的範圍內。
## 為什麼需要這條 —— GDD 的三個數字互相打架：
##   同屏上限 2~5 顆、露娜 60 px/s 一趟只夠橫move 1.4~2.9 軌、漏接有價物 Combo 歸零。
## 三者同時成立時，兩顆珠寶只要落在相隔夠遠的軌道就必定漏一顆，Combo 永遠斷。
## 模擬結果：40 局裡有 35 局最高倍率停在 ×1，從沒超過 ×2 ——
## GDD 說 Combo 是「拉開分差的關鍵」，實際上整個機制是死的。
##
## 這裡只約束「有價物之間」的距離，炸彈照樣愛落哪就落哪。
## 這樣 Combo 變成考驗走位的真本事，而「該不該去搶那顆」的抉擇仍然存在 ——
## 逼你繞路的是炸彈與衝刺冷卻，不是骰子。
func _spawn(kind: int) -> bool:
	var candidates: Array[int] = []
	for i in LANES:
		if _lane_last[i] >= LANE_MIN_GAP:
			candidates.append(i)
	if candidates.is_empty():
		return false

	if _is_valuable(kind):
		var chain := _chain_filter(candidates)
		if not chain.is_empty():
			candidates = chain

	var lane: int = candidates[_rng.randi_range(0, candidates.size() - 1)]
	var d := Drop.new()
	d.kind = kind
	d.lane = lane
	d.phase = _rng.randf() * TAU
	# 在軌道內隨機偏移，但留邊避免半顆貼到畫面外
	d.pos = Vector2(lane * LANE_W + _rng.randf_range(14.0, LANE_W - 14.0), SPAWN_Y)
	drops.append(d)
	_lane_last[lane] = 0.0
	if kind == Kind.MOON:
		moons_spawned += 1
	return true


func _is_valuable(kind: int) -> bool:
	return kind != Kind.BOMB


## 已經在飛的有價物裡，最快落地的那一顆。沒有就回 null。
func _most_urgent_valuable() -> Drop:
	var best: Drop = null
	for d in drops:
		if not _is_valuable(d.kind):
			continue
		if best == null or d.pos.y > best.pos.y:
			best = d
	return best


## 從 candidates 篩出「接完前一顆還追得上」的軌道。
## 時間差 × 衝刺速度就是這段空檔能移動的距離，留 0.85 的安全係數，
## 因為玩家不會每次都走最佳路線，而且衝刺還有冷卻。
func _chain_filter(candidates: Array[int]) -> Array[int]:
	var urgent := _most_urgent_valuable()
	if urgent == null:
		return []

	var speed := float(_phase()["speed"])
	var catch_y := LUNA_Y + BASKET_DY
	var t_urgent := (catch_y - urgent.pos.y) / speed
	var t_new := (catch_y - SPAWN_Y) / speed
	var window := t_new - t_urgent
	if window <= 0.0:
		return []

	var reach := MOVE_SPEED * DASH_MULT * window * 0.85
	var out: Array[int] = []
	for i in candidates:
		var lane_center := i * LANE_W + LANE_W * 0.5
		if absf(lane_center - urgent.pos.x) <= reach:
			out.append(i)
	return out


func _move_drops(delta: float) -> void:
	var speed := float(_phase()["speed"])
	var basket := _basket_rect()
	var survivors: Array[Drop] = []

	for d in drops:
		d.phase += delta
		d.pos.y += speed * delta

		# 接到：掉落物中心進入提籃頂面判定框
		if basket.has_point(d.pos):
			_on_caught(d)
			continue
		# 漏接
		if d.pos.y >= KILL_Y:
			_on_missed(d)
			continue
		survivors.append(d)

	drops = survivors


func _on_caught(d: Drop) -> void:
	match d.kind:
		Kind.BOMB:
			if shield_left > 0.0:
				shield_left = 0.0          # 護盾擋掉一顆炸彈後消失
				_juice.kick(0.50)
				_juice.freeze(0.10)
				_pop("BLOCKED", Palette.MOON, d.pos)
			else:
				lives -= 1
				combo = 0
				multiplier = 1
				_flash = 0.28
				_juice.kick(0.95)
				_juice.freeze(0.14)
				_pop("-1 LIFE", Palette.WARN, d.pos)
				if lives <= 0:
					state = State.RESULT
		Kind.MOON:
			shield_left = SHIELD_TIME
			_juice.kick(0.30)
			_juice.freeze(0.05)
			_pop("SHIELD 8s", Palette.MOON, d.pos)
		_:
			var base := _base_score(d.kind)
			var was_mult := multiplier
			combo += 1
			multiplier = clampi(1 + combo / COMBO_STEP, 1, COMBO_MAX)
			var gained := base * multiplier
			score += gained
			# 珠寶約 1.5 秒掉一顆，力道必須極小，不然會變成整局的背景震動
			match d.kind:
				Kind.CHARM:
					_juice.kick(0.45)
					_juice.freeze(0.09)
				Kind.STARDUST:
					_juice.kick(0.12)
				_:
					_juice.kick(0.06)
			if multiplier > was_mult:
				_juice.kick(0.25 + 0.08 * (multiplier - 1))
				_juice.freeze(0.03 * (multiplier - 1))
			var col: Color = Palette.GOLD if d.kind == Kind.CHARM else Palette.TEXT
			_pop("+%d" % gained, col, d.pos)


func _on_missed(d: Drop) -> void:
	# 漏接有價物才斷 Combo；炸彈與月光能量漏掉沒有懲罰
	if d.kind == Kind.BOMB or d.kind == Kind.MOON:
		return
	if combo > 0:
		_juice.kick(0.32, Vector2.DOWN)
		_pop("COMBO LOST", Palette.TEXT_DIM, Vector2(d.pos.x, KILL_Y - 12))
	combo = 0
	multiplier = 1


func _base_score(kind: int) -> int:
	match kind:
		Kind.JEWEL:
			return 50
		Kind.STARDUST:
			return 100
		Kind.CHARM:
			return 300
	return 0


func _pop(text: String, col: Color, at: Vector2) -> void:
	_pop_text = text
	_pop_col = col
	_pop_at = at
	_pop_timer = 0.7


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
	_draw_bg_far()                     # 星星與屋頂剪影：視差層
	draw_set_transform(_juice.world_offset())
	_draw_ground()                     # 地面線跟世界同步，露娜才不會在地上滑動
	for d in drops:
		_draw_drop(d)
	_draw_luna()
	_draw_pop()                        # _pop_at 是世界座標，必須畫在這一層
	draw_set_transform(Vector2.ZERO)
	_draw_hud()

	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(Palette.WARN, _flash * 0.5))
	if state == State.READY:
		_center("READY!", 140, 24, Palette.GOLD)
	elif state == State.RESULT:
		_draw_result()


## 視差層：只有遠到不會跟任何東西接觸的元素。往外多畫 OVERDRAW 避免露出缺口。
func _draw_bg_far() -> void:
	var m := Juice.OVERDRAW
	draw_rect(Rect2(-m, -m, SCREEN.x + m * 2.0, SCREEN.y + m * 2.0), Palette.BG)
	# 星點
	for i in 34:
		var x := fmod(float(i) * 71.0, 474.0) + 3.0
		var y := fmod(float(i) * 43.0, 190.0) + 6.0
		draw_rect(Rect2(x, y, 1, 1), Palette.PEARL)
	# 屋頂與樹林剪影：多跑一輪並往左移，補上多畫出來的那一圈
	for i in 10:
		var bx := float(i) * 56.0 - 8.0 - m
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx, 214), Vector2(bx + 28, 186), Vector2(bx + 56, 214)]), Palette.FAR)


## 地面屬於 WORLD 而不是背景 —— 露娜站在這條線上，兩者必須共用同一個位移。
func _draw_ground() -> void:
	var m := Juice.OVERDRAW
	draw_rect(Rect2(-m, 214, SCREEN.x + m * 2.0, SCREEN.y - 214 + m), Palette.NEAR)
	draw_line(Vector2(-m, 214), Vector2(SCREEN.x + m, 214), Palette.WALL_DARK, 1.0)


func _draw_drop(d: Drop) -> void:
	match d.kind:
		Kind.JEWEL:
			draw_rect(Rect2(d.pos - Vector2(4, 4), Vector2(8, 8)), Palette.LUNA)
			draw_rect(Rect2(d.pos - Vector2(2, 2), Vector2(3, 3)), Palette.LUNA_LIGHT)
		Kind.STARDUST:
			draw_circle(d.pos, 4.5, Palette.PEARL)
			draw_circle(d.pos + Vector2(-1.5, -1.5), 1.5, Palette.TEXT)
		Kind.CHARM:
			# 金色光暈與拖尾，遠遠就能判讀
			draw_line(d.pos, d.pos - Vector2(0, 14), Color(Palette.GOLD, 0.35), 3.0)
			var halo := 7.0 + sin(d.phase * 3.0) * 1.5
			draw_circle(d.pos, halo, Color(Palette.GOLD, 0.3))
			draw_circle(d.pos, 4.5, Palette.GOLD)
		Kind.BOMB:
			draw_circle(d.pos, 6.5, Palette.CAT_DARK)
			draw_circle(d.pos, 6.5, Palette.CAT, false, 1.0)
			# 暗影猫的黃眼睛
			draw_circle(d.pos + Vector2(-2.5, -1.0), 1.5, Palette.CAT_EYE)
			draw_circle(d.pos + Vector2(2.5, -1.0), 1.5, Palette.CAT_EYE)
			# 引信火花：畫面唯一的暖橘色，120px/s 落速下也要能瞬間辨識
			var spark := 1.5 + sin(d.phase * 14.0) * 0.8
			draw_circle(d.pos + Vector2(0, -8.0), spark, Palette.WARN)
		Kind.MOON:
			draw_circle(d.pos, 6.0, Palette.MOON)
			draw_circle(d.pos + Vector2(-2, -1), 5.0, Palette.BG)


func _draw_luna() -> void:
	var cx := luna_x
	# 身體（16×32 placeholder）＋帽子＋心形徽章
	draw_rect(Rect2(cx - 6, LUNA_Y - 22, 12, 22), Palette.LUNA, false, 1.0)
	draw_rect(Rect2(cx - 9, LUNA_Y - 30, 18, 6), Palette.LUNA)
	draw_rect(Rect2(cx - 1, LUNA_Y - 29, 2, 2), Palette.LUNA_LIGHT)
	# 星光提籃：判定框就是頂面那條
	var b := _basket_rect()
	draw_rect(b, Palette.GOLD)
	draw_rect(Rect2(b.position.x, b.position.y, b.size.x, 10), Palette.GOLD, false, 1.0)
	# 護盾光圈，剩 2 秒開始閃爍
	if shield_left > 0.0:
		var show := shield_left > SHIELD_WARN or fmod(shield_left, 0.24) < 0.12
		if show:
			draw_arc(Vector2(cx, LUNA_Y - 12), 20.0, 0.0, TAU, 24, Palette.MOON, 1.0)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var secs := int(ceil(time_left))
	var time_col: Color = Palette.WARN if secs <= 10 else Palette.TEXT
	draw_string(font, Vector2(12, 18), "TIME %d:%02d" % [secs / 60, secs % 60],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, time_col)
	draw_string(font, Vector2(0, 18), "SCORE %06d" % score,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, 12, Palette.TEXT)

	# 生命愛心
	for i in START_LIVES:
		var c := Vector2(404 + i * 14, 14)
		if i < lives:
			draw_circle(c, 4.0, Palette.LUNA)
		else:
			draw_circle(c, 4.0, Palette.FAR)

	# Combo 倍率：提升時放大跳動一次
	if multiplier > 1:
		var grow := 1.0 + maxf(0.0, _pop_timer - 0.5) * 1.4
		draw_string(font, Vector2(12, 34), "COMBO x%d" % multiplier,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * grow), Palette.GOLD)
	elif combo > 0:
		draw_string(font, Vector2(12, 34), "COMBO %d/%d" % [combo, COMBO_STEP],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.TEXT_DIM)



## 分數飄字用的是世界座標，所以畫在 world pass，不能留在 HUD
func _draw_pop() -> void:
	if _pop_timer <= 0.0:
		return
	var rise := (0.7 - _pop_timer) * 16.0
	draw_string(ThemeDB.fallback_font, Vector2(_pop_at.x - 40, _pop_at.y - rise),
		_pop_text, HORIZONTAL_ALIGNMENT_CENTER, 80, 12, _pop_col)


func _draw_result() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(Palette.NIGHT, 0.82))
	var over := lives <= 0
	_center("GAME OVER" if over else "TIME UP", 96, 22,
		Palette.WARN if over else Palette.GOLD)
	_center("SCORE  %06d" % score, 134, 18, Palette.TEXT)
	_center(chest_tier(), 162, 14, Palette.MOON)
	_center("PRESS ENTER TO PLAY AGAIN", 200, 10, Palette.TEXT_DIM)
	_center("ESC FOR MENU", 216, 10, Palette.TEXT_DIM)


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, col)
