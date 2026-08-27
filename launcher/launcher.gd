extends Node2D

# ─────────────────────────────────────────────────────────
# 啟動標題 + 遊戲流程狀態機：
#   MENU（一級標題＝管理員的遊戲選擇畫面：↑ ↓ 循環選遊戲、← → 切當前
#     遊戲難度、B 開當前選中遊戲的排行榜清除選單、A 確認）
#   → GAME_TITLE（二級標題圖）→ NAME_INPUT → PLAYING
#   → GAME_OVER（局終結算界面）→ LEADERBOARD（排行榜）
#
# 標題層只畫全屏圖（assets/title/）＋一級標題的遊戲選擇清單（名字與難度用
# draw_string 疊在圖上）＋二級標題下方一條緩慢閃爍的開局提示
# （中文「按空格键开启游戏」內建字型顯示不了，先掛英文，接中文字型後換字串）。
# 二級標題是「固定場所」：不響應 1/2/3 與 ESC，**唯一回一級的路徑是
# F3 管理員密碼**（ui/admin_password.gd，Modal Overlay）：正確 → 回一級，
# ESC → 留在二級。遊戲結束與遊戲中 ESC 都回**該款的二級標題**。
# 二級標題按 R 開**當前款的排行榜**（ui/leaderboard_panel.gd，一律只讀：
# 只顯示前 10 名、沒有清除入口，B/ESC 關閉回二級標題）。
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

enum Mode { MENU, GAME_TITLE, NAME_INPUT, PLAYING, GAME_OVER, LEADERBOARD }

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

## 遊戲名稱區域：1920×1080 設計座標 (734, 392) 起、651×291（邏輯畫面 ÷4）
const MENU_REGION_POS := Vector2(774.0, 452.0) / 4.0
const MENU_REGION_SIZE := Vector2(651.0, 291.0) / 4.0
const MENU_NAME_SIZE := 16
const MENU_DIFF_SIZE := 12
const MENU_DIFF_X := 88.0      # EASY/HARD 畫在名字右側的固定距離（比最長的名字寬）
const MENU_LINE_H := 22.0


enum Difficulty { EASY, HARD }

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
var _title_time := 0.0        # 二級標題的閃爍提示計時器
var selected_game := 0        # 一級標題當前選中的遊戲（GAMES 索引，↑ ↓ 循環）
var game_difficulties: Array[int] = [   # 各遊戲獨立的難度，預設全 EASY；
	Difficulty.EASY,                    # ← → 只改「當前選中」那一格，切換選擇不重置
	Difficulty.EASY,
	Difficulty.EASY,
]


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
	if mode == Mode.GAME_TITLE:
		_title_time += delta    # 閃爍提示需要逐幀重繪
		queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	# NAME_INPUT / LEADERBOARD 的按鍵由各自的子節點處理並吃掉事件，
	# launcher 不需要也不應該碰。
	#
	# 輸入分層：
	#   Level 1  密碼彈窗／清除選單開著 → 只剩彈窗自己的按鍵，這裡整段不處理
	#   Level 2  二級標題 → 只收 Space/Enter 進起名、R 開排行榜、
	#            F3 開彈窗。
	#            固定場所：1/2/3 不換遊戲、ESC 無效（回一級只有 F3 密碼一條路）
	#   Level 3  一級標題 → ↑ ↓ 選遊戲（循環）、← → 切「當前選中」遊戲的難度、
	#            B 開當前遊戲的排行榜清除選單、A 確認進二級標題
	if _password_modal != null or _clear_modal != null:
		return                     # Level 1：彈窗開著，底層標題不響應任何鍵

	match mode:
		Mode.MENU:
			match key.keycode:
				KEY_UP, KEY_DOWN:
					var dir := 1 if key.keycode == KEY_DOWN else -1
					selected_game = (selected_game + dir + GAMES.size()) % GAMES.size()
					queue_redraw()
				KEY_LEFT, KEY_RIGHT:
					_toggle_difficulty()
				KEY_B:
					_open_clear_menu()
				KEY_A:
					_enter_game_title(selected_game)
		Mode.GAME_TITLE:
			match key.keycode:
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_launch(active_index)
				KEY_R:
					_open_leaderboard_view()
				KEY_F3:
					_open_password_modal()
		Mode.PLAYING:
			if key.keycode == KEY_ESCAPE:
				_close_game()


## 一級標題按 A 確認 → 二級標題。未建置的款項留在原地跳提示。
func _enter_game_title(index: int) -> void:
	if not _built[index]:
		_show_notice("%s NOT BUILT YET" % GAMES[index]["title"], Palette.WARN)
		return
	active_index = index
	mode = Mode.GAME_TITLE
	queue_redraw()


## 一級標題 ← → 切換「當前選中遊戲」的難度 EASY / HARD。各遊戲獨立記憶，
## 切換選擇不會重置其他遊戲的難度。進二級標題後玩家只能起名，不能再改。
func _toggle_difficulty() -> void:
	var d: int = game_difficulties[selected_game]
	game_difficulties[selected_game] = Difficulty.HARD if d == Difficulty.EASY else Difficulty.EASY
	queue_redraw()


## 排行榜記錄用的 difficulty_id（easy / hard）。
func _difficulty_id(index: int) -> String:
	return "hard" if game_difficulties[index] == Difficulty.HARD else "easy"


## 排行榜記錄用的 difficulty_name（EASY / HARD），也是一級標題畫在名字右側的文字。
func _difficulty_name(index: int) -> String:
	return "HARD" if game_difficulties[index] == Difficulty.HARD else "EASY"


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
	# 把一級標題選定的難度傳給遊戲（目前各款只當標籤記錄、玩法未分檔；
	# 分檔時在遊戲內讀這兩個欄位）。遊戲腳本沒有這兩個屬性時 set() 靜默無效。
	node.set("difficulty_id", _difficulty_id(index))
	node.set("difficulty_name", _difficulty_name(index))
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
	# 難度由管理員在一級標題選（各遊戲獨立），進二級後玩家只能起名、不能再改
	record.difficulty_id = _difficulty_id(active_index)
	record.difficulty_name = _difficulty_name(active_index)
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
	mode = Mode.GAME_TITLE
	queue_redraw()


# ── 排行榜面板（Game Over 進入／二級標題按 R 進入共用）────

## 開排行榜面板（二級標題按 R 或 Game Over 界面選 LEADERBOARD 進入，
## 兩者行為一致）：只顯示前 10 名、不顯示本局成績，B/ESC 回該款二級標題。
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


## 二級標題按 R：開當前款的排行榜，僅供查看（清除入口在一級標題）。
func _open_leaderboard_view() -> void:
	_open_leaderboard()


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
		# 一級標題的遊戲選擇清單（管理員用）：名字＋選中那行右側的難度
		_draw_game_menu()
		_center("↑ ↓ SELECT    ← → DIFFICULTY    A START    B CLEAR", 250, 12, Palette.BG)
	elif (mode == Mode.GAME_TITLE or mode == Mode.NAME_INPUT) and active_index >= 0:
		# 二級標題圖同時是起名 overlay 的底層：NAME_INPUT 時底下要透得出這張圖
		var image: Texture2D = GAMES[active_index]["title_image"]
		draw_texture_rect(image, Rect2(0, 0, 480, 270), false)
		# 開局提示：遊戲視覺下方居中、緩慢閃爍（亮 1.2 秒 / 滅 0.8 秒）。
		# 原始需求文字是中文「按空格键开启游戏」—— 內建字型沒有中文字形
		# （AGENTS.md 硬規則：HUD 一律英文），接入像素中文字型後改這一行字串即可。
		# 起名 overlay 蓋著時不畫提示，避免兩層各一個「按鍵」訊息。
		if mode == Mode.GAME_TITLE and fmod(_title_time, 2.0) < 1.2:
			_center("PRESS SPACE TO START", 226, 12, Palette.BG)
			_center("PRESS R FOR LEADERBOARD", 240, 10, Palette.TEXT_DIM)
	else:
		return              # 遊戲／面板／輸入屏自己會把整個畫面畫滿

	# 提示（NOT BUILT / 載入失敗 / 清除成功）直接疊在圖上，極少出現
	if _notice != "":
		_center(_notice, 256, 10, _notice_col)


## 一級標題的遊戲選擇清單：區域內垂直排列三款遊戲名（MAZE / FISHING / CATCH），
## 選中那行畫 MENU_SELECTED（#FFC4FF）、其餘畫 MENU_IDLE（#FF44FF）；
## EASY/HARD 只畫在選中那行的名字右側（固定 x，換行不會左右跳）。
func _draw_game_menu() -> void:
	var font := ThemeDB.fallback_font
	var name_x := MENU_REGION_POS.x + 8.0
	var y := MENU_REGION_POS.y + (MENU_REGION_SIZE.y - MENU_LINE_H * GAMES.size()) / 2.0
	for i in GAMES.size():
		var selected := i == selected_game
		var col := MENU_SELECTED if selected else MENU_IDLE
		var name: String = GAMES[i]["menu_name"]
		draw_string(font, Vector2(name_x, y), name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, MENU_NAME_SIZE, col)
		if selected:
			draw_string(font, Vector2(name_x + MENU_DIFF_X, y), _difficulty_name(i),
				HORIZONTAL_ALIGNMENT_LEFT, -1, MENU_DIFF_SIZE, col)
		y += MENU_LINE_H


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, 480, size, col)
