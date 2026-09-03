extends Node2D

# ─────────────────────────────────────────────────────────
# CharmsFishing —— 黃金礦工式夜釣（依 Guides/CharmsFishing.docx 實作）
#
# 玩家只做一個決定：什麼時候放線。鉤子自己擺，放出去就不能取消，
# 收線速度由勾到的東西決定 —— 所有的取捨都壓在「時間」這一個資源上。
# 沒有生命值，犯錯只會浪費秒數，這是刻意跟 Seeker 的三條命互補。
#
# 畫面分層（GDD）：天空 96px／水下 174px，水面線在 y=96。
# 釣線起點 LINE_ORIGIN 預設在船底 (240, 96)，±75° 擺動，單趟週期 2.4 秒，
# 最後 15 秒擺速 +15% 製造收尾壓力。
#
# 座標一律用 Vector2（像素）—— 這款沒有格子，不會有 Vector2i 混用問題。
# ─────────────────────────────────────────────────────────

signal round_finished(score: int, duration: float, game_over: bool)

enum State { READY, PLAYING, RESULT }
enum Hook { SWING, EXTEND, RETRACT }
enum Kind { DIAMOND, CHARM, CLOUD, IMP }

const ROUND_TIME := 60.0
# 開場停頓：ReadyGo 淡入 0.25s＋動畫 24幀@14fps≈1.71s＋0.05s 緩衝（播完才開場）
const READY_TIME := ReadyGo.FADE_SECONDS + ReadyGo.ANIM_SECONDS + 0.05

# ── 畫面配置 ────────────────────────────────────────────
const SCREEN := Vector2(480, 270)
const SURFACE_Y := 96.0                    # 水面線：天空 96 / 水下 174
const PIVOT := Vector2(240.0, 96.0)        # 船底龍骨錨點（船與露娜的視覺中心）
## 釣線的起點（鉤子擺動中心）。預設跟 PIVOT 同點；想單獨移動線的起點
## （例如改到角色手上的釣竿尖端）只改這裡，船的錨點不動。
const LINE_ORIGIN := Vector2(222.0, 69.0)

# 船＋露娜整張貼圖（F_Luna.png，300×300：露娜頭頂在貼圖 y=30、船底龍骨在 y=269）。
# 顯示大小 60×60：船體寬約 51px（貼近舊版 56px 佔位），露娜頭頂落在 y≈42、
# 不會被 HUD 分數框（底緣 y=40.5）蓋到。換貼圖時只需調 LUNA_KEEL。
const LUNA_SIZE := Vector2(60.0, 60.0)
const LUNA_KEEL := 269.0                   # 船底龍骨在貼圖座標的 y（對齊水面線）
const WATER_L := 6.0
const WATER_R := 474.0
const WATER_B := 266.0

# ── 鉤子 ────────────────────────────────────────────────
const MAX_ANGLE_DEG := 75.0
const SWING_PERIOD := 2.4                  # 一趟來回的秒數
const RUSH_TIME := 15.0                    # 剩幾秒開始加速
const RUSH_SWING := 1.15                   # 擺速 ×1.15
const LINE_MIN := 40.0                     # 待機時的線長
const LINE_MAX := 205.0
const EXTEND_SPEED := 150.0
const RETRACT_EMPTY := 210.0               # 空鉤回收速度

# ── 月光能量 ────────────────────────────────────────────
const MOON_USES := 3
const MOON_BOOST := 3.0                    # 勾到寶物時收線 ×3

# ── 水層（y 範圍）───────────────────────────────────────
# 淺/中/深 = (112,168)/(162,208)/(212,256)，全區 (112,256)。
# 注意水層不是等面積的：鉤子從 (240,96) 以 ±75° 掃，可及範圍是一個倒三角形，
# 越淺越窄（y=112 附近全寬只有約 90px）。物件數要照這個來配，
# 不然會有一堆生不出來 —— 翻倍數量＋32px 大物件是模擬試出來的上限。
const SHALLOW := Vector2(112, 168)
const MID := Vector2(162, 208)
const DEEP := Vector2(212, 256)
const ANY := Vector2(112, 256)

# ── 族群補充 ────────────────────────────────────────────
# 四種物件撈走後都會回補（同一種類、同一層位），重生延遲 5~15 秒、
# 隨剩餘時間由慢到快：開局撈走的等最久（15 秒），局末很快就補回來（5 秒）。
#
# 為什麼要有這個：盤面總值上限只有 1680 分（6×200+4×100+8×10），
# 不補充的話，撈得再快也會撞到天花板（模擬過：照單全收的機器人
# 清完盤面也只有 1680）。
const RESPAWN_MIN := 5.0
const RESPAWN_MAX := 15.0
const RESPAWN_KINDS := {
	Kind.DIAMOND: Vector2(MID.x, DEEP.y),
	Kind.CHARM: MID,
	Kind.CLOUD: ANY,
	Kind.IMP: ANY,
}


## 水下的一個物件。小惡魔會橫向游動、放線時主動靠近鉤子，其餘固定不動。
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

# ─────────────────────────────────────────────────────────
# 露娜視覺：F_Player.tscn（畫師交付的動畫場景，AnimatedSprite2D 四段動畫）：
#   Idle      待機：鉤子擺動、玩家沒有操作時 —— 循環
#   Hook      放線：A 按下、線伸出／收回途中 —— 循環
#   GetPoint  寶物上船加分的慶祝 —— 播一次
#   Hurt      小惡魔上船扣時間的受傷 —— 播一次
# 一次性動畫播完自動回到基礎動畫（放線中＝Hook，否則 Idle）。
# 動畫不自己播 —— pause 後由 _process 用場景定義的 fps 手動推幀，
# launcher 停掉遊戲節點（process_mode = DISABLED）時畫面才跟著凍。
# luna_view 是純視覺節點，position 只當繪製錨點、不參與任何玩法判定，
# 所以把畫面位移寫進它的 position 是安全的（跟 player/cat 那套不同）；
# _draw_boat() 偵測到 luna_view 非 null 就跳過舊貼圖（場景結構不符時退回）。
# ─────────────────────────────────────────────────────────
const F_PLAYER_SCENE := preload("res://assets/AnimationScene/F_Player.tscn")
## 顯示縮放：與舊 F_Luna.png（300×300 畫到 60×60）同尺寸 —— 畫師照舊比例
## 重畫的新幀（內容約 256×240px）在 0.2 倍下視覺大小跟舊貼圖一致。
const PLAYER_SCALE := 0.2
## 每段動畫的錨點參考框（取第 0 幀，alpha>32 的內容包圍盒；畫師改圖要重測）。
## 整段動畫共用這個框算 offset —— 所有幀都是同一畫布尺寸、內容位置一致，
## 不需要逐幀歸一化（逐幀錨定反而會讓船跟著角色肢體擺動而左右滑，見
## _apply_frame_anchor 的註解）。
const P_REFS := {
	&"Idle": Rect2(34, 32, 257, 237),
	&"Hook": Rect2(34, 33, 257, 237),
	&"GetPoint": Rect2(34, 32, 257, 237),
	&"Hurt": Rect2(37, 42, 257, 237),
}

enum PAnim { IDLE, HOOK, GETPOINT, HURT }
const P_ANIM_NAMES := [&"Idle", &"Hook", &"GetPoint", &"Hurt"]

var luna_view: Node2D = null
var _bg_view: Node2D = null           # 背景層子節點（z=-2，見 _setup_bg_view）
var _bg_video: VideoStreamPlayer = null   # 背景影片（隱藏節點，只負責解碼）
var _anim: AnimatedSprite2D = null
var _p_anim := PAnim.IDLE         # 目前播的動畫（見 PAnim）
var _p_time := 0.0                # 目前動畫累計時間（手動推幀用）
var _p_oneshot := false           # 一次性動畫播放中（播完回基礎動畫）

var bg_texture : Texture2D = preload("res://assets/fishing/F_BG.jpg");
var s_ui_kuang: Texture2D = preload("res://assets/UI/UI_KUANG.png")
var s_score_frame: Texture2D = preload("res://assets/UI/SCORE_FRAME.png")
var s_luna: Texture2D = preload("res://assets/fishing/F_Luna.png")
var _textures := {
	Kind.DIAMOND: preload("res://assets/fishing/F_Diamond_s.png"),
	Kind.CHARM: preload("res://assets/fishing/F_Charm_s.png"),
	Kind.CLOUD: preload("res://assets/fishing/F_Cloud_s.png"),
	Kind.IMP: preload("res://assets/fishing/F_Imp.png"),
}

## 小惡魔的游泳動畫：7 幀循環（ImpAnim/F_Imp_0~6.png，200×200）。
## 顯示尺寸沿用 _item_sizes 的 16×16（新幀內容占比與舊 220×220 貼圖一致）。
const IMP_ANIM_FPS := 8.0
## 小惡魔之間的最小間距（px）：靠得更近就沿兩心連線互相推開，
## 聚在鉤頭後也能重新散開，不會疊成一片。
const IMP_MIN_SEP := 16.0
var _imp_frames: Array[Texture2D] = [
	preload("res://assets/fishing/ImpAnim/F_Imp_0.png"),
	preload("res://assets/fishing/ImpAnim/F_Imp_1.png"),
	preload("res://assets/fishing/ImpAnim/F_Imp_2.png"),
	preload("res://assets/fishing/ImpAnim/F_Imp_3.png"),
	preload("res://assets/fishing/ImpAnim/F_Imp_4.png"),
	preload("res://assets/fishing/ImpAnim/F_Imp_5.png"),
	preload("res://assets/fishing/ImpAnim/F_Imp_6.png"),
]

var _item_sizes := {
	Kind.DIAMOND: Vector2(18, 18),
	Kind.CHARM: Vector2(24, 24),
	Kind.CLOUD: Vector2(38, 38),
	Kind.IMP: Vector2(28, 28),
}




func _ready() -> void:
	_rng.randomize()
	_build_defs()
	_setup_player_view()
	_setup_bg_view()
	_start_round()


## 露娜視覺：實例化 F_Player.tscn 掛到 luna_view，由它接管角色繪製。
## 場景結構不符預期（沒有 AnimatedSprite2D）時退回 F_Luna.png 靜態貼圖
## （_draw_boat 的舊路徑，luna_view 保持 null）。
func _setup_player_view() -> void:
	luna_view = F_PLAYER_SCENE.instantiate()
	_anim = luna_view.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _anim == null:
		luna_view.queue_free()
		luna_view = null
		return
	_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 縮放必須在這裡就設好：READY 期間 _process 推幀前就會先畫出第一幀，
	# 沒設的話開場會以貼圖原尺寸（358×305）畫出一個巨無霸露娜。
	_anim.scale = Vector2(PLAYER_SCALE, PLAYER_SCALE)
	_anim.pause()                 # 幀由 _process 手動推（凍結時畫面才跟著凍）
	luna_view.name = "LunaView"
	add_child(luna_view)
	# 子節點一律畫在父節點 _draw() 之後（在釣線之上）——把玩家壓到 -1 層，
	# 釣線與鉤頭才不會被角色貼圖擋住。鉤子本來就掛在船的前方，這是正確的遮蔽順序。
	luna_view.z_index = -1
	_p_anim = PAnim.IDLE
	_p_time = 0.0
	_p_oneshot = false
	_anim.animation = P_ANIM_NAMES[PAnim.IDLE]
	_anim.frame = 0
	_apply_frame_anchor()


## 物件資料表
## 收線速度就是「重量」欄位：輕→快、中→普通、重→慢、極重→極慢。
func _build_defs() -> void:
	_defs = {
		Kind.DIAMOND: {"score": 200, "pull": 85.0,  "size": Vector2(32, 32), "col": Palette.PEARL, "label": "DIAMOND"},
		Kind.CHARM:   {"score": 100, "pull": 85.0,  "size": Vector2(32, 32), "col": Palette.GOLD,  "label": "CHARM"},
		Kind.CLOUD:   {"score": 10,  "pull": 160.0, "size": Vector2(32, 32), "col": Palette.FAR,   "label": "CLOUD"},
		Kind.IMP:     {"score": 0,   "pull": 105.0, "size": Vector2(16, 16), "col": Palette.CAT,   "label": "-3 SEC"},
	}


func _score_of(k: int) -> int:
	return int(_defs[k]["score"])


func _is_treasure(k: int) -> bool:
	# 月光能量要判斷「寶物還是廢物」：有分數的是寶物，小惡魔是廢物
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
	_p_anim = PAnim.IDLE
	_p_time = 0.0
	_p_oneshot = false
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


## 依水層配置鋪放水下物件。四種物件都屬於「族群」，
## 撈走後會有新的游進來（見 _schedule_respawn）—— 這是為了讓 60 秒的
## 計分上限取決於玩家手速，而不是取決於盤面總值。
func _populate() -> void:
	items.clear()
	_respawns.clear()
	# 帶最窄的先放：寶珠的中層帶只有 46px 高，被鑽石佔走就生不出來；
	# 鑽石帶（中/深層）大得多，放後面容錯高。
	_spawn_many(Kind.CHARM, 4, MID)                        # 中層
	_spawn_many(Kind.DIAMOND, 6, Vector2(MID.x, DEEP.y))   # 中／深層
	_spawn_many(Kind.CLOUD, 8, ANY)                        # 任意層
	_spawn_many(Kind.IMP, 4, ANY)                          # 任意層，會游動


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
	if kind == Kind.IMP:
		it.vx = 12.0 * (1.0 if _rng.randf() < 0.5 else -1.0)

	# 兩段式：先要求物件之間留 4px 空隙，真的擠不下就退讓成「不重疊即可」。
	# 不這樣做的話，族群補充在滿場時會靜靜地失敗，魚群會隨著時間越來越稀。
	# 嘗試 500 次：翻倍數量＋32px 大物件後空間很緊，40 次會偶爾生不出來
	# （模擬：500 次 + 先小後大的放置順序 = 10000 局零失敗）。
	for margin in [4.0, 0.0]:
		for _try in 500:
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
	var d := it.pos - LINE_ORIGIN
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
## 重生延遲 5~15 秒、隨剩餘時間由慢到快：開局撈走的等最久（15 秒），
## 局末很快就補回來（5 秒）。
func _schedule_respawn(kind: int) -> void:
	if not RESPAWN_KINDS.has(kind):
		return
	var delay := RESPAWN_MIN + (RESPAWN_MAX - RESPAWN_MIN) * (time_left / ROUND_TIME)
	_respawns.append({"kind": kind, "timer": delay, "band": RESPAWN_KINDS[kind]})


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
	if luna_view != null:
		# 動畫場景對齊到船底龍骨（含鏡頭位移；純視覺，見 luna_view 註解）
		luna_view.position = _luna_anchor() + _juice.world_offset()
		_update_player_anim(delta)
	if _bg_view != null:
		_bg_view.queue_redraw()   # 背景層每幀重繪（視差位移會變）
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
	return LINE_ORIGIN + _hook_dir() * line_len


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
			# 力道與重量成反比（pull 就是重量欄）：還沒看清楚就先
			# 感覺到鉤到什麼。鑽石與寶珠最重（收得最慢）撞得最兇，
			# 雲朵最輕幾乎沒感覺。
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
			carried.phase += delta   # 收線途中動畫繼續播（游泳相位計時）
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
	if it.kind == Kind.IMP:
		_play_oneshot(PAnim.HURT)              # 小惡魔：受傷動畫
		AudioManager.play_sfx("fishing_boom")        # 小惡魔：扣時間
		time_left = maxf(0.0, time_left - 3.0)
		_juice.kick(0.80)
		_juice.freeze(0.12)
		_fx.burst(PIVOT, 16, Palette.WARN, 100.0, 0.6, 3.0, 0.7)
		_pop("-3 SEC", Palette.WARN)
	else:
		var gained := _score_of(it.kind)
		score += gained
		if gained > 0:
			_play_oneshot(PAnim.GETPOINT)     # 寶物上船：慶祝動畫
			AudioManager.play_sfx("fishing_gainpoints")   # 上船加分
			var col: Color = Palette.GOLD if it.kind == Kind.CHARM else Palette.TEXT
			if it.kind == Kind.CHARM:
				_juice.kick(0.55)
				_juice.freeze(0.10)
				_fx.burst(PIVOT, 22, Palette.GOLD, 115.0, 0.75, 3.0, 0.55)
			elif it.kind == Kind.DIAMOND:
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
	var imps := []          # 這幀場上的小惡魔（散開判定用，最多 4 隻）
	for it in items:
		it.phase += delta
		if it.kind == Kind.IMP:
			imps.append(it)
		if it.vx == 0.0:
			continue

		if it.kind == Kind.IMP and line_out:
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

	# 小惡魔互斥：兩兩比較，距離小於 IMP_MIN_SEP 就沿連線各推一半 ——
	# 追鉤頭擠成一團之後線一收就會重新四散，任何時候都不會重疊。
	for i in imps.size():
		for j in range(i + 1, imps.size()):
			var a: Item = imps[i]
			var b: Item = imps[j]
			var d := b.pos - a.pos
			var dist := d.length()
			if dist >= IMP_MIN_SEP:
				continue
			var push: Vector2 = d / maxf(dist, 0.001) * (IMP_MIN_SEP - dist) * 0.5
			a.pos -= push
			b.pos += push
	# 推開可能把彼此推出水域邊界，補一次夾住
	for imp: Item in imps:
		imp.pos.x = clampf(imp.pos.x,
			WATER_L + imp.size.x * 0.5, WATER_R - imp.size.x * 0.5)
		imp.pos.y = clampf(imp.pos.y, SURFACE_Y + 14.0, WATER_B - 6.0)


# ── 繪製 ────────────────────────────────────────────────

func _draw() -> void:
	# 三層（見 shared/juice.gd 的分層模型）：背景由 _bg_view（z=-2）畫、
	# 玩家 luna_view 壓在 z=-1，其餘世界內容與 HUD 都在這層（z=0）——
	# 子節點一律畫在父節點 _draw() 之後，背景留在這裡會被玩家蓋住。
	draw_set_transform(_juice.world_offset())
	#_draw_water()                      # 水面線跟世界同步，船才不會浮起來
	for it in items:
		_draw_item(it)
	_draw_boat()
	_draw_line_and_hook()   # 畫在船之後：釣線（與鉤頭）在角色前方
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


## 背景層（天空／月亮／星星／遠山／全屏背景影片）畫在獨立子節點 z=-2：
## 玩家 luna_view 在 z=-1，背景留在父節點 _draw() 會蓋過玩家
## （子節點一律畫在父節點之後，父節點自己的輸出拆不出「玩家之下」的層）。
## 這層唯一會變的是視差位移（bg_offset），_process 每幀重繪它。
class BgView extends Node2D:
	var game = null   # fishing 節點；不型別，執行期取背景狀態
	func _draw() -> void:
		if game == null:
			return
		draw_set_transform(game._juice.bg_offset())
		var m := Juice.OVERDRAW
		# 天空底色要往下延伸超過水面線 —— 水體畫在 WORLD 層，兩層分離時
		# 如果天空只畫到 y=96，水面線附近就會裂開一條沒人畫的縫。
		draw_rect(Rect2(-m, -m, game.SCREEN.x + m * 2.0, game.SURFACE_Y + m * 2.0), Palette.BG)
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
				Vector2(bx, game.SURFACE_Y), Vector2(bx + 38, game.SURFACE_Y - 26),
				Vector2(bx + 76, game.SURFACE_Y)]), Palette.FAR)
		# 背景影片的當前幀（或載入失敗時的靜態圖）：等比例縮放填滿整個
		# 畫面、水平垂直置中，超出畫面的部分裁掉 —— 素材尺寸任意都能自適應。
		var vtex: Texture2D = null
		if game._bg_video != null:
			vtex = game._bg_video.get_video_texture()
		if vtex != null and vtex.get_size().x > 0.0:
			var vs := vtex.get_size()
			var s := maxf(game.SCREEN.x / vs.x, game.SCREEN.y / vs.y)
			var w := vs.x * s
			var h := vs.y * s
			draw_texture_rect(vtex,
				Rect2((game.SCREEN.x - w) * 0.5, (game.SCREEN.y - h) * 0.5, w, h), false)
		else:
			draw_texture_rect(game.bg_texture,
				Rect2(2, 15, game.SCREEN.x - 2, game.SCREEN.y - 10), false)


func _setup_bg_view() -> void:
	# 背景影片（F_BG_Anim.ogv）：VideoStreamPlayer 只負責解碼播放、節點本身
	# 隱藏（它是 Control，不隱藏會用自己的尺寸把影片畫在角落），畫面由
	# BgView 手繪 —— 跟 launcher 的標題／待機影片同一套做法。循環靠 loop，
	# finished 重播是保險（同 launcher）。載入失敗（素材沒進場）退回靜態圖。
	_bg_video = VideoStreamPlayer.new()
	_bg_video.name = "BgVideo"
	var stream: VideoStream = load("res://assets/fishing/F_BG_Anim.ogv")
	if stream != null:
		_bg_video.stream = stream
	_bg_video.autoplay = true
	_bg_video.loop = true
	_bg_video.visible = false
	_bg_video.connect("finished", Callable(self, "_on_bg_video_finished"))
	add_child(_bg_video)
	var v := BgView.new()
	v.game = self
	v.name = "BgView"
	v.z_index = -2
	add_child(v)
	_bg_view = v


## loop=true 的保險：萬一播放器到片尾沒接上循環，重播一次（同 launcher）
func _on_bg_video_finished() -> void:
	if _bg_video != null:
		_bg_video.play()


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
		size: Vector2,
		flip_h := false
	) -> void:

	if texture == null:
		return

	if flip_h:
		# 水平鏡像：把物體中心當原點、x 軸反轉後再畫（draw_texture_rect
		# 沒有 flip 參數）。呼叫點都在 WORLD 層（變換＝鏡頭位移），
		# 畫完恢復原變換，不影響後續繪製。
		var wo := _juice.world_offset()
		draw_set_transform(center + wo, 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect(texture, Rect2(-size * 0.5, size), false)
		draw_set_transform(wo)
		return

	draw_texture_rect(
		texture,
		Rect2(center - size * 0.5, size),
		false
	)

func _draw_item(it: Item) -> void:
	if it.kind == Kind.IMP:
		# 小惡魔的游泳動畫：7 幀循環。用 it.phase 驅動 —— 每隻初始相位
		# 隨機，不會整場同步（跟鑽石閃光同一顆計時器，互不干擾）。
		var f := int(it.phase * IMP_ANIM_FPS) % _imp_frames.size()
		var tex: Texture2D = _imp_frames[f]
		var size: Vector2 = _item_sizes[Kind.IMP]
		# 泳姿朝向：放線時往鉤頭靠（水平分量）、平時按自己的游速；掛上鉤
		# 後維持最後朝向。美術默認朝左，往右游要水平鏡像。
		var dir := signf(it.vx)
		if hook_state != Hook.SWING and it != carried:
			dir = signf(_hook_pos().x - it.pos.x)
		_draw_centered_texture(tex, it.pos, size, dir > 0.0)
		return
	var texture: Texture2D = _textures.get(it.kind)
	if texture == null:
		return

	var size : Vector2 = _item_sizes.get(it.kind, texture.get_size())
	_draw_centered_texture(texture, it.pos, size)
	if it.kind == Kind.DIAMOND:
		_draw_diamond_flash(it)


## 鑽石的表面白光閃爍：二值閃（0.4 秒週期、亮 0.2 秒），亮的時候在貼圖上疊
## 一個白色十字星芒＋中心白點。用 it.phase 驅動 —— 每顆初始相位隨機，
## 不會整場同步閃；只讀相位不改狀態，掛在鉤上收線時照樣閃。
func _draw_diamond_flash(it: Item) -> void:
	if fmod(it.phase, 0.4) >= 0.2:
		return
	var s := it.size.x
	var col := Color(Palette.MOON_LIGHT, 0.85)
	draw_line(it.pos + Vector2(-s * 0.2, 0), it.pos + Vector2(s * 0.2, 0), col, 0.5)
	draw_line(it.pos + Vector2(0, -s * 0.2), it.pos + Vector2(0, s * 0.2), col, 0.5)
	draw_circle(it.pos, s * 0.05, col)




func _draw_line_and_hook() -> void:
	var tip := _hook_pos()
	# 星光釣線：亮青白 1px。勾中的瞬間整條線閃一次白（GDD 指定）。
	var line_col: Color = Palette.TEXT if _line_flash > 0.0 else Palette.MOON
	var line_w := 2.0 if _line_flash > 0.0 else 1.0
	draw_line(LINE_ORIGIN, tip, line_col, line_w)
	# 鉤頭是小星星
	draw_circle(tip, 2.5, Palette.TEXT)
	draw_rect(Rect2(tip.x - 3.5, tip.y - 0.5, 7, 1), Palette.MOON)
	draw_rect(Rect2(tip.x - 0.5, tip.y - 3.5, 1, 7), Palette.MOON)
	# 掛在鉤上的獵物。位置在 _extend()/_retract() 更新，
	# **不要在這裡改** —— _draw() 裡改遊戲狀態的話，鏡頭位移會被寫進
	# carried.pos 再被 _retract() 讀回去，讓獵物的真實位置被污染。
	if carried != null:
		_draw_item(carried)


## 露娜（船底龍骨）在遊戲座標的位置：船底中央對齊水面線。
## 釣線起點是獨立的 LINE_ORIGIN（預設與船底同點），改它不會動到船。
func _luna_anchor() -> Vector2:
	return Vector2(PIVOT.x, SURFACE_Y)


## 觸發一次性動畫（GETPOINT／HURT）：立即中斷目前動畫，播完回基礎動畫。
## 在 _land() 裡呼叫 —— 上船結算的那一幀就切，不等到下一幀。
func _play_oneshot(anim: int) -> void:
	_p_anim = anim
	_p_time = 0.0
	_p_oneshot = true
	if _anim != null:
		_anim.animation = P_ANIM_NAMES[anim]
		_anim.frame = 0
		_apply_frame_anchor()


## 露娜動畫狀態機（手動推幀，見 PAnim／P_ANIM_NAMES）：
## 基礎動畫由鉤子狀態決定 —— 線在外面（放線／收線途中）播 Hook，否則 Idle；
## 一次性動畫（GETPOINT／HURT）播完才回基礎動畫，期間不被 Hook／Idle 打斷。
func _update_player_anim(delta: float) -> void:
	if _anim == null:
		return
	var base: int = PAnim.HOOK if hook_state != Hook.SWING else PAnim.IDLE
	var anim := _p_anim if _p_oneshot else base
	if anim != _p_anim:
		_p_anim = anim
		_p_time = 0.0
		_p_oneshot = anim == PAnim.GETPOINT or anim == PAnim.HURT
		_anim.animation = P_ANIM_NAMES[_p_anim]
		_anim.frame = 0
	var name: StringName = P_ANIM_NAMES[_p_anim]
	var frames := _anim.sprite_frames.get_frame_count(name)
	_p_time += delta
	var f := int(_p_time * _anim.sprite_frames.get_animation_speed(name))
	if _p_oneshot and f >= frames:
		# 一次性動畫播完 → 回到基礎動畫
		_p_oneshot = false
		_p_anim = base
		_p_time = 0.0
		_anim.animation = P_ANIM_NAMES[_p_anim]
		f = 0
	elif not _p_oneshot:
		f %= frames
	if _anim.frame != f:
		_anim.frame = f
	_apply_frame_anchor()


## 動畫錨點：每段動畫共用一個 offset（由 P_REFS 參考框算出，所有幀的
## 畫布尺寸相同）—— 內容中心對到 x=0、內容底（船底龍骨）對到 y=0，
## luna_view 的位置就是錨點（_luna_anchor + 鏡頭位移），所以船底永遠
## 貼著水面線、水平置中。
## 不做逐幀歸一化：畫師的幀都在同一畫布、內容位置一致，逐幀錨定反而會
## 讓船跟著角色的肢體擺動（抬手、伸杆子）而左右滑、上下跳。
## offset 是未縮放座標（scale 乘在整個節點上），錨點正好是 0 所以
## 不需要像 Seeker 那樣加 ÷scale 的腳底偏移項。
func _apply_frame_anchor() -> void:
	var name: StringName = P_ANIM_NAMES[_p_anim]
	var b: Rect2 = P_REFS[name]
	var ts: Vector2 = _anim.sprite_frames.get_frame_texture(name, _anim.frame).get_size()
	_anim.offset = Vector2(
		ts.x * 0.5 - b.get_center().x,
		ts.y * 0.5 - b.end.y)


func _draw_boat() -> void:
	# 露娜的統一繪製入口：動畫場景（luna_view）掛上後由它接管，跳過貼圖
	if luna_view != null:
		return
	if s_luna == null:
		return
	# 整張貼圖（船＋露娜一體）：船底龍骨（貼圖 y=269）對齊水面線
	var s := LUNA_SIZE.x / s_luna.get_width()
	var top := SURFACE_Y - LUNA_KEEL * s
	draw_texture_rect(s_luna,
		Rect2(PIVOT.x - LUNA_SIZE.x * 0.5, top, LUNA_SIZE.x, s_luna.get_height() * s),
		false)


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
	# 右：分數（滾動中的值）。背景框右緣對齊原 DEPTH 的右邊界（480-12），
	# 只動 X、Y 不變（框 17.5／文字 34.0）。背景框在 1920×1080 設計座標
	# (768,70)、文字 baseline (990,92)，除以 4 到邏輯畫面（同 launcher 慣例）。
	var fsize := s_score_frame.get_size() / 4.0
	var fx := SCREEN.x - 12.0 - fsize.x
	draw_texture_rect(s_score_frame, Rect2(fx, 17.5, fsize.x, fsize.y), false)
	draw_string(font, Vector2(fx + 23.0, 34.0), "%06d" % int(round(_score_shown)),
		HORIZONTAL_ALIGNMENT_CENTER, fsize.x, 12, Palette.LUNA)

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
