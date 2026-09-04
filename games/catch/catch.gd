extends Node2D

# ─────────────────────────────────────────────────────────
# CharmsCatch —— 接珠寶躲炸彈（依 Guides/CharmsCatch.docx 實作）
#
# 三款中最直覺的一款：只有左右兩個方向。張力全靠 Combo 倍率與
# 每 15 秒一跳的落速撐出來。
#
# 數值以 GDD 為準，只有移動速度是企劃試玩後刻意調快的（見下方常數註解）。
# 長按同方向 1 秒線性加速到 ×2.5（原 A/Shift 衝刺已移除），6 條軌道每軌 80px，
# 同軌連續生成間隔不得低於 0.6 秒。像
#
# 座標一律用 Vector2（素）。
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

# ── 生命與月光能量 ──────────────────────────────────────
const START_LIVES := 3
# 月光能量（2026-09）：護盾功能取消，純加分道具 —— 接到 +150（吃 Combo 倍率），
# 漏接跟其他有價物一樣斷 Combo；仍是每局最多出現 MOON_MAX_PER_ROUND 個的稀有物。
const MOON_SCORE := 150
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
#
# 掉落物數量翻倍（2026-09 企劃）：gap 全部減半、max_on 翻倍。炸彈比例
# 設為原值的 0.65 倍（0.10→0.065 等）＝ 炸彈密度比原版多 30%、不到翻倍 ——
# 原因見模擬第 6 節：連炸彈一起翻倍時 AI 存活率 68%→19%、平均局長
# 56s→45s，局提前結束，「翻倍」反而讓總掉落數與分數都縮水。
# 0.65 倍時炸彈 2.1→2.6 顆/局、死亡 1.7→2.1 次、存活率 67%→50%、
# 有價物仍有約 56 顆/局（1.95 倍）。
#
# 末段加壓（2026-09 企劃追加）：第 4 段（45-60s）gap 再 ÷1.3、炸彈比例
# 不動 —— 有價物與炸彈共用同一條生成計時器，兩者剛好都 +30%
# （段內有價物 12.7→16.5 顆、炸彈 3.6→4.7 顆，模擬第 6 節驗證）。
const PHASES := [
	{"speed": 60.0,  "max_on": 4,  "bomb": 0.065,  "charm_mult": 1.0, "gap": Vector2(0.8, 1.1)},
	{"speed": 80.0,  "max_on": 6,  "bomb": 0.13,   "charm_mult": 1.0, "gap": Vector2(0.7, 1.0)},
	{"speed": 100.0, "max_on": 8,  "bomb": 0.195,  "charm_mult": 1.0, "gap": Vector2(0.6, 0.9)},
	{"speed": 120.0, "max_on": 10, "bomb": 0.2275, "charm_mult": 2.0, "gap": Vector2(0.385, 0.575)},
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

# Game feel（見 shared/juice.gd）。位移只作用在繪製，不碰任何遊戲數值。
var _juice := Juice.new(Juice.ARCADE)
var _fx := Fx.new()                 # 粒子（見 shared/fx.gd）
var _at_wall := false               # 去抖：貼著邊界時只在「剛撞上」那一幀 kick
var _last_phase := 0
var _score_shown := 0.0             # HUD 上滾動中的分數
var _heart_fade := 0.0              # 剛失去的愛心淡出動畫剩餘秒數（0 = 沒在播）
var _heart_fade_slot := -1          # 正在播動畫的愛心格位
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
var s_score_frame: Texture2D = preload("res://assets/UI/SCORE_FRAME.png")
var s_heart_ui: Texture2D = preload("res://assets/UI/HEART.png")

# ── 露娜視覺：C_Player.tscn（畫師交付的動畫場景，AnimatedSprite2D 兩段動畫）
#   Idle  待機循環（8 幀 @9fps）
#   Hurt  接到炸彈扣命時播一次（3 幀 @6fps），播完回 Idle
# 動畫不自己播 —— pause 後由 _process 用場景定義的 fps 手動推幀，
# launcher 停掉遊戲節點（process_mode = DISABLED）時畫面才跟著凍。
# luna_view 是純視覺子節點（z=-1），position 只當繪製錨點、不參與任何玩法判定，
# 所以把鏡頭位移寫進它的 position 是安全的（跟 player/cat 那套不同）；
# 背景因此搬到 _bg_view（z=-2）—— 子節點一律畫在父節點 _draw() 之後，
# 背景留在父節點會蓋住玩家（fishing 同款結構）。
const C_PLAYER_SCENE := preload("res://assets/AnimationScene/C_Player.tscn")
## 顯示縮放：幀畫布 450×284、內容約 308×240，0.29 倍後約 89×70，
## 與接取判定框 90×71（_body_size()，仍以 cc_person1 尺寸為準）視覺一致。
const PLAYER_SCALE := 0.29
## 每段動畫的錨點參考框（取第 0 幀，alpha>32 的內容包圍盒；畫師改圖要重測）。
## 整段動畫共用這個框算 offset —— 所有幀同一畫布、內容位置一致，
## 不做逐幀歸一化（同 fishing 的 P_REFS，逐幀錨定會跟著肢體擺動滑動）。
const P_REFS := {
	&"Idle": Rect2(57, 22, 308, 240),
	&"Hurt": Rect2(58, 22, 308, 240),
}
enum PAnim { IDLE, HURT }
const P_ANIM_NAMES := [&"Idle", &"Hurt"]

var luna_view: Node2D = null
var _bg_view: Node2D = null          # 背景層子節點（z=-2，見 _setup_views）
var _anim: AnimatedSprite2D = null
var _p_anim := PAnim.IDLE            # 目前播的動畫（見 PAnim）
var _p_time := 0.0                   # 目前動畫累計時間（手動推幀用）
var _p_oneshot := false              # Hurt 播放中（播完回 Idle）

func _ready() -> void:
	_rng.randomize()
	_setup_views()
	_start_round()


## 場景接入：背景 BgView（z=-2）→ 玩家 luna_view（z=-1）→ 遊戲本體 _draw（z=0）。
## 動畫場景結構不符（沒有 AnimatedSprite2D）時退回 cc_person1 靜態貼圖
## （_draw_luna 的舊路徑，luna_view 保持 null），判定框不受影響。
func _setup_views() -> void:
	var bg := BgView.new()
	bg.game = self
	bg.name = "BgView"
	bg.z_index = -2
	add_child(bg)
	_bg_view = bg

	luna_view = C_PLAYER_SCENE.instantiate()
	_anim = luna_view.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _anim == null:
		luna_view.queue_free()
		luna_view = null
		return
	_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 縮放必須在這裡就設好：READY 期間 _process 推幀前就會畫出第一幀，
	# 沒設的話開場會以貼圖原尺寸（450×284）畫出一個巨無霸露娜。
	_anim.scale = Vector2(PLAYER_SCALE, PLAYER_SCALE)
	_anim.pause()                 # 幀由 _process 手動推（凍結時畫面才跟著凍）
	luna_view.name = "LunaView"
	luna_view.z_index = -1
	add_child(luna_view)
	_p_anim = PAnim.IDLE
	_p_time = 0.0
	_p_oneshot = false
	_anim.animation = P_ANIM_NAMES[PAnim.IDLE]
	_anim.frame = 0
	_apply_frame_anchor()


## 每幀：錨點對位（內容腳底貼 LUNA_Y、水平置中＋鏡頭位移）、擠壓變形、推幀。
## 擠壓寫在 luna_view.scale（節點原點就是腳底錨點），跟舊 draw_set_transform
## 以腳底為支點的縮放同效果；position 寫進子節點是安全的（純視覺，見上）。
func _update_luna_view(delta: float) -> void:
	if luna_view == null:
		return
	luna_view.position = Vector2(luna_x, LUNA_Y) + _juice.world_offset()
	var sc := Vector2.ONE
	if _luna_squash > 0.0:
		sc = sc * Fx.squash(_luna_squash, _luna_axis)
	if _catch_squash > 0.0:
		sc = sc * Fx.squash(_catch_squash, Vector2.DOWN, 0.38)
	luna_view.scale = sc
	_tick_player_anim(delta)


## 動畫狀態機（手動推幀，見 PAnim）：平時播 Idle 循環；
## 接到炸彈扣命時 _play_oneshot(PAnim.HURT)，Hurt 播完自動回 Idle，
## 期間不被 Idle 打斷。
func _tick_player_anim(delta: float) -> void:
	if _anim == null:
		return
	var anim_name: StringName = P_ANIM_NAMES[_p_anim]
	var frames := _anim.sprite_frames.get_frame_count(anim_name)
	_p_time += delta
	var f := int(_p_time * _anim.sprite_frames.get_animation_speed(anim_name))
	if _p_oneshot and f >= frames:
		# Hurt 播完 → 回 Idle
		_p_oneshot = false
		_p_anim = PAnim.IDLE
		_p_time = 0.0
		anim_name = P_ANIM_NAMES[_p_anim]
		_anim.animation = anim_name
		f = 0
	elif not _p_oneshot:
		f %= frames
	if _anim.frame != f:
		_anim.frame = f
	_apply_frame_anchor()


## 觸發一次性動畫（Hurt）：立即中斷目前動畫，播完回 Idle。
func _play_oneshot(anim: PAnim) -> void:
	if _anim == null:
		return
	_p_anim = anim
	_p_time = 0.0
	_p_oneshot = true
	_anim.animation = P_ANIM_NAMES[anim]
	_anim.frame = 0
	_apply_frame_anchor()


## 動畫錨點：每段動畫共用一個 offset（由 P_REFS 參考框算出）——
## 內容中心對到 x=0、內容底（腳底）對到 y=0，luna_view 的位置就是錨點。
## 不做逐幀歸一化：畫師的幀都在同一畫布、內容位置一致（理由同 fishing）。
## offset 是未縮放座標（scale 乘在整個節點上），錨點正好是 0 所以
## 不需要腳底偏移項。
func _apply_frame_anchor() -> void:
	if _anim == null:
		return
	var anim_name: StringName = P_ANIM_NAMES[_p_anim]
	var b: Rect2 = P_REFS[anim_name]
	var ts: Vector2 = _anim.sprite_frames.get_frame_texture(anim_name, _anim.frame).get_size()
	_anim.offset = Vector2(ts.x * 0.5 - b.get_center().x, ts.y * 0.5 - b.end.y)


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
	_heart_fade = 0.0
	_heart_fade_slot = -1
	_luna_squash = 0.0
	_catch_squash = 0.0
	_p_anim = PAnim.IDLE
	_p_time = 0.0
	_p_oneshot = false
	if _anim != null:
		_anim.animation = P_ANIM_NAMES[PAnim.IDLE]
		_anim.frame = 0
		_apply_frame_anchor()
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

	# 愛心淡出動畫：純表現，命中頓格期間也繼續走
	if _heart_fade > 0.0:
		_heart_fade = maxf(0.0, _heart_fade - delta)

	if _pop_timer > 0.0:
		_pop_timer -= delta
	if _flash > 0.0:
		_flash -= delta
	if _bg_view != null:
		_bg_view.queue_redraw()        # 背景層每幀重繪（視差位移會變）
	_update_luna_view(delta)
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
			AudioManager.play_sfx("catch_hitwall")   # 撞上邊界的那一幀
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
			AudioManager.play_sfx("catch_boom")      # 接到炸彈
			lives -= 1
			_play_oneshot(PAnim.HURT)   # 接到炸彈扣命：受傷動畫播一次再回 Idle
			# 剛失去的那顆愛心播「1 秒放大 1.5 倍＋淡出」（格位 = 少掉後的 lives）
			_heart_fade = 1.0
			_heart_fade_slot = lives
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
		_:
			# 有價物（珠寶／星塵／Charm／月光能量，2026-09 起月亮也是純加分）
			AudioManager.play_sfx("catch_item")      # 接到會加分的掉落物
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
				Kind.MOON:
					_juice.kick(0.30)
					_juice.freeze(0.05)
					_fx.burst(d.pos, 14, Palette.MOON, 80.0, 0.6, 3.0, 0.3)
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
	# 漏接有價物才斷 Combo；炸彈漏掉沒有懲罰（月光能量 2026-09 起也是純加分，
	# 屬於有價物 —— 漏掉照樣斷）
	if d.kind == Kind.BOMB:
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
		Kind.MOON:
			return MOON_SCORE
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
	# 三層（見 shared/juice.gd 的分層模型）：背景由 _bg_view（z=-2）畫、
	# 玩家 luna_view 壓在 z=-1，其餘世界內容與 HUD 都在這層（z=0）——
	# 子節點一律畫在父節點 _draw() 之後，背景留在這裡會被玩家蓋住。
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
	# 人物由 luna_view 子節點（z=-1）負責（見 _update_luna_view）；
	# 動畫場景缺失時退回 cc_person1 貼圖：撞邊界壓扁與接取彈跳都作用在
	# 同一張貼圖上，以腳底為支點縮放，兩種變形同幀並存時相乘疊加。
	if luna_view == null:
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


func _draw_luna_body(cx: float, cy: float) -> void:
	if cc_person1 == null:
		return
	var size := cc_person1.get_size()
	draw_texture(cc_person1, Vector2(cx - size.x * 0.5, cy - size.y))


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var secs := int(ceil(time_left))
	var time_col: Color = Palette.WARN if secs <= 10 else Palette.LUNA
	var tsize := 20
	if secs <= 10 and state == State.PLAYING:
		tsize = int(12.0 + (1.0 - fmod(time_left, 1.0)) * 4.0)   # 每秒脈動一次
	draw_string(font, Vector2(25, 37), "%d:%02d" % [secs / 60, secs % 60],
		HORIZONTAL_ALIGNMENT_LEFT, -1, tsize, time_col)
	# 中：分數（滾動中的值）。背景框在 1920×1080 設計座標 (768,70)、
	# 文字 baseline (990,92)，除以 4 到邏輯畫面（同 launcher 慣例）。
	var fsize := s_score_frame.get_size() / 4.0
	draw_texture_rect(s_score_frame, Rect2(192.0, 17.5, fsize.x, fsize.y), false)
	draw_string(font, Vector2(213.0, 34.0), "%06d" % int(round(_score_shown)),
		HORIZONTAL_ALIGNMENT_CENTER, fsize.x, 12, Palette.LUNA)

	# 生命愛心：HEART.png（80×68 設計稿 ÷4 = 20×17）。剛失去的那顆播
	# 1 秒「放大 1.5 倍＋淡出」，播完後與其他空位一樣畫成暗色愛心。
	var heart_size := s_heart_ui.get_size() / 4.0
	for i in START_LIVES:
		var c := Vector2(404 + i * 24, 37)
		if i < lives:
			_draw_heart(c, heart_size, 1.0)
		elif i == _heart_fade_slot and _heart_fade > 0.0:
			var k := 1.0 - _heart_fade          # 0 → 1
			_draw_heart(c, heart_size * (1.0 + 0.5 * k), 1.0 - k)
		else:
			_draw_heart(c, heart_size, 0.22)

	# Combo 倍率：提升時放大跳動一次
	if multiplier > 1:
		var grow := 1.0 + maxf(0.0, _pop_timer - 0.5) * 1.4
		draw_string(font, Vector2(18, 55), "COMBO x%d" % multiplier,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * grow), Palette.GOLD)
	elif combo > 0:
		draw_string(font, Vector2(18, 55), "COMBO %d/%d" % [combo, COMBO_STEP],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.TEXT_DIM)



## 分數飄字用的是世界座標，所以畫在 world pass，不能留在 HUD
func _draw_heart(center: Vector2, size: Vector2, alpha: float) -> void:
	if s_heart_ui == null:
		return
	draw_texture_rect(s_heart_ui, Rect2(center - size * 0.5, size), false,
		Color(1, 1, 1, alpha))


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
	# 壓暗背景 —— GAME OVER／TIME UP 文字與分數由 launcher 的 Game Over
	# 動畫層畫（ui/game_over.gd），這裡只負責讓遊戲場景沉下去
	# （遊戲節點會保留到動畫播完，見 launcher._open_game_over）。
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(Palette.NIGHT, 0.82))


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, col)


## 背景層（z=-2）：玩家 luna_view 是子節點、畫在父節點 _draw() 之後，
## 背景若留在父節點會蓋住玩家 —— 所以搬到這顆更低的子節點（fishing 同款）。
## 內容與舊 _draw_bg_far 相同：視差層只放遠到不會跟任何東西接觸的元素，
## 往外多畫 OVERDRAW 避免震動露出缺口。
class BgView extends Node2D:
	var game = null   # catch 節點；不型別，執行期取背景狀態
	func _draw() -> void:
		if game == null:
			return
		draw_set_transform(game._juice.bg_offset())
		var m := Juice.OVERDRAW
		draw_rect(Rect2(-m, -m, game.SCREEN.x + m * 2.0, game.SCREEN.y + m * 2.0), Palette.BG)
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
		# 全屏背景圖拉伸到邏輯螢幕（CC_Bg.png 蓋掉程式底色與星點）
		if game.bg_texture != null:
			draw_texture_rect(game.bg_texture, Rect2(0, 0, game.SCREEN.x, game.SCREEN.y), false)
