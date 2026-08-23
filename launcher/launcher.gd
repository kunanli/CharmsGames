extends Node2D

# ─────────────────────────────────────────────────────────
# 啟動選單 + 遊戲流程狀態機：
#   MENU → NAME_INPUT → PLAYING → LEADERBOARD（重開 / 退出）
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

enum Mode { MENU, NAME_INPUT, PLAYING, LEADERBOARD }

const GAMES := [
	{
		"id": "seeker",
		"title": "CHARMS SEEKER",
		"blurb": "MAZE CHASE",
		"script": "res://games/seeker/seeker.gd",
	},
	{
		"id": "fishing",
		"title": "CHARMS FISHING",
		"blurb": "HOOK THE CHARMS",
		"script": "res://games/fishing/fishing.gd",
	},
	{
		"id": "catch",
		"title": "CHARMS CATCH",
		"blurb": "CATCH AND DODGE",
		"script": "res://games/catch/catch.gd",
	},
]

const NOTICE_TIME := 1.6      # 「還沒做」提示停留幾秒


var mode := Mode.MENU
var game: Node2D = null       # 目前正在玩的那一款，沒在玩時為 null
var active_index := -1        # 目前這局是哪一款（排行榜重開要用）
var _panel: Node2D = null
var _name_input: Node2D = null
var _built: Array[bool] = []  # 每一款的腳本存不存在，開場算一次就好
var _notice := ""
var _notice_timer := 0.0
var _finish_data := {}        # 局終暫存：record_id / score / game_over / consts


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


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	# NAME_INPUT / LEADERBOARD 的按鍵由各自的子節點處理並吃掉事件，
	# launcher 不需要也不應該碰。
	match mode:
		Mode.MENU:
			var index := key.keycode - KEY_1
			if index >= 0 and index < GAMES.size():
				_launch(index)
		Mode.PLAYING:
			if key.keycode == KEY_ESCAPE:
				_close_game()


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
		"consts": consts,
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
	panel.set("chest_tiers", _chest_tiers_from(_finish_data["consts"]))
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
	# 退出：清名字回選單，下次進任何一款都要重新輸入
	_close_panel()
	CurrentPlayerSession.clear()
	mode = Mode.MENU
	queue_redraw()


## 寶箱門檻從遊戲腳本的常數讀（每款不同：Seeker/Catch 1500/3000/5000，
## Fishing 1000/2000/3500），改數值時只動遊戲那一支，面板不用碰。
func _chest_tiers_from(consts: Dictionary) -> Array[int]:
	return [
		int(consts.get("CHEST_BRONZE", 1500)),
		int(consts.get("CHEST_SILVER", 3000)),
		int(consts.get("CHEST_GOLD", 5000)),
	]


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
	mode = Mode.MENU
	queue_redraw()


# ── 節點清理 ────────────────────────────────────────────

## 只釋放遊戲節點（局終接面板用，不動 session）。
func _free_game_node() -> void:
	if game == null:
		return
	# 先脫離場景樹再排程釋放，否則 queue_free() 生效前它還會多跑一幀 _process/_draw
	remove_child(game)
	game.queue_free()
	game = null


## ESC 中離 = 退出：釋放節點、清名字回選單。
func _close_game() -> void:
	_free_game_node()
	CurrentPlayerSession.clear()
	_notice = ""
	_notice_timer = 0.0
	mode = Mode.MENU
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
	if mode != Mode.MENU:
		return             # 遊戲／面板／輸入屏自己會把整個畫面畫滿

	draw_rect(Rect2(0, 0, 480, 270), Palette.BG)

	_center("CHARMS GAMES", 54, 26, Palette.GOLD)
	_center("A PANDORA MINI ARCADE", 74, 10, Palette.TEXT_DIM)

	var font := ThemeDB.fallback_font
	for i in GAMES.size():
		var y := 118.0 + i * 34.0
		var entry: Dictionary = GAMES[i]
		var built: bool = _built[i]
		var name_col := Palette.TEXT if built else Palette.TEXT_DIM

		draw_string(font, Vector2(104, y), "[%d]" % (i + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.MOON)
		draw_string(font, Vector2(140, y), entry["title"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, name_col)
		draw_string(font, Vector2(140, y + 12), entry["blurb"] if built else "COMING SOON",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.TEXT_DIM)

	_center("PRESS 1-3 TO PLAY    ESC TO RETURN", 236, 10, Palette.TEXT_DIM)

	if _notice != "":
		_center(_notice, 256, 10, Palette.WARN)

	# 角落放個露娜的剪影當招牌，等美術素材進來再換掉
	draw_rect(Rect2(40, 150, 16, 28), Palette.LUNA, false, 1.0)
	draw_rect(Rect2(43, 153, 10, 8), Palette.LUNA)


func _center(text: String, y: float, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, 480, size, col)
