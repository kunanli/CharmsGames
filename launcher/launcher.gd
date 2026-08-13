extends Node2D

# ─────────────────────────────────────────────────────────
# 啟動選單：按 1/2/3 進遊戲，遊戲中按 ESC 回來。
#
# 遊戲不是場景，是「掛在臨時 Node2D 上的腳本」：
#   load(path) → Node2D.new() → set_script() → add_child()
# add_child() 那一刻才會觸發遊戲的 _ready()，所以順序不能調換。
# 回選單時直接 queue_free() 整個節點，遊戲自己生的子節點跟著一起消失，
# 不需要每款遊戲各寫一套清理邏輯。
#
# 新增一款遊戲＝在 GAMES 加一筆，不用新增場景、不用改這支以外的檔案。
# 腳本還不存在的項目會顯示 NOT BUILT YET，不會讓選單當掉。
# ─────────────────────────────────────────────────────────

const GAMES := [
	{
		"title": "CHARMS SEEKER",
		"blurb": "MAZE CHASE",
		"script": "res://games/seeker/seeker.gd",
	},
	{
		"title": "CHARMS FISHING",
		"blurb": "HOOK THE CHARMS",
		"script": "res://games/fishing/fishing.gd",
	},
	{
		"title": "CHARMS CATCH",
		"blurb": "CATCH AND DODGE",
		"script": "res://games/catch/catch.gd",
	},
]

const NOTICE_TIME := 1.6      # 「還沒做」提示停留幾秒


var game: Node2D = null       # 目前正在玩的那一款，回選單時為 null
var _built: Array[bool] = []  # 每一款的腳本存不存在，開場算一次就好
var _notice := ""
var _notice_timer := 0.0


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

	if game == null:
		# 選單中：數字鍵選遊戲
		var index := key.keycode - KEY_1
		if index >= 0 and index < GAMES.size():
			_launch(index)
	elif key.keycode == KEY_ESCAPE:
		_close_game()


func _launch(index: int) -> void:
	var entry: Dictionary = GAMES[index]

	if not _built[index]:
		_notice = "%s NOT BUILT YET" % entry["title"]
		_notice_timer = NOTICE_TIME
		queue_redraw()
		return

	var script: Script = load(entry["script"])
	if script == null:
		_notice = "%s FAILED TO LOAD" % entry["title"]
		_notice_timer = NOTICE_TIME
		queue_redraw()
		return

	var node := Node2D.new()
	node.name = "Game"
	node.set_script(script)
	game = node
	add_child(node)        # 這一行才會觸發遊戲的 _ready()
	queue_redraw()


func _close_game() -> void:
	if game == null:
		return
	# 先脫離場景樹再排程釋放，否則 queue_free() 生效前它還會多跑一幀 _process/_draw
	remove_child(game)
	game.queue_free()
	game = null
	_notice = ""
	_notice_timer = 0.0
	queue_redraw()


# ── 繪製 ────────────────────────────────────────────────

func _draw() -> void:
	if game != null:
		return             # 遊戲自己會把整個畫面畫滿

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
