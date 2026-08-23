extends Node2D

# ─────────────────────────────────────────────────────────
# 啟動標題 + 遊戲流程狀態機：
#   MENU（一級標題圖）→ GAME_TITLE（二級標題圖）
#     → NAME_INPUT → PLAYING → LEADERBOARD（重開 / 退出）
#
# 標題層只畫全屏圖（assets/title/）＋二級標題下方一條緩慢閃爍的開局提示
# （中文「按空格键开启游戏」內建字型顯示不了，先掛英文，接中文字型後換字串）。
# 二級標題是「固定場所」：不響應 1/2/3 與 ESC，**唯一回一級的路徑是
# F3 管理員密碼**（ui/admin_password.gd，Modal Overlay）：正確 → 回一級，
# ESC → 留在二級。遊戲結束（面板 ESC）與遊戲中 ESC 都回**該款的二級標題**。
# 彈窗開著時本檔不處理任何按鍵（輸入分層見 _unhandled_key_input 註解）。
#
# 遊戲不是場景，是「掛在臨時 Node2D 上的腳本」：
#   load(path) → Node2D.new() → set_script() → add_child()
# add_child() 那一刻才會觸發遊戲的 _ready()，所以順序不能調換。
# 回選單時直接 queue_free() 整個節點，遊戲自己生的子節點跟著一起消失，
# 不需要每款遊戲各寫一套清理邏輯。
#
# 排行榜流程（LeaderboardRecord / LeaderboardManager / 面板，見 shared/ 與 ui/）：
#   遊戲進 RESULT 時發 round_finished(score, duration, game_over)
#   → launcher 組裝記錄、submit_score()、打開通用排行榜面板
#   面板 Enter = 重開同一款（名字保留）；ESC = 退出回選單（清名字）
#   名字由 CurrentPlayerSession 管理：第一次進遊戲先輸入，退出即清。
#
# 新增一款遊戲＝在 GAMES 加一筆（含 id），不用新增場景、不用改這支以外的檔案。
# 腳本還不存在的項目會顯示 NOT BUILT YET，不會讓選單當掉。
# ─────────────────────────────────────────────────────────

enum Mode { MENU, GAME_TITLE, NAME_INPUT, PLAYING, LEADERBOARD }

const GAMES := [
	{
		"id": "seeker",
		"title": "CHARMS SEEKER",
		"blurb": "MAZE CHASE",
		"script": "res://games/seeker/seeker.gd",
		"title_image": preload("res://assets/title/Title_Maze.png"),
	},
	{
		"id": "fishing",
		"title": "CHARMS FISHING",
		"blurb": "HOOK THE CHARMS",
		"script": "res://games/fishing/fishing.gd",
		"title_image": preload("res://assets/title/Title_Fishing.png"),
	},
	{
		"id": "catch",
		"title": "CHARMS CATCH",
		"blurb": "CATCH AND DODGE",
		"script": "res://games/catch/catch.gd",
		"title_image": preload("res://assets/title/Title_Catch.png"),
	},
]

## 一級標題全屏圖。三張二級標題圖掛在各 GAMES 條目的 title_image。
const TITLE_MAIN_IMAGE: Texture2D = preload("res://assets/title/Title_ChooseGames.png")

const NOTICE_TIME := 1.6      # 「還沒做」提示停留幾秒


var mode := Mode.MENU
var game: Node2D = null       # 目前正在玩的那一款，沒在玩時為 null
var active_index := -1        # 目前這局是哪一款（排行榜重開要用）
var _panel: Node2D = null
var _name_input: Node2D = null
var _password_modal: Node2D = null   # F3 管理員密碼彈窗；非 null 時攔下所有標題層按鍵
var _built: Array[bool] = []  # 每一款的腳本存不存在，開場算一次就好
var _notice := ""
var _notice_timer := 0.0
var _finish_data := {}        # 局終暫存：record_id / score / game_over
var _title_time := 0.0        # 二級標題的閃爍提示計時器


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
	#   Level 1  密碼彈窗開著 → 只剩彈窗自己的按鍵，這裡整段不處理
	#   Level 2  二級標題 → 只收 Space/Enter 進起名、F3 開彈窗。
	#            固定場所：1/2/3 不換遊戲、ESC 無效（回一級只有 F3 密碼一條路）
	#   Level 3  一級標題 → 1/2/3 進二級標題
	if _password_modal != null:
		return                     # Level 1：彈窗開著，底層標題不響應任何鍵

	match mode:
		Mode.MENU:
			var index := key.keycode - KEY_1
			if index >= 0 and index < GAMES.size():
				_enter_game_title(index)
		Mode.GAME_TITLE:
			match key.keycode:
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_launch(active_index)
				KEY_F3:
					_open_password_modal()
		Mode.PLAYING:
			if key.keycode == KEY_ESCAPE:
				_close_game()


## 一級標題按 1/2/3 → 二級標題。未建置的款項留在原地跳提示。
func _enter_game_title(index: int) -> void:
	if not _built[index]:
		var entry: Dictionary = GAMES[index]
		_notice = "%s NOT BUILT YET" % entry["title"]
		_notice_timer = NOTICE_TIME
		queue_redraw()
		return
	active_index = index
	mode = Mode.GAME_TITLE
	queue_redraw()


func _launch(index: int) -> void:
	var entry: Dictionary = GAMES[index]

	if not _built[index]:
		_notice = "%s NOT BUILT YET" % entry["title"]
		_notice_timer = NOTICE_TIME
		queue_redraw()
		return

	if not CurrentPlayerSession.is_active():
		# 第一次進遊戲：先輸入名字，輸入成功才真正開局
		active_index = index
		_open_name_input()
		return
	_start_game(index)


func _start_game(index: int) -> void:
	var entry: Dictionary = GAMES[index]
	var script: Script = load(entry["script"])
	if script == null:
		_notice = "%s FAILED TO LOAD" % entry["title"]
		_notice_timer = NOTICE_TIME
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


# ── 局終：提交成績 → 排行榜面板 ─────────────────────────

func _on_round_finished(score: int, duration: float, game_over: bool) -> void:
	var entry: Dictionary = GAMES[active_index]
	var consts: Dictionary = game.get_script().get_script_constant_map()

	var record := LeaderboardRecord.new()
	record.game_id = entry["id"]
	record.game_name = entry["title"]
	record.player_name = CurrentPlayerSession.player_name
	record.score = score
	record.difficulty_id = str(consts.get("DIFFICULTY_ID", "normal"))
	record.difficulty_name = str(consts.get("DIFFICULTY_NAME", "NORMAL"))
	record.duration_seconds = duration

	_finish_data = {
		"record_id": LeaderboardManager.submit_score(record),
		"score": score,
		"game_over": game_over,
	}
	# 推遲到這幀結束再切換：不能在發射者的 signal 回呼裡把它移出場景樹
	_open_leaderboard.call_deferred()


func _open_leaderboard() -> void:
	if mode != Mode.PLAYING:
		return                # 保險：局終後緊接著的 ESC 之類的路徑，避免重複開
	_free_game_node()        # 只釋放節點，不動 session —— 面板還要顯示名字

	var entry: Dictionary = GAMES[active_index]
	var panel := Node2D.new()
	panel.name = "LeaderboardPanel"
	panel.set_script(load("res://ui/leaderboard_panel.gd"))
	# 面板的欄位要用 set() 設定：panel 是 Node2D 型別，編譯器看不到腳本屬性
	panel.set("game_id", entry["id"])
	panel.set("game_name", entry["title"])
	panel.set("player_name", CurrentPlayerSession.player_name)
	panel.set("current_record_id", _finish_data["record_id"])
	panel.set("score", _finish_data["score"])
	panel.set("game_over", _finish_data["game_over"])
	panel.connect("restart_requested", Callable(self, "_on_panel_restart"))
	panel.connect("exit_requested", Callable(self, "_on_panel_exit"))
	_panel = panel
	add_child(panel)
	mode = Mode.LEADERBOARD
	queue_redraw()


func _on_panel_restart() -> void:
	# 重新開始：名字保留，直接重開同一款（下一局結束會再提交一條新記錄）
	_close_panel()
	_start_game(active_index)


func _on_panel_exit() -> void:
	# 退出：清名字回**該款的二級標題**（不回一級），下次 Space 重新起名
	_close_panel()
	CurrentPlayerSession.clear()
	mode = Mode.GAME_TITLE
	queue_redraw()


# ── 姓名輸入 ────────────────────────────────────────────

func _open_name_input() -> void:
	var ni := Node2D.new()
	ni.name = "NameInput"
	ni.set_script(load("res://ui/name_input.gd"))
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
	elif mode == Mode.GAME_TITLE and active_index >= 0:
		var image: Texture2D = GAMES[active_index]["title_image"]
		draw_texture_rect(image, Rect2(0, 0, 480, 270), false)
		# 開局提示：遊戲視覺下方居中、緩慢閃爍（亮 1.2 秒 / 滅 0.8 秒）。
		# 原始需求文字是中文「按空格键开启游戏」—— 內建字型沒有中文字形
		# （AGENTS.md 硬規則：HUD 一律英文），接入像素中文字型後改這一行字串即可。
		if fmod(_title_time, 2.0) < 1.2:
			_center("PRESS SPACE TO START", 236, 12, Palette.GOLD)
	else:
		return              # 遊戲／面板／輸入屏自己會把整個畫面畫滿

	# 提示（NOT BUILT / 載入失敗）直接疊在圖上，極少出現
	if _notice != "":
		_center(_notice, 256, 10, Palette.WARN)


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, 480, size, col)
