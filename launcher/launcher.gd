extends Node2D

# ─────────────────────────────────────────────────────────
# 啟動標題 + 遊戲流程狀態機：
#   MENU（一級標題＝管理員的遊戲選擇畫面：↑ ↓ 循環選遊戲／SETTING、
#     B 開當前選中遊戲的排行榜清除選單、A 確認）
#   → GAME_TITLE（二級標題＝該款全屏影片背景，無按鈕、底部一行閃爍的
#     PRESS ANY BUTTON TO START 提示：按**任意鍵** → 起名開局；A／B 例外 —— 兩個一起按住 3 秒 →
#     管理員密碼界面，提前鬆開＝普通按鍵 → 起名。開局一律過投幣閘門：
#     Y＝投幣（InputMap coin_insert，不觸發起名）；幣不夠（且非無限投幣）
#     → 左下角 Coin 圖抖動＋UI_Coin_None、留在二級，夠 → 扣幣＋UI_confirm
#     → 起名。幣量與閘門在 CoinManager，UI 畫在本檔 _draw_coin_ui）
#
#   街機鍵位（2026-09 起，shared/arcade_input.gd ＋ project.godot [input]，
#   鍵盤與 Xbox 手柄同時生效）：A＝鍵盤 A／手柄 A、B＝鍵盤 S／手柄 B
#   （2026-09 鍵盤 B 的邏輯全部改到 S，鍵盤 B 不再有用）、投幣
#   Y＝鍵盤 Y／手柄 View/Back。手柄按鈕事件不進 _unhandled_key_input，
#   所以本檔的按鍵處理走 _unhandled_input，A／B／投幣一律讀 InputMap action。
#   管理員界面（一級清單／SETTING 二三級）的 ↑↓ 選擇另收手柄左搖杆上下
#   （_pad_stick_nav：死區 ±0.5、邊沿觸發不連發）；其餘方向輸入仍只吃鍵盤。
#   → NAME_INPUT → PLAYING
#   → GAME_OVER（局終結算界面）→ LEADERBOARD（排行榜）
#   一級標題選中 SETTING 按 A → SETTING（二級：CLEAR LEADERBOARD /
#     UNLIMITED COINS / MUSIC —— MUSIC 只關 BGM 不關音效，A 執行、B 回一級）
#   → SETTING_CLEAR（三級：CLEAR TODAY / LAST 24 HOURS / ALL DATA，
#     跨三款一起清、A 執行、B 回 SETTING）
#
# 標題層：一級畫 Title_ChooseGames（assets/title/）＋遊戲選擇清單（名字用
# draw_string 疊在圖上）；二級畫該款的全屏背景影片
# （assets/title/TItleVideo/Title_*.ogv，等比例縮放填滿 480×270，素材沒
# 進場時退回該款的標題圖 title_image）。二級標題是
# 「固定場所」：不響應 1/2/3 與 ESC，**唯一回一級的路徑是管理員密碼界面**
# （ui/admin_password.gd，Modal Overlay，二級標題 A＋B 長按 3 秒進入）：
# 用方向鍵輸入「上上下下左右左右」共 8 位指令、按 A 確認 —— 正確 → 回一級、
# ESC → 留在二級。遊戲結束與遊戲中 ESC 都回**該款的二級標題**。
# 一級標題按 B 開**當前選中遊戲的排行榜清除選單**（ui/admin_clear_menu.gd，
# Modal Overlay，見「清除功能」段落）。
# 彈窗開著時本檔不處理任何按鍵（輸入分層見 _unhandled_input 註解）。
#
# 二級標題另有「待機」狀態（IDLE，2026-08 新增）：進二級起 10 秒無操作
# 計時，↑↓←→／A／B 任一輸入重設計時；連續 10 秒無輸入 → 隱藏標題圖、
# 播放該款的待機影片（VideoStreamPlayer loop，節點本身隱藏、畫面由
# _draw() 手繪：等比例縮放置中＋中央閃爍 CLICK TO PLAY），任一有效輸入
# 喚醒（該輸入被吃掉，不觸發起名）。影片路徑在 GAMES 的 idle_video 欄位
# （引擎內建 VideoStreamPlayer 只吃 Ogg Theora，MP4 素材要先轉 .ogv）。
#
# 遊戲不是場景，是「掛在臨時 Node2D 上的腳本」：
#   load(path) → Node2D.new() → set_script() → add_child()
# add_child() 那一刻才會觸發遊戲的 _ready()，所以順序不能調換。
# 回選單時直接 queue_free() 整個節點，遊戲自己生的子節點跟著一起消失，
# 不需要每款遊戲各寫一套清理邏輯。
#
# 局終流程（LeaderboardRecord / LeaderboardManager / Game Over 界面 /
# 排行榜面板，見 shared/ 與 ui/）：
#   遊戲進 RESULT 時發 round_finished(score, duration, game_over)
#   → launcher 組裝記錄、submit_score()、開 Game Over 界面
#   （ui/game_over.gd：GAME OVER ／分數／排名／玩家名字的 1 秒動畫，
#   沒有按鈕、不吃按鍵，播完**自動**開排行榜面板 —— 舊版 RESTART／
#   LEADERBOARD 兩鈕已於 2026-09 移除）
#   排行榜面板 = 大標題 YOUR SCORE ＋ 前 10 名單欄 ＋ 底部當前玩家行，
#   進入時逐行交錯顯現；面板 B/ESC = 回該款二級標題（清名字）。
#   名字由 CurrentPlayerSession 管理：第一次進遊戲先輸入，回二級即清。
#
# 新增一款遊戲＝在 GAMES 加一筆（含 id），不用新增場景、不用改這支以外的檔案。
# 腳本還不存在的項目會顯示 NOT BUILT YET，不會讓選單當掉。
# ─────────────────────────────────────────────────────────

enum Mode { MENU, GAME_TITLE, NAME_INPUT, PLAYING, GAME_OVER, LEADERBOARD, SETTING, SETTING_CLEAR }

const GAMES := [
	{
		"id": "seeker",
		"title": "CHARMS SEEKER",
		"menu_name": "MAZE",             # 一級標題遊戲選擇清單顯示的短名
		"bgm": "MAZE",                   # 開局時的 BGM（AudioManager 名稱）
		"blurb": "MAZE CHASE",
		"script": "res://games/seeker/seeker.gd",
		"title_image": preload("res://assets/title/Title_Maze.jpg"),
		"title_video": "res://assets/title/TItleVideo/Title_Maze.ogv",
		"naming_image": preload("res://assets/title/Naming/Name_Charmsseeker.png"),
		"idle_video": "res://assets/title/IdleVideo/CharmsSeeker_Idle.ogv",
	},
	{
		"id": "fishing",
		"title": "CHARMS FISHING",
		"menu_name": "FISHING",
		"bgm": "FISHING",
		"blurb": "HOOK THE CHARMS",
		"script": "res://games/fishing/fishing.gd",
		"title_image": preload("res://assets/title/Title_Fishing.jpg"),
		"title_video": "res://assets/title/TItleVideo/Title_Fishing.ogv",
		"naming_image": preload("res://assets/title/Naming/Name_Charmsfishing.png"),
		"idle_video": "res://assets/title/IdleVideo/CharmsFishing_Idle.ogv",
	},
	{
		"id": "catch",
		"title": "CHARMS CATCH",
		"menu_name": "CATCH",
		"bgm": "CATCH",
		"blurb": "CATCH AND DODGE",
		"script": "res://games/catch/catch.gd",
		"title_image": preload("res://assets/title/Title_Catch.jpg"),
		"title_video": "res://assets/title/TItleVideo/Title_Catch.ogv",
		"naming_image": preload("res://assets/title/Naming/Name_CharmsCatch.png"),
		"idle_video": "res://assets/title/IdleVideo/CharmsCatch_Idle.ogv",
	},
]

## 一級標題全屏圖。二級標題的背景影片（title_video）與備用標題圖
## （title_image）掛在各 GAMES 條目。
const TITLE_MAIN_IMAGE: Texture2D = preload("res://assets/title/Title_ChooseGames.png")

const NOTICE_TIME := 1.6      # 「還沒做」提示停留幾秒

## 一級標題遊戲選擇清單的兩色（需求指定）：選中 / 未選中
const MENU_SELECTED := Color("FFC4FF")
const MENU_IDLE := Color("FF44FF")

## 管理員選單區域：1920×1080 設計座標 (734, 392) 起、651×291（邏輯畫面 ÷4）。
## 一級遊戲清單（三款遊戲＋SETTING）、SETTING 二級、清除三級都畫在這一塊內。
## 註：需求原文就是 (734,392)；舊常量 (774,452) 與自身註解不符，2026-08 修正。
const MENU_REGION_POS := Vector2(734.0, 425.0) / 4.0
const MENU_REGION_SIZE := Vector2(651.0, 330.0) / 4.0
const MENU_NAME_SIZE := 16
const MENU_SUB_SIZE := 11      # SETTING 二級／三級選單的字體（選項名字比一級長）
const MENU_LINE_H := 18.0      # 4 行（三款遊戲＋SETTING）塞進 291 高的區域

## SETTING 二級選單的三個選項（索引即 setting_index）。MUSIC 只控制 BGM：
## 狀態存 Settings（跨執行保存），AudioManager 播 BGM 前與切換當下讀取。
const SETTING_OPTIONS := ["CLEAR RANKING DATA", "UNLIMITED COINS", "MUSIC"]
const SETTING_CLEAR_IDX := 0
const SETTING_COINS_IDX := 1
const SETTING_MUSIC_IDX := 2

## 三級排行榜清除選單：顯示名與對應的 ClearRule（TODAY／LAST_24_HOURS／ALL，
## 索引順序一致）。執行時跨三款遊戲一起清，見 _draw_clear_menu 與
## LeaderboardManager.clear_all_games_records。
const CLEAR_OPTIONS := ["CLEAR TODAY", "CLEAR LAST 24 HOURS", "CLEAR ALL DATA"]
const CLEAR_RULES := [
	LeaderboardManager.ClearRule.TODAY,
	LeaderboardManager.ClearRule.LAST_24_HOURS,
	LeaderboardManager.ClearRule.ALL,
]


## 二級標題的管理員入口：A＋B 同時按住滿這個秒數 → 管理員密碼界面。
## （不足 3 秒就鬆開＝普通按鍵，照樣進入起名流程。）
const AB_HOLD_SECONDS := 3.0

## 二級標題待機（IDLE）：連續這個秒數沒有任何有效輸入（↑↓←→／A／B）→
## 隱藏標題圖、全屏播放該款待機影片；任一有效輸入喚醒（輸入被吃掉）。
const TITLE_IDLE_SECONDS := 10.0

## 待機計時與喚醒認定的有效街機輸入（與二級標題正常流程用的同一組按鍵，
## 見 _unhandled_input 的分層註解）。待機狀態下只有這幾個鍵能喚醒，
## 喚醒的那一次輸入不會繼續觸發二級標題原本的操作。
## 手柄 A／B 不吃 keycode，由 _is_wake_input 的 action 判斷補上。
const TITLE_IDLE_WAKE_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_A, KEY_S]

## 待機畫面中央 CLICK TO PLAY 的閃爍週期（秒）與每週期亮著的時長。
const IDLE_PROMPT_PERIOD := 1.2
const IDLE_PROMPT_ON_SECONDS := 0.7

## 二級標題底部 PRESS ANY BUTTON TO START 的閃爍週期（秒）與每週期亮著的
## 時長。與待機的 CLICK TO PLAY 同款：亮滅二值閃爍。
const START_PROMPT_PERIOD := 1.2
const START_PROMPT_ON_SECONDS := 0.7

## 二級標題 PRESS ANY BUTTON TO START 與投幣數字的每款配色（2026-09 企劃
## 指定，跟各款標題影片的美術配色走）。只用在 launcher 標題層文字，不進
## shared/palette.gd 的 21 色共用遊戲色盤；鍵＝GAMES 的 id。
const TITLE_TEXT_COLORS := {
	"seeker": {"text": Color("F349CC"), "shadow": Color("7207A0")},
	"fishing": {"text": Color("4982F3"), "shadow": Color("2923D1")},
	"catch": {"text": Color("A351F8"), "shadow": Color("4311B7")},
}


## ── 投幣 UI（二級標題左下角，2026-09）────
## Coin 圖與幣量文字：1920×1080 設計座標 (70, 940) 起、48×48（÷4 = 邏輯
## (17.5, 235) 起、12×12）。Coin.png 原圖 1312×1199，全專案最近鄰取樣，
## 百倍縮小直接畫會糊成一團 —— _ready() 裡用 Image LANCZOS 一次降採樣
## 到 12×12 再畫。
const COIN_SOURCE: Texture2D = preload("res://assets/UI/Coin.png")
const COIN_UI_POS := Vector2(70.0, 940.0) / 4.0
const COIN_UI_SIZE := Vector2(48.0, 48.0) / 4.0
const COIN_UI_TEXT_GAP := 4.0    # 狀態文字與 Coin 圖右緣的間距（邏輯 px）

## 幣不夠被擋下時 Coin 圖的水平抖動：總時長與振幅（邏輯 px，畫面上 ×4）。
const COIN_SHAKE_SECONDS := 0.4
const COIN_SHAKE_AMPLITUDE := 2.0


var mode := Mode.MENU
var game: Node2D = null       # 目前正在玩的那一款，沒在玩時為 null
var active_index := -1        # 目前這局是哪一款（排行榜重開要用）
var _panel: Node2D = null
var _name_input: Node2D = null
var _password_modal: Node2D = null   # F3 管理員密碼彈窗；非 null 時攔下所有標題層按鍵
var _clear_modal: Node2D = null      # 排行榜清除選單；同上，開著時標題層不響應
var _built: Array[bool] = []  # 每一款的腳本存不存在，開場算一次就好
var _notice := ""
var _notice_col := Palette.WARN   # 提示文字顏色（清除成功用 GOLD）
var _notice_timer := 0.0
var _finish_data := {}        # 局終暫存：record_id / score / game_over
var _ab_hold_active := false  # 二級標題：A／B 有被按下，等待長按判定（提前鬆開＝普通按鍵）
var _ab_hold_time := 0.0      # A＋B 同時按住的累計秒數（滿 AB_HOLD_SECONDS 進管理員密碼）
var _stick_nav_dir := 0       # 手柄左搖杆垂直推量（0 中立／-1 上／1 下）：管理員界面 ↑↓ 選擇的邊沿觸發狀態
var _title_idle := false      # 二級標題待機狀態：true = IDLE（在播待機影片）、false = NORMAL
var _title_video: VideoStreamPlayer = null   # 二級標題背景影片（NORMAL 與起名 overlay 的底層）
var _idle_video: VideoStreamPlayer = null
var _idle_timer: Timer = null
var _idle_prompt_elapsed := 0.0   # CLICK TO PLAY 閃爍相位（秒），進待機時歸零
var _start_prompt_elapsed := 0.0  # 底部 PRESS ANY BUTTON TO START 閃爍相位（秒），進二級時歸零
var _title_stream_cache: Dictionary = {}  # game index → VideoStream；載入失敗記 null 不重試
var _idle_stream_cache: Dictionary = {}   # game index → VideoStream；載入失敗記 null 不重試
var _coin_tex: Texture2D = null   # 投幣 UI 的 Coin 圖（_ready 降到 12×12；解不開時用原圖）
var _coin_shake_time := 0.0       # 幣不夠的 Coin 圖抖動剩餘秒數（>0 時每幀重繪）
var selected_game := 0        # 一級標題當前選中的項目（0..GAMES.size()，size()＝SETTING）
var setting_index := 0        # SETTING 二級選單：0 = CLEAR LEADERBOARD、1 = UNLIMITED COINS、2 = MUSIC
var clear_index := 0          # 三級清除選單：0 = CLEAR TODAY、1 = LAST 24 HOURS、2 = ALL


func _ready() -> void:
	# 全專案文字統一用像素字體（assets/fonts/PixelFont.ttf，10×12 網格、原生
	# 渲染尺寸 12px）：所有 draw_string 都讀 ThemeDB.fallback_font，換掉它
	# 全部界面文字一次生效。load 失敗（素材沒進場）時維持引擎預設字型。
	var pixel_font := load("res://assets/fonts/PixelFont.ttf") as Font
	if pixel_font:
		ThemeDB.fallback_font = pixel_font

	# 用 ResourceLoader 而不是 FileAccess：匯出後 .gd 會被編譯進 pck 並重新對應，
	# FileAccess.file_exists() 在匯出版會一律回 false，選單就全變成 COMING SOON。
	for entry in GAMES:
		_built.append(ResourceLoader.exists(entry["script"]))

	# 二級標題背景影片（NORMAL 與起名 overlay 的底層）：與待機影片同款做法
	# —— VideoStreamPlayer 只負責播放、**節點本身隱藏**（它是 Control，
	# expand=false 時會用自己的尺寸把影片畫在角落），畫面統一由 _draw() 的
	# _draw_title_background() 手繪（等比例縮放置中）。
	_title_video = VideoStreamPlayer.new()
	_title_video.name = "TitleVideo"
	_title_video.autoplay = false      # 不自動播放：進二級標題才 play()
	_title_video.loop = true           # 無縫循環（_on_title_video_finished 是保險）
	_title_video.visible = false       # 節點不自己畫，畫面全走 launcher._draw()
	_title_video.connect("finished", Callable(self, "_on_title_video_finished"))
	add_child(_title_video)

	# 二級標題待機（IDLE）：VideoStreamPlayer 只負責播放，**節點本身隱藏**
	# （它是 Control，expand=false 時會用自己的尺寸把影片畫在角落、stop()
	# 後還會殘留最後一幀 —— 影片「不消失」的來源）；畫面統一由 _draw()
	# 手繪：等比例縮放置中＋CLICK TO PLAY 閃爍。Timer 管 10 秒無操作計時。
	_idle_video = VideoStreamPlayer.new()
	_idle_video.name = "IdleVideo"
	_idle_video.autoplay = false      # 不自動播放：進待機才 play()
	_idle_video.loop = true           # 無縫循環（_on_idle_video_finished 是保險）
	_idle_video.visible = false       # 節點不自己畫，畫面全走 launcher._draw()
	_idle_video.connect("finished", Callable(self, "_on_idle_video_finished"))
	add_child(_idle_video)

	_idle_timer = Timer.new()
	_idle_timer.name = "IdleTimer"
	_idle_timer.one_shot = true
	_idle_timer.wait_time = TITLE_IDLE_SECONDS
	_idle_timer.connect("timeout", Callable(self, "_on_idle_timer_timeout"))
	add_child(_idle_timer)

	# 投幣 UI 的 Coin 圖：原圖太大（1312×1199），載入時一次 LANCZOS 縮到
	# 顯示尺寸 12×12（設計 48×48 ÷4）。素材解不開（get_image 失敗）時退回
	# 原圖直接畫 —— 與「素材未進場不當機」的慣例一致；兩者皆不可用時
	# _draw_coin_ui 只畫文字。
	var coin_img: Image = COIN_SOURCE.get_image()
	if coin_img != null:
		coin_img.resize(int(COIN_UI_SIZE.x), int(COIN_UI_SIZE.y), Image.INTERPOLATE_LANCZOS)
		_coin_tex = ImageTexture.create_from_image(coin_img)
	else:
		_coin_tex = COIN_SOURCE

	queue_redraw()


func _process(delta: float) -> void:
	if _notice_timer > 0.0:
		_notice_timer -= delta
		if _notice_timer <= 0.0:
			_notice = ""
		queue_redraw()
	if _coin_shake_time > 0.0:
		# 幣不夠的 Coin 圖抖動：倒數到 0 自動停（_draw 的偏移同步歸 0）。
		_coin_shake_time = maxf(_coin_shake_time - delta, 0.0)
		queue_redraw()
	if mode == Mode.GAME_TITLE and not _title_idle:
		# 二級標題（NORMAL）：背景影片每幀更新＋底部提示的閃爍相位，都要每幀重繪。
		_start_prompt_elapsed += delta
		queue_redraw()
	elif mode == Mode.NAME_INPUT and _title_video.is_playing():
		# 起名 overlay：背景影片每幀更新，畫面要跟著重繪。
		queue_redraw()
	if mode == Mode.GAME_TITLE and _title_idle:
		# IDLE：每幀重繪讓待機影片畫面跟得上；不處理 A＋B 長按 ——
		# 待機中正常互動全部停止（輸入層面見 _unhandled_input）。
		# CLICK TO PLAY 的閃爍相位也在此累計。
		_idle_prompt_elapsed += delta
		queue_redraw()
		return
	if mode == Mode.GAME_TITLE and _ab_hold_active:
		# 二級標題的管理員入口：A＋B 同時按住滿 AB_HOLD_SECONDS 秒 →
		# 管理員密碼界面（不到 3 秒鬆開的話，放開分支會當普通按鍵進起名）。
		# 鍵盤 A＋S、手柄 A＋B（可混按）都算 —— 走同一組 InputMap action。
		if ArcadeInput.held(ArcadeInput.ACTION_A) and ArcadeInput.held(ArcadeInput.ACTION_B):
			_ab_hold_time += delta
			if _ab_hold_time >= AB_HOLD_SECONDS:
				_ab_hold_active = false
				_ab_hold_time = 0.0
				_open_password_modal()
		else:
			_ab_hold_time = 0.0


func _unhandled_input(event: InputEvent) -> void:
	# 只處理鍵盤與手柄「按鈕」：搖桿軸（InputEventJoypadMotion）、滑鼠等
	# 一律略過 —— 否則二級標題的「任意鍵」會被撥搖桿誤觸發。
	var key := event as InputEventKey
	var pad := event as InputEventJoypadButton
	var stick := event as InputEventJoypadMotion
	if key == null and pad == null and stick == null:
		return
	if key != null and key.echo:
		return

	# 手柄左搖杆（2026-09）：只餵管理員界面的 ↑↓ 選擇（_pad_stick_nav），
	# 其餘模式一律在這裡吃掉 —— 二級標題的「任意鍵」不能被撥搖桿誤觸發。
	if stick != null:
		if stick.axis == JOY_AXIS_LEFT_Y \
				and _password_modal == null and _clear_modal == null \
				and (mode == Mode.MENU or mode == Mode.SETTING or mode == Mode.SETTING_CLEAR):
			_pad_stick_nav(stick.axis_value)
		return

	# IDLE（待機）：二級標題的正常互動全部停止。↑↓←→／街機 A／B 其中一個
	# **按下** → 只喚醒、輸入被吃掉（不進起名、不進 A／B 長按判定）；
	# 投幣（Y／手柄 View）＝喚醒並照常投一枚幣（實體投幣隨時都收）；
	# 其餘按鍵（含放開）一律忽略。
	if mode == Mode.GAME_TITLE and _title_idle:
		if event.is_pressed() and _is_wake_input(event):
			_wake_from_title_idle()
		elif event.is_pressed() and _is_coin_insert(event):
			_wake_from_title_idle()
			_insert_coin()
		return

	# 放開事件只用於二級標題的 A／B 長按判定：兩顆鍵沒按住滿 3 秒就鬆開
	# ＝普通按鍵，照樣進入起名流程（進入密碼界面後 _ab_hold_active 已清，
	# 鬆開不會誤觸發）。起名／遊戲等子節點會吃掉自己的事件，收不到這裡。
	if not event.is_pressed():
		if mode == Mode.GAME_TITLE and _ab_hold_active \
				and (ArcadeInput.released(event, ArcadeInput.ACTION_A)
					or ArcadeInput.released(event, ArcadeInput.ACTION_B)):
			_ab_hold_active = false
			_ab_hold_time = 0.0
			_launch(active_index)
		return

	# NAME_INPUT / LEADERBOARD 的按鍵由各自的子節點處理並吃掉事件，
	# launcher 不需要也不應該碰。
	#
	# 輸入分層（街機 A／B／投幣走 InputMap action —— 鍵盤 A·S·Y 與手柄
	# A·B·View 都會命中；方向鍵維持鍵盤直讀 keycode，管理員界面的 ↑↓
	# 另收手柄左搖杆上下）：
	#   Level 1  密碼彈窗／清除選單開著 → 只剩彈窗自己的按鍵，這裡整段不處理
	#   Level 2  二級標題 → 按**任意鍵**進入起名流程（A／B 例外：先等長按
	#            判定 —— 兩顆一起按住 3 秒進管理員密碼界面、提前鬆開＝普通
	#            按鍵）。固定場所：1/2/3 不換遊戲、ESC 無效（回一級只有
	#            管理員密碼一條路）
	#   Level 3  一級標題 → ↑ ↓ 選遊戲／SETTING（循環）、B 開當前遊戲的
	#            排行榜清除選單、A 確認進二級標題（SETTING 則進 SETTING 二級選單）
	#   Level 4  SETTING 二級 → ↑ ↓ 選項、A 執行（CLEAR LEADERBOARD＝進三級、
	#            UNLIMITED COINS＝切換 ON/OFF）、B/ESC 回一級
	#   Level 5  SETTING_CLEAR 三級 → ↑ ↓ 選清除規則、A 執行（跨三款一起清）、
	#            B/ESC 回 SETTING 二級
	if _password_modal != null or _clear_modal != null:
		return                     # Level 1：彈窗開著，底層標題不響應任何鍵

	match mode:
		Mode.MENU:
			if ArcadeInput.pressed(event, ArcadeInput.ACTION_A):
				AudioManager.play_sfx("ui_confirm")   # A 確認（鍵盤 A／手柄 A）
				if selected_game >= GAMES.size():
					mode = Mode.SETTING     # SETTING → 二級選單
				else:
					_enter_game_title(selected_game)
				queue_redraw()
			elif ArcadeInput.pressed(event, ArcadeInput.ACTION_B):
				# B（鍵盤 S／手柄 B）開當前選中遊戲的清除選單
				if selected_game < GAMES.size():
					_open_clear_menu()     # SETTING 行 B 無操作
			elif key != null:
				match key.keycode:
					KEY_UP, KEY_DOWN:
						var dir := 1 if key.keycode == KEY_DOWN else -1
						selected_game = (selected_game + dir + GAMES.size() + 1) % (GAMES.size() + 1)
						AudioManager.play_sfx("ui_select")   # 選單移動
						queue_redraw()
					# A／B 已由上面的 action 分支吃掉，這裡不再比 keycode
		Mode.SETTING:
			if ArcadeInput.pressed(event, ArcadeInput.ACTION_A) \
					or (key != null and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]):
				AudioManager.play_sfx("ui_confirm")
				match setting_index:
					SETTING_CLEAR_IDX:
						mode = Mode.SETTING_CLEAR        # 進三級清除選單
					SETTING_COINS_IDX:
						Settings.set_unlimited_coins(not Settings.is_unlimited_coins())
					SETTING_MUSIC_IDX:
						_toggle_music()                  # 只關 BGM，音效不受影響
				queue_redraw()
			elif ArcadeInput.pressed(event, ArcadeInput.ACTION_B) \
					or (key != null and key.keycode in [KEY_S, KEY_ESCAPE]):
				mode = Mode.MENU                     # 回一級，選擇狀態保留
				queue_redraw()
			elif key != null and key.keycode in [KEY_UP, KEY_DOWN]:
				var dir := 1 if key.keycode == KEY_DOWN else -1
				setting_index = (setting_index + dir + SETTING_OPTIONS.size()) % SETTING_OPTIONS.size()
				AudioManager.play_sfx("ui_select")
				queue_redraw()
		Mode.SETTING_CLEAR:
			if ArcadeInput.pressed(event, ArcadeInput.ACTION_A) \
					or (key != null and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]):
				AudioManager.play_sfx("ui_confirm")
				LeaderboardManager.clear_all_games_records(CLEAR_RULES[clear_index])
				_show_notice("SCORE DATA CLEARED", Palette.GOLD)
				mode = Mode.SETTING                   # 執行完回二級，選項狀態保留
				queue_redraw()
			elif ArcadeInput.pressed(event, ArcadeInput.ACTION_B) \
					or (key != null and key.keycode in [KEY_S, KEY_ESCAPE]):
				mode = Mode.SETTING
				queue_redraw()
			elif key != null and key.keycode in [KEY_UP, KEY_DOWN]:
				var dir := 1 if key.keycode == KEY_DOWN else -1
				clear_index = (clear_index + dir + CLEAR_OPTIONS.size()) % CLEAR_OPTIONS.size()
				AudioManager.play_sfx("ui_select")
				queue_redraw()
		Mode.GAME_TITLE:
			# 有效街機輸入（↑↓←→／A／B）與投幣（Y／手柄 View）重設 10 秒待機
			# 計時；其他鍵不重設（字母／空白等照舊進起名流程）。NORMAL 時這些鍵
			# 也會照常觸發起名／長按判定 —— 只有 IDLE 喚醒那一次輸入會被攔截。
			if (key != null and key.keycode in TITLE_IDLE_WAKE_KEYS) \
					or _is_arcade_a(event) or _is_arcade_b(event) or _is_coin_insert(event):
				_idle_timer.start()
			# Y／手柄 View ＝投幣：吃掉事件，不觸發起名（幣量 +1＋coin_push 音效）。
			if _is_coin_insert(event):
				_insert_coin()
			# 任意鍵 → 起名開局（閘門見 _launch）。A／B 例外：按下後先等長按
			# 判定（_process 裡兩顆一起按住 3 秒 → 管理員密碼界面；提前鬆開 →
			# 放開分支當普通按鍵進起名 —— 一樣要過 _launch 的投幣閘門）。
			elif _is_arcade_a(event) or _is_arcade_b(event):
				_ab_hold_active = true
				_ab_hold_time = 0.0
			else:
				_ab_hold_active = false    # 清掉可能的長按等待，防 keyup 誤觸發
				_ab_hold_time = 0.0
				_launch(active_index)
		Mode.PLAYING:
			if key != null and key.keycode == KEY_ESCAPE:
				_close_game()


## 街機 A／B 的按下判斷（鍵盤 A·S／手柄 A·B 共用，見 shared/arcade_input.gd）。
func _is_arcade_a(event: InputEvent) -> bool:
	return ArcadeInput.pressed(event, ArcadeInput.ACTION_A)


func _is_arcade_b(event: InputEvent) -> bool:
	return ArcadeInput.pressed(event, ArcadeInput.ACTION_B)


## 待機喚醒認定的有效輸入：方向鍵（鍵盤）＋街機 A／B（鍵盤 A·S／手柄 A·B）。
func _is_wake_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null and key.keycode in TITLE_IDLE_WAKE_KEYS:
		return true
	return _is_arcade_a(event) or _is_arcade_b(event)


## 手柄左搖杆的垂直推量 → 管理員界面（一級清單／SETTING 二三級）的上下
## 選擇，與鍵盤 ↑↓ 同一組移動與音效。死區 ±0.5（與起名屏的搖桿判定同一
## 檔）：過死區算「推住」，邊沿觸發只動一次、回到中立區重置後才允許下一
## 次 —— 推住不連發，與鍵盤方向鍵不吃 echo 一致。
func _pad_stick_nav(value: float) -> void:
	var dir := 0
	if value >= 0.5:
		dir = 1          # 推下（搖桿 Y 軸向下為正）
	elif value <= -0.5:
		dir = -1         # 推上
	if dir == _stick_nav_dir:
		return
	_stick_nav_dir = dir
	if dir == 0:
		return           # 回中立只重置狀態，不動選擇
	match mode:
		Mode.MENU:
			selected_game = (selected_game + dir + GAMES.size() + 1) % (GAMES.size() + 1)
		Mode.SETTING:
			setting_index = (setting_index + dir + SETTING_OPTIONS.size()) % SETTING_OPTIONS.size()
		Mode.SETTING_CLEAR:
			clear_index = (clear_index + dir + CLEAR_OPTIONS.size()) % CLEAR_OPTIONS.size()
		_:
			return
	AudioManager.play_sfx("ui_select")   # 選單移動
	queue_redraw()


## 一級標題按 A 確認 → 二級標題。未建置的款項留在原地跳提示。
func _enter_game_title(index: int) -> void:
	if not _built[index]:
		_show_notice("%s NOT BUILT YET" % GAMES[index]["title"], Palette.WARN)
		return
	active_index = index
	_ab_hold_active = false
	_ab_hold_time = 0.0
	_stick_nav_dir = 0
	mode = Mode.GAME_TITLE
	_begin_title_idle_watch()   # 進二級：開始 10 秒無操作計時
	queue_redraw()


func _launch(index: int) -> void:
	var entry: Dictionary = GAMES[index]
	if not _built[index]:
		_show_notice("%s NOT BUILT YET" % entry["title"], Palette.WARN)
		return

	# 投幣閘門（規格：先擋幣再進起名）：無限投幣 ON 直接放行且不扣幣；
	# OFF 時餘額夠 START_COST 才扣一枚放行。不夠 → Coin 圖抖動＋
	# UI_Coin_None，留在二級標題、不進起名。閘門排在 NOT BUILT 之後，
	# 沒建置的款項不會白吃玩家一枚幣。
	if not CoinManager.consume_coin():
		_start_coin_shake()
		return
	AudioManager.play_sfx("ui_confirm")   # 只有成功進入起名／開局才播
	_leave_title_idle()         # 離開二級標題：待機計時與影片全部停掉

	if not CurrentPlayerSession.is_active():
		# 第一次進遊戲：先輸入名字，輸入成功才真正開局
		active_index = index
		_open_name_input()
		return
	_start_game(index)


# ── 投幣（二級標題 Y；InputMap action「coin_insert」＝鍵盤 Y＋手柄 View）──

## 這顆輸入事件是不是「投幣」（鍵盤 Y／手柄 View/Back）。action 被人從
## project.godot 的 [input] 拿掉時安全回 false，不讓 is_action_pressed 刷錯誤。
func _is_coin_insert(event: InputEvent) -> bool:
	return ArcadeInput.pressed(event, ArcadeInput.ACTION_COIN)


## Y／手柄 View 投一枚幣：幣量 +1、刷新左下角顯示、播 coin_push。無限投幣 ON 也
## 照常累計與播音（實體投幣的聲音，規格允許；ON/OFF 只影響開局扣不扣）。
## 不設投幣上限。
func _insert_coin() -> void:
	CoinManager.add_coin()
	AudioManager.play_sfx("coin_push")
	queue_redraw()


## 幣不夠被 _launch 擋下：Coin 圖抖 COIN_SHAKE_SECONDS 秒＋UI_Coin_None。
## 抖動結束自動恢復正常（_process 倒數歸零，偏移在 _draw 同步回 0）。
func _start_coin_shake() -> void:
	_coin_shake_time = COIN_SHAKE_SECONDS
	AudioManager.play_sfx("ui_coin_none")
	queue_redraw()


# ── SETTING 二級選單的 MUSIC 開關（只控制 BGM，音效不受影響）────

## 切換 MUSIC：狀態寫回 Settings（user://settings.cfg，跨執行保存），
## 再叫 AudioManager.apply_music_setting() 讓當下立刻生效 —— 關閉 → 停掉
## 正在播的 BGM；打開 → 接續播回當前場合的 BGM（各處 play_bgm 調用點
## 不用改，AudioManager 內部自己檢查開關）。
func _toggle_music() -> void:
	Settings.set_music_on(not Settings.is_music_on())
	AudioManager.apply_music_setting()


## 標題層的短提示（NOT BUILT／載入失敗／清除成功），停留 NOTICE_TIME 秒。
func _show_notice(text: String, col: Color) -> void:
	_notice = text
	_notice_col = col
	_notice_timer = NOTICE_TIME
	queue_redraw()


func _start_game(index: int) -> void:
	var entry: Dictionary = GAMES[index]
	var script: Script = load(entry["script"])
	if script == null:
		_show_notice("%s FAILED TO LOAD" % entry["title"], Palette.WARN)
		mode = Mode.MENU
		queue_redraw()
		return

	active_index = index
	var node := Node2D.new()
	node.name = "Game"
	node.set_script(script)
	game = node
	add_child(node)        # 這一行才會觸發遊戲的 _ready()
	if node.has_signal("round_finished"):
		node.connect("round_finished", Callable(self, "_on_round_finished"))
	mode = Mode.PLAYING
	_title_video.stop()    # 遊戲畫面接管整個螢幕，背景影片停掉
	AudioManager.play_bgm(entry["bgm"])   # 開局切到該款的 BGM
	queue_redraw()


# ── 局終：提交成績 → Game Over 界面 ─────────────────────

func _on_round_finished(score: int, duration: float, game_over: bool) -> void:
	var entry: Dictionary = GAMES[active_index]

	var record := LeaderboardRecord.new()
	record.game_id = entry["id"]
	record.game_name = entry["title"]
	record.player_name = CurrentPlayerSession.player_name
	record.score = score
	record.duration_seconds = duration

	_finish_data = {
		"record_id": LeaderboardManager.submit_score(record),
		"score": score,
		"game_over": game_over,
	}
	# 推遲到這幀結束再切換：不能在發射者的 signal 回呼裡把它移出場景樹
	_open_game_over.call_deferred()


## 局終開 Game Over 動畫：**背景保留遊戲場景** —— 遊戲節點暫停不釋放
## （process_mode = DISABLED 停整棵子樹，畫面定格在最後一幀），文字
## 淡入淡出播完**自動**進排行榜面板，沒有按鈕、不吃按鍵（見 ui/game_over.gd）。
## 遊戲節點等 _on_game_over_leaderboard 開面板前才釋放。
func _open_game_over() -> void:
	if mode != Mode.PLAYING:
		return                # 保險：局終後緊接著的 ESC 之類的路徑，避免重複開
	if game != null:
		game.process_mode = Node.PROCESS_MODE_DISABLED   # 定格遊戲畫面當背景

	var panel := Node2D.new()
	panel.name = "GameOver"
	panel.set_script(load("res://ui/game_over.gd"))
	# 面板的欄位要用 set() 設定：panel 是 Node2D 型別，編譯器看不到腳本屬性
	panel.set("game_over", _finish_data["game_over"])
	panel.connect("leaderboard_requested", Callable(self, "_on_game_over_leaderboard"))
	_panel = panel
	add_child(panel)
	mode = Mode.GAME_OVER
	queue_redraw()


## Game Over 動畫播完：釋放遊戲節點、關動畫界面、開排行榜面板。
func _on_game_over_leaderboard() -> void:
	_free_game_node()
	_close_panel()
	_open_leaderboard()


## 排行榜面板的 B/ESC：清名字回**該款的二級標題**
## （不回一級），下次起名重新輸入。排行歷史由 LeaderboardManager 保管，
## 與玩家名字生命週期無關。
func _on_panel_exit() -> void:
	_close_panel()
	CurrentPlayerSession.clear()
	_ab_hold_active = false
	_ab_hold_time = 0.0
	mode = Mode.GAME_TITLE
	_begin_title_idle_watch()   # 回二級：重新開始 10 秒無操作計時
	queue_redraw()


# ── 排行榜面板（Game Over 動畫播完自動進入）────

## 開排行榜面板：大標題 YOUR SCORE ＋ 前 10 名單欄 ＋ 底部當前玩家行，
## B/ESC 回該款二級標題。當前玩家的成績（名字／分數／record_id）由
## launcher 傳入，排名在面板內用 record_id 查。
## 清除功能已移到一級標題的清除選單（見 _open_clear_menu），面板一律只讀。
func _open_leaderboard() -> void:
	var entry: Dictionary = GAMES[active_index]
	var panel := Node2D.new()
	panel.name = "LeaderboardPanel"
	panel.set_script(load("res://ui/leaderboard_panel.gd"))
	# 面板的欄位要用 set() 設定：panel 是 Node2D 型別，編譯器看不到腳本屬性
	panel.set("game_id", entry["id"])
	panel.set("player_name", CurrentPlayerSession.player_name)
	panel.set("score", _finish_data["score"])
	panel.set("record_id", _finish_data["record_id"])
	panel.connect("exit_requested", Callable(self, "_on_panel_exit"))
	_panel = panel
	add_child(panel)
	mode = Mode.LEADERBOARD
	queue_redraw()


# ── 管理員排行榜清除選單（一級標題按 B，Modal Overlay）────

## 一級標題按 B：開「當前選中遊戲」的排行榜清除選單。選單自己跟
## LeaderboardManager 要資料與執行刪除，launcher 只負責開關與提示。
func _open_clear_menu() -> void:
	if _clear_modal != null:
		return
	var modal := Node2D.new()
	modal.name = "AdminClearMenu"
	modal.set_script(load("res://ui/admin_clear_menu.gd"))
	modal.set("game_id", GAMES[selected_game]["id"])
	modal.set("game_name", GAMES[selected_game]["menu_name"])
	modal.connect("cleared", Callable(self, "_on_clear_done"))
	modal.connect("cancelled", Callable(self, "_on_clear_cancelled"))
	_clear_modal = modal
	add_child(modal)


## 清除完成：關選單、留在一級標題，顯示成功提示。
## （選單開著時標題層不收任何鍵，selected_game 不會被切動 ——
## 清的一定是開選單時選中的那一款。）
func _on_clear_done() -> void:
	_close_clear_modal()
	_show_notice("%s SCORE DATA CLEARED" % GAMES[selected_game]["menu_name"], Palette.GOLD)


## B/ESC 取消：關選單，留在一級標題，什麼都不做。
func _on_clear_cancelled() -> void:
	_close_clear_modal()


func _close_clear_modal() -> void:
	if _clear_modal == null:
		return
	remove_child(_clear_modal)
	_clear_modal.queue_free()
	_clear_modal = null


# ── 姓名輸入 ────────────────────────────────────────────

func _open_name_input() -> void:
	var entry: Dictionary = GAMES[active_index]
	var ni := Node2D.new()
	ni.name = "NameInput"
	ni.set_script(load("res://ui/name_input.gd"))
	ni.set("title_image", entry["naming_image"])
	ni.set("game_id", entry["id"])
	ni.connect("confirmed", Callable(self, "_on_name_confirmed"))
	ni.connect("cancelled", Callable(self, "_on_name_cancelled"))
	_name_input = ni
	add_child(ni)
	mode = Mode.NAME_INPUT
	queue_redraw()


func _on_name_confirmed(name: String) -> void:
	_close_name_input()
	CurrentPlayerSession.set_player(name)
	_start_game(active_index)


func _on_name_cancelled() -> void:
	_close_name_input()
	_ab_hold_active = false
	_ab_hold_time = 0.0
	mode = Mode.GAME_TITLE      # 取消起名 → 回二級標題（不是一級）
	_begin_title_idle_watch()   # 回二級：重新開始 10 秒無操作計時
	queue_redraw()


# ── F3 管理員密碼彈窗（Modal Overlay，不是主流程狀態）──

func _open_password_modal() -> void:
	if _password_modal != null:
		return
	_leave_title_idle()         # 密碼彈窗開著不算二級標題正常畫面，先停待機
	var modal := Node2D.new()
	modal.name = "AdminPassword"
	modal.set_script(load("res://ui/admin_password.gd"))
	modal.connect("succeeded", Callable(self, "_on_password_succeeded"))
	modal.connect("cancelled", Callable(self, "_on_password_cancelled"))
	_password_modal = modal
	add_child(modal)


## 密碼正確：關彈窗 → 回一級標題，選擇狀態清掉（active_index 會在下次
## 按 1/2/3 時重設，這裡只管畫面與模式）。session 不動 —— 還沒開始玩。
func _on_password_succeeded() -> void:
	_close_password_modal()
	_title_video.stop()    # 回一級：二級標題背景影片不再需要
	_stick_nav_dir = 0     # 離開管理員流程：搖桿邊沿狀態重置
	mode = Mode.MENU
	queue_redraw()


## ESC 取消：關彈窗，留在原二級標題。
func _on_password_cancelled() -> void:
	_close_password_modal()
	_begin_title_idle_watch()   # 取消 → 留在二級，重新開始 10 秒無操作計時


func _close_password_modal() -> void:
	if _password_modal == null:
		return
	remove_child(_password_modal)
	_password_modal.queue_free()
	_password_modal = null


# ── 二級標題背景影片 ＋ 待機（IDLE：10 秒無操作 → 全屏待機影片；有效輸入喚醒）────

## 開始播放該款二級標題的背景影片（NORMAL 與起名 overlay 共用同一顆）。
## 素材沒進場（load 回 null）時不報錯 —— _draw 退回標題圖墊底。
func _start_title_video() -> void:
	if active_index < 0 or active_index >= GAMES.size():
		return
	if not _title_stream_cache.has(active_index):
		_title_stream_cache[active_index] = load(GAMES[active_index]["title_video"])
	var stream: VideoStream = _title_stream_cache[active_index]
	if stream == null:
		return
	if _title_video.stream != stream:
		_title_video.stream = stream
	_title_video.stream_position = 0.0
	_title_video.play()


## 進二級標題（NORMAL）：停掉待機影片、啟動背景影片、重開 10 秒無操作計時。
## 進入二級標題的所有路徑（一級按 A／局終回二級／起名取消／遊戲中 ESC）都
## 從這裡經過，所以標題 BGM 也在此切換；已在同一首時 AudioManager 自動略過。
## 標題 BGM 循環播放（二級停留時間不定，不能放完就停）。
func _begin_title_idle_watch() -> void:
	_title_idle = false
	_idle_video.stop()
	_idle_timer.start()
	_start_prompt_elapsed = 0.0
	AudioManager.play_bgm("TITLE", true)
	_start_title_video()


## 離開二級標題：待機計時與待機影片停掉（起名／開局／密碼彈窗時用）。
## 背景影片故意不停 —— 起名 overlay 與密碼彈窗底下都要透出它，真正離開
## 二級（開局／回一級）時由 _start_game／_on_password_succeeded 停。
func _leave_title_idle() -> void:
	_title_idle = false
	_idle_video.stop()
	_idle_timer.stop()


## 10 秒無有效輸入 → 進 IDLE：隱藏背景影片／文字、全屏播放該款待機影片。
## 影片載入失敗（素材還沒進場）時照樣進 IDLE —— 畫面停在標題圖，
## 輸入行為與有影片時一致，素材到位後自動生效。
func _enter_title_idle() -> void:
	if mode != Mode.GAME_TITLE or _title_idle:
		return
	if _password_modal != null or _clear_modal != null:
		return                # 彈窗開著不進待機（保險，正常流程不會走到）
	_title_idle = true
	_title_video.stop()       # 待機影片接管背景
	_ab_hold_active = false   # 清掉長按等待：進待機前的 A／B 按住不算數
	_ab_hold_time = 0.0
	_idle_prompt_elapsed = 0.0
	var idx := active_index
	if not _idle_stream_cache.has(idx):
		_idle_stream_cache[idx] = load(GAMES[idx]["idle_video"])
	var stream: VideoStream = _idle_stream_cache[idx]
	if stream != null:
		_idle_video.stream = stream
		_idle_video.stream_position = 0.0
		_idle_video.play()
	queue_redraw()


## IDLE → 玩家第一個有效輸入（↑↓←→／A／B）：停待機影片、恢復背景影片、
## 重開 10 秒計時。這次輸入只負責喚醒 —— 呼叫端已 return，
## 不會繼續觸發二級標題原本的操作。
func _wake_from_title_idle() -> void:
	_title_idle = false
	_idle_video.stop()
	_ab_hold_active = false
	_ab_hold_time = 0.0
	_idle_timer.start()
	_start_prompt_elapsed = 0.0
	_start_title_video()
	queue_redraw()


## 待機計時到 → 進 IDLE（彈窗開著或已離開二級標題時不動作）。
func _on_idle_timer_timeout() -> void:
	if mode != Mode.GAME_TITLE or _password_modal != null or _clear_modal != null:
		return
	_enter_title_idle()


## 影片播完的保險：loop 正常時不會走到（finished 只在無縫循環失效時發）。
func _on_idle_video_finished() -> void:
	if _title_idle:
		_idle_video.stream_position = 0.0
		_idle_video.play()


## 背景影片播完的保險（與待機影片同款，loop 正常時不會走到）。
func _on_title_video_finished() -> void:
	if (mode == Mode.GAME_TITLE and not _title_idle) or mode == Mode.NAME_INPUT:
		_title_video.stream_position = 0.0
		_title_video.play()


# ── 節點清理 ────────────────────────────────────────────

## 只釋放遊戲節點（局終接面板用，不動 session）。
func _free_game_node() -> void:
	if game == null:
		return
	# 先脫離場景樹再排程釋放，否則 queue_free() 生效前它還會多跑一幀 _process/_draw
	remove_child(game)
	game.queue_free()
	game = null


## ESC 中離 = 退出：釋放節點、清名字，回**該款的二級標題**（與局末面板 ESC 一致）。
func _close_game() -> void:
	_free_game_node()
	CurrentPlayerSession.clear()
	_notice = ""
	_notice_timer = 0.0
	_ab_hold_active = false
	_ab_hold_time = 0.0
	mode = Mode.GAME_TITLE
	_begin_title_idle_watch()   # 回二級：重新開始 10 秒無操作計時
	queue_redraw()


func _close_panel() -> void:
	if _panel == null:
		return
	remove_child(_panel)
	_panel.queue_free()
	_panel = null


func _close_name_input() -> void:
	if _name_input == null:
		return
	remove_child(_name_input)
	_name_input.queue_free()
	_name_input = null


# ── 繪製 ────────────────────────────────────────────────

func _draw() -> void:
	# 標題層：一級 = Title_ChooseGames 全屏圖，二級 = 該款的全屏背景影片
	# （未進場時退標題圖）。不疊任何文字/按鈕（需求文件第四/六節）；將來
	# 的標題動畫、Y2K 元素都在這兩個分支底下繼續加。
	# 圖都是 ~16:9（1920×1080 或 1672×941），拉到 480×270 變形可忽略。
	if mode == Mode.MENU:
		draw_texture_rect(TITLE_MAIN_IMAGE, Rect2(0, 0, 480, 270), false)
		# 一級標題的遊戲選擇清單（管理員用）：名字
		_draw_game_menu()
		#_center("↑ ↓ SELECT    A START    B CLEAR", 250, 12, Palette.BG)
	elif mode == Mode.SETTING or mode == Mode.SETTING_CLEAR:
		# SETTING 二級／清除三級：同一張一級圖墊底，一級清單文字整個不畫
		draw_texture_rect(TITLE_MAIN_IMAGE, Rect2(0, 0, 480, 270), false)
		if mode == Mode.SETTING:
			_draw_setting_menu()
		else:
			_draw_clear_menu()
	elif (mode == Mode.GAME_TITLE or mode == Mode.NAME_INPUT) and active_index >= 0:
		# 二級標題背景同時是起名 overlay 的底層：NAME_INPUT 時底下要透得出它。
		# 二級標題沒有任何按鈕 —— 按任意鍵即起名開局，底部有一行閃爍的
		# PRESS ANY BUTTON TO START 提示（起名 overlay 與待機畫面不畫）。
		# IDLE：不畫背景影片與提示（等同隱藏全部 UI/文字）。待機影片**等比例
		# 縮放置中**（維持自身長寬比，多餘的邊用底色補，不拉伸變形）；影片
		# 載入失敗時退回標題圖墊底。中央閃爍 CLICK TO PLAY 兩種情況都畫。
		if mode == Mode.GAME_TITLE and _title_idle:
			var video_texture: Texture2D = null
			if _idle_video.stream != null:
				video_texture = _idle_video.get_video_texture()
			if video_texture != null and video_texture.get_size().x > 0.0:
				var vw := video_texture.get_size().x
				var vh := video_texture.get_size().y
				var scale := minf(480.0 / vw, 270.0 / vh)
				var w := vw * scale
				var h := vh * scale
				draw_rect(Rect2(0, 0, 480, 270), Palette.BG, true)   # 留邊底色
				draw_texture_rect(video_texture,
					Rect2((480.0 - w) / 2.0, (270.0 - h) / 2.0, w, h), false)
			else:
				var image: Texture2D = GAMES[active_index]["title_image"]
				draw_texture_rect(image, Rect2(0, 0, 480, 270), false)
			_draw_idle_prompt()
			return
		_draw_title_background()
		if mode == Mode.GAME_TITLE:
			_draw_start_prompt()
			_draw_coin_ui()   # 左下角投幣顯示（只掛在二級標題 NORMAL）
	else:
		return              # 遊戲／面板／輸入屏自己會把整個畫面畫滿

	# 提示（NOT BUILT / 載入失敗 / 清除成功）直接疊在圖上，極少出現
	if _notice != "":
		_center(_notice, 256, 10, _notice_col)


## 一級標題的遊戲選擇清單：區域內垂直排列三款遊戲名（MAZE / FISHING / CATCH）
## ＋最下方一行 SETTING。選中那行畫 MENU_SELECTED（#FFC4FF）、其餘畫
## MENU_IDLE（#FF44FF）；SETTING 行是管理員入口。
func _draw_game_menu() -> void:
	var font := ThemeDB.fallback_font
	var name_x := MENU_REGION_POS.x + 8.0
	var y := MENU_REGION_POS.y + (MENU_REGION_SIZE.y - MENU_LINE_H * (GAMES.size() + 1)) / 2.0
	for i in GAMES.size():
		var selected := i == selected_game
		var col := MENU_SELECTED if selected else MENU_IDLE
		var name: String = GAMES[i]["menu_name"]
		draw_string(font, Vector2(name_x, y), name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, MENU_NAME_SIZE, col)
		y += MENU_LINE_H
	var sel_setting := selected_game >= GAMES.size()
	draw_string(font, Vector2(name_x, y), "SETTING",
		HORIZONTAL_ALIGNMENT_LEFT, -1, MENU_NAME_SIZE,
		MENU_SELECTED if sel_setting else MENU_IDLE)


## SETTING 二級選單（CLEAR LEADERBOARD / UNLIMITED COINS / MUSIC）：同一塊
## 管理員區域內垂直排列，選中／未選中顏色與一級清單相同。開關型選項
## （UNLIMITED COINS／MUSIC）行右側緊接名字顯示 ON/OFF 狀態
## （用量到的名字寬度推過去）。底部一行操作提示在區域內。
func _draw_setting_menu() -> void:
	var font := ThemeDB.fallback_font
	var name_x := MENU_REGION_POS.x + 8.0
	var y := MENU_REGION_POS.y + (MENU_REGION_SIZE.y - MENU_LINE_H * SETTING_OPTIONS.size()) / 2.0
	for i in SETTING_OPTIONS.size():
		var selected := i == setting_index
		var col := MENU_SELECTED if selected else MENU_IDLE
		var name: String = SETTING_OPTIONS[i]
		draw_string(font, Vector2(name_x, y), name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, MENU_SUB_SIZE, col)
		var status := _setting_status(i)
		if status != "":
			var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, MENU_SUB_SIZE).x
			draw_string(font, Vector2(name_x + w + 8.0, y), status,
				HORIZONTAL_ALIGNMENT_LEFT, -1, MENU_SUB_SIZE, col)
		y += MENU_LINE_H
	_center_in_region("A CONFIRM    B BACK",
		MENU_REGION_POS.y + MENU_REGION_SIZE.y - 20.0, 8, Palette.TEXT_DIM)


## 開關型 SETTING 選項右側的 ON/OFF 狀態文字；非開關選項回空字串（不畫）。
func _setting_status(index: int) -> String:
	if index == SETTING_COINS_IDX:
		return "ON" if Settings.is_unlimited_coins() else "OFF"
	if index == SETTING_MUSIC_IDX:
		return "ON" if Settings.is_music_on() else "OFF"
	return ""


## 三級排行榜清除選單（CLEAR TODAY / CLEAR LAST 24 HOURS / CLEAR ALL DATA）：
## 執行時**跨三款遊戲一起清**（LeaderboardManager.clear_all_games_records），
## 不需要也不能選遊戲。選中／未選中顏色與上層相同。
func _draw_clear_menu() -> void:
	var font := ThemeDB.fallback_font
	var name_x := MENU_REGION_POS.x + 8.0
	var y := MENU_REGION_POS.y + (MENU_REGION_SIZE.y - MENU_LINE_H * CLEAR_OPTIONS.size()) / 2.0
	for i in CLEAR_OPTIONS.size():
		var selected := i == clear_index
		draw_string(font, Vector2(name_x, y), CLEAR_OPTIONS[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, MENU_SUB_SIZE,
			MENU_SELECTED if selected else MENU_IDLE)
		y += MENU_LINE_H
	_center_in_region("A CLEAR    B BACK",
		MENU_REGION_POS.y + MENU_REGION_SIZE.y - 20.0, 8, Palette.TEXT_DIM)


## 在管理員選單區域內水平置中的一行文字（區域寬度為置中基準）。
func _center_in_region(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(MENU_REGION_POS.x, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, MENU_REGION_SIZE.x, size, col)


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, 480, size, col)


## 二級標題（NORMAL）與起名 overlay 的底層背景：該款的全屏影片**等比例縮放
## 置中**（480×270 是 16:9，16:9 素材會正好鋪滿；非 16:9 素材多餘的邊用
## 底色補，不拉伸變形）。影片載入失敗（素材沒進場）時退回標題圖墊底。
func _draw_title_background() -> void:
	var video_texture: Texture2D = null
	if _title_video.stream != null:
		video_texture = _title_video.get_video_texture()
	if video_texture != null and video_texture.get_size().x > 0.0:
		var vw := video_texture.get_size().x
		var vh := video_texture.get_size().y
		var scale := minf(480.0 / vw, 270.0 / vh)
		var w := vw * scale
		var h := vh * scale
		draw_rect(Rect2(0, 0, 480, 270), Palette.BG, true)   # 留邊底色
		draw_texture_rect(video_texture,
			Rect2((480.0 - w) / 2.0, (270.0 - h) / 2.0, w, h), false)
	else:
		var image: Texture2D = GAMES[active_index]["title_image"]
		draw_texture_rect(image, Rect2(0, 0, 480, 270), false)


## 二級標題底部中央閃爍的 PRESS ANY BUTTON TO START（週期 START_PROMPT_PERIOD
## 秒、每週期亮 START_PROMPT_ON_SECONDS 秒，與待機的 CLICK TO PLAY 同款）。
## 文字與底影照當前款式取 TITLE_TEXT_COLORS 的配色，讓亮色影片上也能看清。
## 只由 _draw 的 GAME_TITLE 分支呼叫，閃爍相位在 _process 累計。
func _draw_start_prompt() -> void:
	if fmod(_start_prompt_elapsed, START_PROMPT_PERIOD) >= START_PROMPT_ON_SECONDS:
		return
	var font := ThemeDB.fallback_font
	var colors := _title_text_colors()
	var y := 245.0
	draw_string(font, Vector2(0, y + 1.0), "PRESS ANY BUTTON TO START",
		HORIZONTAL_ALIGNMENT_CENTER, 480, 10, colors["shadow"])
	draw_string(font, Vector2(-1, y), "PRESS ANY BUTTON TO START",
		HORIZONTAL_ALIGNMENT_CENTER, 480, 10, colors["text"])


## 當前款式的標題文字配色：text 是主色、shadow 是底影。id 沒登記時退回
## 原本的金字／深影（防禦，目前三款都有登記）。
func _title_text_colors() -> Dictionary:
	var fallback := {"text": Palette.GOLD, "shadow": Palette.NIGHT}
	if active_index < 0 or active_index >= GAMES.size():
		return fallback
	return TITLE_TEXT_COLORS.get(GAMES[active_index]["id"], fallback)


## 待機畫面中央閃爍的 CLICK TO PLAY（週期 IDLE_PROMPT_PERIOD 秒、每週期亮
## IDLE_PROMPT_ON_SECONDS 秒）。深色底影讓亮色影片上也能看清。只由 _draw
## 的 IDLE 分支呼叫，閃爍相位在 _process 累計。
func _draw_idle_prompt() -> void:
	if fmod(_idle_prompt_elapsed, IDLE_PROMPT_PERIOD) >= IDLE_PROMPT_ON_SECONDS:
		return
	var font := ThemeDB.fallback_font
	var y := 139.0
	draw_string(font, Vector2(0, y + 1.0), "CLICK TO PLAY",
		HORIZONTAL_ALIGNMENT_CENTER, 480, 10, Palette.NIGHT)
	draw_string(font, Vector2(0, y), "CLICK TO PLAY",
		HORIZONTAL_ALIGNMENT_CENTER, 480, 10, Palette.GOLD)


## 二級標題左下角的投幣顯示：Coin 圖（12×12，1920×1080 設計 48×48）＋
## 右側狀態文字 —— 無限投幣 ON 顯示「∞」、OFF 顯示「餘額/需求」（如 0/1，
## 需求 = CoinManager.START_COST）。文字底影與 PRESS ANY BUTTON 同款雙層
## 畫法，亮色影片上也看得清。幣不夠被擋下時整組水平抖動（位移只在繪製
## 層，見 _coin_shake_offset）。只由 _draw 的 GAME_TITLE NORMAL 分支呼叫
## （IDLE 待機與起名 overlay 不畫，待機畫面不該有 UI、起名時幣已扣完）。
func _draw_coin_ui() -> void:
	var shake := Vector2(_coin_shake_offset(), 0.0)
	if _coin_tex != null:
		draw_texture_rect(_coin_tex, Rect2(COIN_UI_POS + shake, COIN_UI_SIZE), false)
	var font := ThemeDB.fallback_font
	var text := "∞" if CoinManager.is_unlimited_coins() \
		else "%d/%d" % [CoinManager.get_coins(), CoinManager.START_COST]
	# 文字基線對齊圖示底緣（圖示 235..247，基線 245），尺寸 12 = 像素字體
	# 原生 12px 的整數倍，網格對得齊。
	var pos := Vector2(COIN_UI_POS.x + COIN_UI_SIZE.x + COIN_UI_TEXT_GAP,
		COIN_UI_POS.y + COIN_UI_SIZE.y - 2.0) + shake
	# 幣量文字跟 PRESS ANY BUTTON 同一套每款配色（2026-09 企劃指定）。
	var colors := _title_text_colors()
	draw_string(font, pos + Vector2(0.0, 1.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, colors["shadow"])
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, colors["text"])


## 幣不夠抖動的水平位移：振幅隨剩餘時間線性衰減的正弦，倒數到 0 時
## 正好回到 0，不會停在偏移上（位移只進 draw，不碰任何節點 position）。
func _coin_shake_offset() -> float:
	if _coin_shake_time <= 0.0:
		return 0.0
	return COIN_SHAKE_AMPLITUDE * (_coin_shake_time / COIN_SHAKE_SECONDS) \
		* sin(_coin_shake_time * 60.0)
