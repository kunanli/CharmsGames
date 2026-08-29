extends Node2D

# ─────────────────────────────────────────────────────────
# 啟動標題 + 遊戲流程狀態機：
#   MENU（一級標題＝管理員的遊戲選擇畫面：↑ ↓ 循環選遊戲／SETTING、
#     B 開當前選中遊戲的排行榜清除選單、A 確認）
#   → GAME_TITLE（二級標題＝該款全屏標題圖，無按鈕、無提示文字：
#     按**任意鍵** → 起名開局；A／B 例外 —— 兩個一起按住 3 秒 →
#     管理員密碼界面，提前鬆開＝普通按鍵 → 起名）
#   → NAME_INPUT → PLAYING
#   → GAME_OVER（局終結算界面）→ LEADERBOARD（排行榜）
#   一級標題選中 SETTING 按 A → SETTING（二級：CLEAR LEADERBOARD /
#     UNLIMITED COINS，A 執行、B 回一級）
#   → SETTING_CLEAR（三級：CLEAR TODAY / LAST 24 HOURS / ALL DATA，
#     跨三款一起清、A 執行、B 回 SETTING）
#
# 標題層只畫全屏圖（assets/title/）：一級畫 Title_ChooseGames＋遊戲選擇
# 清單（名字用 draw_string 疊在圖上），二級畫該款的標題圖。二級標題是
# 「固定場所」：不響應 1/2/3 與 ESC，**唯一回一級的路徑是管理員密碼界面**
# （ui/admin_password.gd，Modal Overlay，二級標題 A＋B 長按 3 秒進入）：
# 用方向鍵輸入「上上下下左右左右」共 8 位指令、按 A 確認 —— 正確 → 回一級、
# ESC → 留在二級。遊戲結束與遊戲中 ESC 都回**該款的二級標題**。
# 一級標題按 B 開**當前選中遊戲的排行榜清除選單**（ui/admin_clear_menu.gd，
# Modal Overlay，見「清除功能」段落）。
# 彈窗開著時本檔不處理任何按鍵（輸入分層見 _unhandled_key_input 註解）。
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
#   （ui/game_over.gd：GAME OVER ／分數／排名／玩家名字 ＋ RESTART／
#   LEADERBOARD 兩個按鈕，↑ ↓ 切換、A 執行）
#   Game Over 選 RESTART = 重開同一款（名字保留）；
#   選 LEADERBOARD = 開排行榜面板（只顯示前 10 名）；
#   B/ESC = 回該款二級標題（清名字）。
#   排行榜面板 B/ESC = 回該款二級標題（清名字，不保留玩家名稱）。
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
		"blurb": "MAZE CHASE",
		"script": "res://games/seeker/seeker.gd",
		"title_image": preload("res://assets/title/Title_Maze.jpg"),
		"naming_image": preload("res://assets/title/Naming/Name_Charmsseeker.png"),
	},
	{
		"id": "fishing",
		"title": "CHARMS FISHING",
		"menu_name": "FISHING",
		"blurb": "HOOK THE CHARMS",
		"script": "res://games/fishing/fishing.gd",
		"title_image": preload("res://assets/title/Title_Fishing.jpg"),
		"naming_image": preload("res://assets/title/Naming/Name_Charmsfishing.png"),
	},
	{
		"id": "catch",
		"title": "CHARMS CATCH",
		"menu_name": "CATCH",
		"blurb": "CATCH AND DODGE",
		"script": "res://games/catch/catch.gd",
		"title_image": preload("res://assets/title/Title_Catch.jpg"),
		"naming_image": preload("res://assets/title/Naming/Name_CharmsCatch.png"),
	},
]

## 一級標題全屏圖。三張二級標題圖掛在各 GAMES 條目的 title_image。
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

## SETTING 二級選單的兩個選項（索引即 setting_index）。
const SETTING_OPTIONS := ["CLEAR RANKING DATA", "UNLIMITED COINS"]
const SETTING_CLEAR_IDX := 0
const SETTING_COINS_IDX := 1

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
var selected_game := 0        # 一級標題當前選中的項目（0..GAMES.size()，size()＝SETTING）
var setting_index := 0        # SETTING 二級選單：0 = CLEAR LEADERBOARD、1 = UNLIMITED COINS
var clear_index := 0          # 三級清除選單：0 = CLEAR TODAY、1 = LAST 24 HOURS、2 = ALL


func _ready() -> void:
	# 用 ResourceLoader 而不是 FileAccess：匯出後 .gd 會被編譯進 pck 並重新對應，
	# FileAccess.file_exists() 在匯出版會一律回 false，選單就全變成 COMING SOON。
	for entry in GAMES:
		_built.append(ResourceLoader.exists(entry["script"]))
	queue_redraw()


func _process(delta: float) -> void:
	if _notice_timer > 0.0:
		_notice_timer -= delta
		if _notice_timer <= 0.0:
			_notice = ""
		queue_redraw()
	if mode == Mode.GAME_TITLE and _ab_hold_active:
		# 二級標題的管理員入口：A＋B 同時按住滿 AB_HOLD_SECONDS 秒 →
		# 管理員密碼界面（不到 3 秒鬆開的話，keyup 分支會當普通按鍵進起名）。
		if Input.is_key_pressed(KEY_A) and Input.is_key_pressed(KEY_B):
			_ab_hold_time += delta
			if _ab_hold_time >= AB_HOLD_SECONDS:
				_ab_hold_active = false
				_ab_hold_time = 0.0
				_open_password_modal()
		else:
			_ab_hold_time = 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo:
		return

	# keyup 只用於二級標題的 A／B 長按判定：兩個鍵沒按住滿 3 秒就鬆開
	# ＝普通按鍵，照樣進入起名流程（進入密碼界面後 _ab_hold_active 已清，
	# 鬆開不會誤觸發）。起名／遊戲等子節點會吃掉自己的事件，收不到這裡。
	if not key.pressed:
		if mode == Mode.GAME_TITLE and _ab_hold_active \
				and (key.keycode == KEY_A or key.keycode == KEY_B):
			_ab_hold_active = false
			_ab_hold_time = 0.0
			_launch(active_index)
		return

	# NAME_INPUT / LEADERBOARD 的按鍵由各自的子節點處理並吃掉事件，
	# launcher 不需要也不應該碰。
	#
	# 輸入分層：
	#   Level 1  密碼彈窗／清除選單開著 → 只剩彈窗自己的按鍵，這裡整段不處理
	#   Level 2  二級標題 → 按**任意鍵**進入起名流程（A／B 例外：先等長按
	#            判定 —— 兩個一起按住 3 秒進管理員密碼界面、提前鬆開＝普通
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
			match key.keycode:
				KEY_UP, KEY_DOWN:
					var dir := 1 if key.keycode == KEY_DOWN else -1
					selected_game = (selected_game + dir + GAMES.size() + 1) % (GAMES.size() + 1)
					queue_redraw()
				KEY_B:
					if selected_game < GAMES.size():
						_open_clear_menu()     # SETTING 行 B 無操作
				KEY_A:
					if selected_game >= GAMES.size():
						mode = Mode.SETTING     # SETTING → 二級選單
					else:
						_enter_game_title(selected_game)
					queue_redraw()
		Mode.SETTING:
			match key.keycode:
				KEY_UP, KEY_DOWN:
					setting_index = 1 - setting_index    # 兩個選項直接互換
					queue_redraw()
				KEY_A, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					if setting_index == SETTING_CLEAR_IDX:
						mode = Mode.SETTING_CLEAR        # 進三級清除選單
					else:
						Settings.set_unlimited_coins(not Settings.is_unlimited_coins())
					queue_redraw()
				KEY_B, KEY_ESCAPE:
					mode = Mode.MENU                     # 回一級，選擇狀態保留
					queue_redraw()
		Mode.SETTING_CLEAR:
			match key.keycode:
				KEY_UP, KEY_DOWN:
					var dir := 1 if key.keycode == KEY_DOWN else -1
					clear_index = (clear_index + dir + CLEAR_OPTIONS.size()) % CLEAR_OPTIONS.size()
					queue_redraw()
				KEY_A, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					LeaderboardManager.clear_all_games_records(CLEAR_RULES[clear_index])
					_show_notice("SCORE DATA CLEARED", Palette.GOLD)
					mode = Mode.SETTING                   # 執行完回二級，選項狀態保留
					queue_redraw()
				KEY_B, KEY_ESCAPE:
					mode = Mode.SETTING
					queue_redraw()
		Mode.GAME_TITLE:
			# 任意鍵 → 起名開局。A／B 例外：按下後先等長按判定（_process 裡
			# 兩個一起按住 3 秒 → 管理員密碼界面；提前鬆開 → keyup 分支
			# 當普通按鍵進起名）。
			if key.keycode == KEY_A or key.keycode == KEY_B:
				_ab_hold_active = true
				_ab_hold_time = 0.0
			else:
				_ab_hold_active = false    # 清掉可能的長按等待，防 keyup 誤觸發
				_ab_hold_time = 0.0
				_launch(active_index)
		Mode.PLAYING:
			if key.keycode == KEY_ESCAPE:
				_close_game()


## 一級標題按 A 確認 → 二級標題。未建置的款項留在原地跳提示。
func _enter_game_title(index: int) -> void:
	if not _built[index]:
		_show_notice("%s NOT BUILT YET" % GAMES[index]["title"], Palette.WARN)
		return
	active_index = index
	_ab_hold_active = false
	_ab_hold_time = 0.0
	mode = Mode.GAME_TITLE
	queue_redraw()


func _launch(index: int) -> void:
	var entry: Dictionary = GAMES[index]

	if not _built[index]:
		_show_notice("%s NOT BUILT YET" % entry["title"], Palette.WARN)
		return

	if not CurrentPlayerSession.is_active():
		# 第一次進遊戲：先輸入名字，輸入成功才真正開局
		active_index = index
		_open_name_input()
		return
	_start_game(index)


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


## 局終開 Game Over 界面（取代舊的「局終直接進排行榜面板」）。
## 界面顯示 GAME OVER／TIME UP、分數、排名、玩家名字，並提供
## RESTART／LEADERBOARD 兩個按鈕（↑ ↓ 切換、A 執行，見 ui/game_over.gd）。
func _open_game_over() -> void:
	if mode != Mode.PLAYING:
		return                # 保險：局終後緊接著的 ESC 之類的路徑，避免重複開
	_free_game_node()        # 只釋放節點，不動 session —— 界面還要顯示名字

	var entry: Dictionary = GAMES[active_index]
	var panel := Node2D.new()
	panel.name = "GameOver"
	panel.set_script(load("res://ui/game_over.gd"))
	# 面板的欄位要用 set() 設定：panel 是 Node2D 型別，編譯器看不到腳本屬性
	panel.set("title_image", entry["title_image"])
	panel.set("player_name", CurrentPlayerSession.player_name)
	panel.set("score", _finish_data["score"])
	panel.set("game_over", _finish_data["game_over"])
	panel.set("record_id", _finish_data["record_id"])
	panel.connect("restart_requested", Callable(self, "_on_panel_restart"))
	panel.connect("leaderboard_requested", Callable(self, "_on_game_over_leaderboard"))
	panel.connect("exit_requested", Callable(self, "_on_panel_exit"))
	_panel = panel
	add_child(panel)
	mode = Mode.GAME_OVER
	queue_redraw()


## Game Over 界面選 LEADERBOARD：關界面、開排行榜面板。
func _on_game_over_leaderboard() -> void:
	_close_panel()
	_open_leaderboard()


func _on_panel_restart() -> void:
	# 重新開始：名字保留，直接重開同一款（下一局結束會再提交一條新記錄）
	_close_panel()
	_start_game(active_index)


## 排行榜面板／Game Over 界面的 B/ESC：清名字回**該款的二級標題**
## （不回一級），下次 Space 重新起名。排行歷史由 LeaderboardManager 保管，
## 與玩家名字生命週期無關。
func _on_panel_exit() -> void:
	_close_panel()
	CurrentPlayerSession.clear()
	_ab_hold_active = false
	_ab_hold_time = 0.0
	mode = Mode.GAME_TITLE
	queue_redraw()


# ── 排行榜面板（Game Over 界面進入）────

## 開排行榜面板（Game Over 界面選 LEADERBOARD 進入）：只顯示前 10 名、
## 不顯示本局成績，B/ESC 回該款二級標題。
## 清除功能已移到一級標題的清除選單（見 _open_clear_menu），面板一律只讀。
func _open_leaderboard() -> void:
	var entry: Dictionary = GAMES[active_index]
	var panel := Node2D.new()
	panel.name = "LeaderboardPanel"
	panel.set_script(load("res://ui/leaderboard_panel.gd"))
	# 面板的欄位要用 set() 設定：panel 是 Node2D 型別，編譯器看不到腳本屬性
	panel.set("game_id", entry["id"])
	panel.set("game_name", entry["title"])
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
	queue_redraw()


# ── F3 管理員密碼彈窗（Modal Overlay，不是主流程狀態）──

func _open_password_modal() -> void:
	if _password_modal != null:
		return
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
	mode = Mode.MENU
	queue_redraw()


## ESC 取消：關彈窗，留在原二級標題。
func _on_password_cancelled() -> void:
	_close_password_modal()


func _close_password_modal() -> void:
	if _password_modal == null:
		return
	remove_child(_password_modal)
	_password_modal.queue_free()
	_password_modal = null


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
	# 標題層只畫全屏圖：一級 = Title_ChooseGames，二級 = 該款遊戲的標題圖。
	# 不疊任何文字/按鈕（需求文件第四/六節）；將來的標題動畫、Y2K 元素
	# 都在這兩個分支底下繼續加。
	# 圖都是 ~16:9（1920×1080 或 1672×941），拉到 480×270 變形可忽略。
	if mode == Mode.MENU:
		draw_texture_rect(TITLE_MAIN_IMAGE, Rect2(0, 0, 480, 270), false)
		# 一級標題的遊戲選擇清單（管理員用）：名字
		_draw_game_menu()
		_center("↑ ↓ SELECT    A START    B CLEAR", 250, 12, Palette.BG)
	elif mode == Mode.SETTING or mode == Mode.SETTING_CLEAR:
		# SETTING 二級／清除三級：同一張一級圖墊底，一級清單文字整個不畫
		draw_texture_rect(TITLE_MAIN_IMAGE, Rect2(0, 0, 480, 270), false)
		if mode == Mode.SETTING:
			_draw_setting_menu()
		else:
			_draw_clear_menu()
	elif (mode == Mode.GAME_TITLE or mode == Mode.NAME_INPUT) and active_index >= 0:
		# 二級標題圖同時是起名 overlay 的底層：NAME_INPUT 時底下要透得出這張圖。
		# 二級標題沒有任何按鈕與提示文字 —— 按任意鍵即起名開局。
		var image: Texture2D = GAMES[active_index]["title_image"]
		draw_texture_rect(image, Rect2(0, 0, 480, 270), false)
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


## SETTING 二級選單（CLEAR LEADERBOARD / UNLIMITED COINS）：同一塊管理員
## 區域內垂直排列，選中／未選中顏色與一級清單相同。UNLIMITED COINS 行右側
## 緊接名字顯示 ON/OFF 狀態（用量到的名字寬度推過去）。
## 底部一行操作提示在區域內。
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
		if i == SETTING_COINS_IDX:
			var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, MENU_SUB_SIZE).x
			draw_string(font, Vector2(name_x + w + 8.0, y),
				"ON" if Settings.is_unlimited_coins() else "OFF",
				HORIZONTAL_ALIGNMENT_LEFT, -1, MENU_SUB_SIZE, col)
		y += MENU_LINE_H
	_center_in_region("A CONFIRM    B BACK",
		MENU_REGION_POS.y + MENU_REGION_SIZE.y - 20.0, 8, Palette.TEXT_DIM)


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
