extends Node2D

# ─────────────────────────────────────────────────────────
# CharmsCatch —— 接珠寶躲炸彈（依 Guides/CharmsCatch.docx 實作）
#
# 三款中最直覺的一款：只有左右兩個方向。張力全靠 Combo 倍率與
# 每 15 秒一跳的落速撐出來。
#
# 數值以 GDD 為準，只有移動速度是企劃試玩後刻意調快的（見下方常數註解）。
# 長按同方向 1 秒線性加速到 ×2.5（原 A/Shift 衝刺已移除），6 條軌道每軌 80px，
# 同軌連續生成間隔不得低於 0.6 秒。
#
# 座標一律用 Vector2（像素）。
# ─────────────────────────────────────────────────────────

signal round_finished(score: int, duration: float, game_over: bool)

enum State { READY, PLAYING, RESULT }
enum Kind { JEWEL, STARDUST, CHARM, BOMB, MOON }

const ROUND_TIME := 60.0
# 開場停頓：ReadyGo 淡入 0.25s＋動畫 24幀@14fps≈1.71s＋0.05s 緩衝（播完才開場）
const READY_TIME := ReadyGo.FADE_SECONDS + ReadyGo.ANIM_SECONDS + 0.05
const SCREEN := Vector2(480, 270)

# ── 露娜 ────────────────────────────────────────────────
# GDD 寫 60 px/s，但實際玩起來太鈍 —— 一趟落下的時間只夠橫move 1.4~2.9 軌，
# 玩家常常眼睜睜看著珠寶掉在搆不到的地方。企劃試玩後決定調快並加上慣性。
# 這是**刻意偏離 GDD** 的手感調整，不是筆誤。
# GDD 的 A 鍵衝刺 ×1.8 已於 2026-08 拍板移除（實機幾乎沒人用），
# 改成長按同一方向 HOLD_TIME 秒，速度線性升到 HOLD_MULT 倍。
const MOVE_SPEED := 95.0            # 基礎速度（GDD 原值 60）
const HOLD_MULT := 2.5              # 長按同一方向到頂的速度倍率
const HOLD_TIME := 1.0              # 從基礎速度線性升到頂的秒數
# 慣性：加速比煞車快，所以起步跟手、放開會滑一小段（約 0.14 秒、7px）。
# 不用物理節點，純數學 move_toward —— 跟專案其他地方的做法一致。
const ACCEL := 900.0                # px/s²，按住方向鍵時逼近目標速度
const FRICTION := 700.0             # px/s²，放開後減速
const LUNA_Y := 270.0               # 腳踩螢幕最底（貼底）
# 人物與提籃融合成單一物件：只畫 cc_person1 一張貼圖，接取判定框就是貼圖大小
# （腳踩 LUNA_Y、水平置中），見 _catch_rect()。

# ── 掉落區 ──────────────────────────────────────────────
const LANES := 6
const LANE_W := 80.0                # 6 × 80 = 480
const LANE_MIN_GAP := 0.6           # 同一軌道連續生成的最小間隔
const SPAWN_Y := -10.0
const KILL_Y := 270.0               # 掉到這條線以下就算漏接（= 判定框底邊＝螢幕最底）

# ── 生命與護盾 ──────────────────────────────────────────
const START_LIVES := 3
const SHIELD_TIME := 8.0
const SHIELD_WARN := 2.0            # 剩 2 秒開始閃爍
const MOON_MAX_PER_ROUND := 3       # 每局最多出現 3 個月光能量

# ── Combo ───────────────────────────────────────────────
const COMBO_STEP := 5               # 每 5 連 +1 倍率
const COMBO_MAX := 5                # 上限 ×5

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
var _round_sent := false            # 局終信號只發一次（同幀連中兩顆炸彈的保險）

var luna_x := 240.0
var luna_vx := 0.0                  # 目前的水平速度，慣性用
var _hold_t := 0.0                  # 長按同一方向幾秒了（加速用）
var _hold_dir := 0.0                # 目前按住的方向；放開或換向就把 _hold_t 歸零

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
var _fx := Fx.new()                 # 粒子（見 shared/fx.gd）
var _at_wall := false               # 去抖：貼著邊界時只在「剛撞上」那一幀 kick
var _last_phase := 0
var _score_shown := 0.0             # HUD 上滾動中的分數
# 擠壓變形（見 shared/fx.gd）：撞邊界壓扁、接到東西彈跳 —— 提籃融合進人物後，
# 兩種變形都作用在同一張貼圖上，繪製時以腳底為支點相乘疊加（見 _draw_luna）。
const SQUASH_TIME := 0.20
var _luna_squash := 0.0
var _luna_axis := Vector2.ZERO
var _catch_squash := 0.0

var bg_texture: Texture2D = preload("res://assets/catch/CC_Bg.png")
var cc_01: Texture2D = preload("res://assets/catch/CC_01.png")
var cc_02: Texture2D = preload("res://assets/catch/CC_02.png")
var cc_03: Texture2D = preload("res://assets/catch/CC_03.png")
var cc_04: Texture2D = preload("res://assets/catch/CC_04.png")
var cc_05: Texture2D = preload("res://assets/catch/CC_05.png")
var cc_person1: Texture2D = preload("res://assets/catch/CC_Person1.png")
var s_ui_kuang: Texture2D = preload("res://assets/UI/UI_KUANG.png")

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
	luna_vx = 0.0
	_hold_t = 0.0
	_hold_dir = 0.0
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
	_fx.clear()
	_at_wall = false
	_last_phase = 0
	_score_shown = 0.0
	_luna_squash = 0.0
	_catch_squash = 0.0
	state = State.READY
	state_timer = READY_TIME
	_round_sent = false
	ReadyGo.create(self)          # 開場 READY 動畫：淡入→播完→淡出→自行釋放


## 本局結束：把成績交給 launcher，由它提交排行榜並打開面板。
## 發完之後 launcher 會在下一幀釋放本節點，遊戲自己不需要清場。
## duration = 純遊玩秒數（READY 停頓不算），三款一致。
func _finish_round() -> void:
	if _round_sent:
		return
	_round_sent = true
	round_finished.emit(score, ROUND_TIME - time_left, lives <= 0)


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
		_fx.update(delta)
		if _luna_squash > 0.0:
			_luna_squash = maxf(0.0, _luna_squash - delta / SQUASH_TIME)
		if _catch_squash > 0.0:
			_catch_squash = maxf(0.0, _catch_squash - delta / SQUASH_TIME)

	# 分數滾動：珠寶（+50）幾乎瞬間，Charm ×5（+1500）會滾個 0.3 秒
	_score_shown = move_toward(_score_shown, float(score),
		maxf(150.0, absf(float(score) - _score_shown) * 3.0) * delta)

	if _pop_timer > 0.0:
		_pop_timer -= delta
	if _flash > 0.0:
		_flash -= delta
	queue_redraw()


func _run_state(delta: float) -> void:
	# **Catch 不做自動鏡頭跟隨。** 實機試玩的結論：玩家要盯著掉落物的軌跡，
	# 畫面跟著露娜滑會讓人暈。撞擊震動保留。理由詳見 seeker.gd 同一段註解。
	_juice.look(Vector2.ZERO)
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

	# 長按加速（取代已移除的 A/Shift 衝刺）：持續按住同一個方向 HOLD_TIME 秒，
	# 目標速度從基礎值線性升到 HOLD_MULT 倍；放開或換方向就從頭計。
	if dir == 0.0 or dir != _hold_dir:
		_hold_t = 0.0
	else:
		_hold_t = minf(_hold_t + delta, HOLD_TIME)
	_hold_dir = dir

	# 慣性：往目標速度加速，放開就用摩擦力減速
	var top := MOVE_SPEED * lerpf(1.0, HOLD_MULT, _hold_t / HOLD_TIME)
	if dir != 0.0:
		luna_vx = move_toward(luna_vx, dir * top, ACCEL * delta)
	else:
		luna_vx = move_toward(luna_vx, 0.0, FRICTION * delta)

	# 走到畫面邊界：撞上去的那一幀給一記水平震動，貼著不放不會重複觸發。
	# 力道跟著撞擊速度走 —— 用衝的撞上去比慢慢靠過去晃得兇，
	# 這樣「撞得多用力」在畫面上是看得出來的。
	var want_x := luna_x + luna_vx * delta
	# 邊界以貼圖半寬內縮 —— 融合後判定與外觀同一張圖，貼圖半張掛在畫面外
	# 等於判定框也掛出去，看起來像壞掉。
	var half_w := _body_size().x * 0.5
	var clamped := clampf(want_x, half_w, SCREEN.x - half_w)
	if not is_equal_approx(want_x, clamped) and absf(luna_vx) > 1.0:
		if not _at_wall:
			var impact := clampf(absf(luna_vx) / (MOVE_SPEED * HOLD_MULT), 0.0, 1.0)
			_juice.kick(lerpf(0.28, 0.60, impact), Vector2.RIGHT)
			_juice.freeze(0.03 + impact * 0.03)
			# 露娜貼著邊界壓扁 —— 這比震動更看得出「我撞到左邊還右邊」
			_luna_squash = 1.0
			_luna_axis = Vector2(signf(luna_vx), 0.0)
			_fx.burst(Vector2(luna_x + signf(luna_vx) * 8.0, LUNA_Y - 12.0),
				int(3 + impact * 5), Palette.WALL_LIGHT, 45.0, 0.3, 2.0, 0.8)
		_at_wall = true
		luna_vx = 0.0            # 撞牆就停住，不要沿著牆繼續累積速度
	else:
		_at_wall = false
	luna_x = clamped

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
		_fx.burst(Vector2(luna_x, LUNA_Y - 12.0), 24, Palette.MOON, 140.0, 0.7, 3.0, 0.35)
		_pop("BURST! x%d" % cleared, Palette.MOON, Vector2(240, 150))


func _tick_shield(delta: float) -> void:
	if shield_left > 0.0:
		shield_left = maxf(0.0, shield_left - delta)


## 融合物件的貼圖尺寸。判定框、邊界內縮、生成可及性計算都從這裡出，
## 美術換圖（尺寸改變）時不必改任何常數。
func _body_size() -> Vector2:
	if cc_person1 == null:
		return Vector2(36.0, 8.0)   # 貼圖載入失敗的兜底，維持可玩
	return cc_person1.get_size()


## 接取判定框＝貼圖大小：腳踩 LUNA_Y、水平置中。
# 舊版只看提籃頂面 36×8 那一條（側邊擦過不算）；融合後掉落物中心
# 碰到人物任何高度都算接到。
func _catch_rect() -> Rect2:
	var size := _body_size()
	return Rect2(luna_x - size.x * 0.5, LUNA_Y - size.y, size.x, size.y)


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
## 逼你繞路的是炸彈與加速暖機，不是骰子。
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
## 時間差 × 最高速度（長按 1 秒的 ×2.5）就是這段空檔能移動的距離。
## 留 0.85 的安全係數，因為玩家不會每次都走最佳路線，加速還需要 1 秒暖機。
func _chain_filter(candidates: Array[int]) -> Array[int]:
	var urgent := _most_urgent_valuable()
	if urgent == null:
		return []

	var speed := float(_phase()["speed"])
	var catch_y := LUNA_Y - _body_size().y   # 判定框上緣：掉落物從上方進框，等效接取面
	var t_urgent := (catch_y - urgent.pos.y) / speed
	var t_new := (catch_y - SPAWN_Y) / speed
	var window := t_new - t_urgent
	if window <= 0.0:
		return []

	var reach := MOVE_SPEED * HOLD_MULT * window * 0.85
	var out: Array[int] = []
	for i in candidates:
		var lane_center := i * LANE_W + LANE_W * 0.5
		if absf(lane_center - urgent.pos.x) <= reach:
			out.append(i)
	return out


func _move_drops(delta: float) -> void:
	var speed := float(_phase()["speed"])
	var catch_box := _catch_rect()
	var survivors: Array[Drop] = []

	for d in drops:
		d.phase += delta
		d.pos.y += speed * delta

		# 接到：掉落物中心進入融合物件的判定框（貼圖大小）
		if catch_box.has_point(d.pos):
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
				_fx.burst(d.pos, 18, Palette.MOON, 105.0, 0.55, 3.0, 0.5)
				_pop("BLOCKED", Palette.MOON, d.pos)
			else:
				lives -= 1
				combo = 0
				multiplier = 1
				_flash = 0.28
				_juice.kick(0.95)
				_juice.freeze(0.14)
				# 炸開：暖橘的火花 ＋ 暗紫的碎片
				_fx.burst(d.pos, 20, Palette.WARN, 135.0, 0.55, 3.0, 0.8)
				_fx.burst(d.pos, 12, Palette.CAT_GLOW, 90.0, 0.7, 2.0, 0.9)
				_pop("-1 LIFE", Palette.WARN, d.pos)
				if lives <= 0:
					state = State.RESULT
					_score_shown = 0.0
					_finish_round()
		Kind.MOON:
			shield_left = SHIELD_TIME
			_juice.kick(0.30)
			_juice.freeze(0.05)
			_catch_squash = 1.0
			_fx.burst(d.pos, 14, Palette.MOON, 80.0, 0.6, 3.0, 0.3)
			_pop("SHIELD 8s", Palette.MOON, d.pos)
		_:
			var base := _base_score(d.kind)
			var was_mult := multiplier
			combo += 1
			multiplier = clampi(1 + combo / COMBO_STEP, 1, COMBO_MAX)
			var gained := base * multiplier
			score += gained
			# 珠寶約 1.5 秒掉一顆，力道必須極小，不然會變成整局的背景震動
			_catch_squash = 1.0         # 接取彈跳（GDD 的「接取彈跳 2 幀」），壓整個人物
			match d.kind:
				Kind.CHARM:
					_juice.kick(0.45)
					_juice.freeze(0.09)
					_fx.burst(d.pos, 20, Palette.GOLD, 110.0, 0.7, 3.0, 0.6)
				Kind.STARDUST:
					_juice.kick(0.12)
					_fx.burst(d.pos, 8, Palette.PEARL, 70.0, 0.45, 2.0, 0.7)
				_:
					_juice.kick(0.06)
					_fx.burst(d.pos, 5, Palette.LUNA_LIGHT, 55.0, 0.35, 2.0, 0.8)
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
		# 落地的塵土，提醒玩家「這顆掉了」
		_fx.burst(Vector2(d.pos.x, KILL_Y - 4.0), 6, Palette.TEXT_DIM,
			50.0, 0.35, 2.0, 0.5, -PI * 0.5, PI * 0.8)
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


# ── 繪製 ────────────────────────────────────────────────

func _draw() -> void:
	# 三層，每層一個位移（見 shared/juice.gd 的分層模型）
	draw_set_transform(_juice.bg_offset())
	_draw_bg_far()                     # 星星與屋頂剪影：視差層
	draw_set_transform(_juice.world_offset())
	for d in drops:
		_draw_drop(d)
	_draw_luna()
	_fx.draw(self)                     # 粒子屬於 WORLD 層
	_draw_pop()                        # _pop_at 是世界座標，必須畫在這一層
	draw_set_transform(Vector2.ZERO)
	_draw_ui_frame()
	_draw_hud()
	_draw_urgency()

	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(Palette.WARN, _flash * 0.5))
	if state == State.RESULT:
		_draw_result()


## 全螢幕邊框圖（美術出圖 1920×1080，拉伸到 480×270）。
## 畫在 HUD 文字之下：邊框上緣的實心條不會蓋掉時間／分數。
func _draw_ui_frame() -> void:
	if s_ui_kuang == null:
		return
	draw_texture_rect(s_ui_kuang, Rect2(0, 0, 480, 270), false)


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
	# 背景圖原始尺寸是螢幕的整數倍（如 1920×1080），拉伸到邏輯螢幕 480×270
	draw_texture_rect(bg_texture, Rect2(0, 0, SCREEN.x, SCREEN.y), false)


func _draw_drop(d: Drop) -> void:
	match d.kind:
		Kind.JEWEL:
			_draw_drop_texture(cc_01, d.pos)
		Kind.STARDUST:
			_draw_drop_texture(cc_02, d.pos)
		Kind.CHARM:
			_draw_drop_texture(cc_04, d.pos)
		Kind.BOMB:
			_draw_drop_texture(cc_03, d.pos)
		Kind.MOON:
			_draw_drop_texture(cc_05, d.pos)


func _draw_drop_texture(texture: Texture2D, center: Vector2) -> void:
	if texture == null:
		return
	var size := texture.get_size()
	draw_texture(texture, center - size * 0.5)


func _draw_luna() -> void:
	var cx := luna_x
	# 人物與提籃融合成單一物件：撞邊界壓扁與接取彈跳（原提籃回饋）都作用在
	# 同一張貼圖上。以腳底為支點縮放，人才不會浮起來；
	# 兩種變形同幀並存時直接相乘疊加。
	var world := _juice.world_offset()
	var sc := Vector2.ONE
	if _luna_squash > 0.0:
		sc = sc * Fx.squash(_luna_squash, _luna_axis)
	if _catch_squash > 0.0:
		sc = sc * Fx.squash(_catch_squash, Vector2.DOWN, 0.38)
	if sc != Vector2.ONE:
		draw_set_transform(world + Vector2(cx, LUNA_Y), 0.0, sc)
		_draw_luna_body(0.0, 0.0)
		draw_set_transform(world)
	else:
		_draw_luna_body(cx, LUNA_Y)

	# Combo 光圈：倍率越高圈越亮越大。原本倍率只是 HUD 上一個數字，
	# 在遊戲區裡完全看不到，玩家不會「感覺」到自己正在連。
	if multiplier > 1:
		var t := float(multiplier - 1) / float(COMBO_MAX - 1)
		var r := 18.0 + t * 8.0 + sin(Time.get_ticks_msec() / 1000.0 * 6.0) * 1.5
		draw_arc(Vector2(cx, LUNA_Y - 12), r, 0.0, TAU, 28,
			Color(Palette.GOLD, 0.25 + t * 0.45), 1.0)

	# 護盾光圈，剩 2 秒開始閃爍
	if shield_left > 0.0:
		var show := shield_left > SHIELD_WARN or fmod(shield_left, 0.24) < 0.12
		if show:
			draw_arc(Vector2(cx, LUNA_Y - 12), 20.0, 0.0, TAU, 24, Palette.MOON, 1.0)


func _draw_luna_body(cx: float, cy: float) -> void:
	if cc_person1 == null:
		return
	var size := cc_person1.get_size()
	draw_texture(cc_person1, Vector2(cx - size.x * 0.5, cy - size.y))


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var secs := int(ceil(time_left))
	var time_col: Color = Palette.WARN if secs <= 10 else Palette.TEXT
	var tsize := 12
	if secs <= 10 and state == State.PLAYING:
		tsize = int(12.0 + (1.0 - fmod(time_left, 1.0)) * 4.0)   # 每秒脈動一次
	draw_string(font, Vector2(12, 18), "TIME %d:%02d" % [secs / 60, secs % 60],
		HORIZONTAL_ALIGNMENT_LEFT, -1, tsize, time_col)
	draw_string(font, Vector2(0, 18), "SCORE %06d" % int(round(_score_shown)),
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
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(Palette.NIGHT, 0.82))
	var over := lives <= 0
	_center("GAME OVER" if over else "TIME UP", 96, 22,
		Palette.WARN if over else Palette.GOLD)
	_center("SCORE  %06d" % int(round(_score_shown)), 134, 18, Palette.TEXT)
	# 提示等分數滾完才出現，跟分數揭曉同一個瞬間
	if int(round(_score_shown)) >= score:
		_center("PRESS ENTER TO PLAY AGAIN", 200, 10, Palette.TEXT_DIM)
		_center("ESC FOR MENU", 216, 10, Palette.TEXT_DIM)


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, col)
