extends Node

# ─────────────────────────────────────────────────────────
# AudioManager —— 全專案共用的音訊管理器（Autoload，見 project.godot）
#
# BGM 與 SFX 分開管理：
#   - BGM：一支 AudioStreamPlayer，play_bgm() 切換；切到同一首不重播
#   - SFX：一池 AudioStreamPlayer（SFX_POOL_SIZE 支），快速連發不互相打斷
#
# 所有音訊路徑集中在這裡（BGM_PATHS / SFX_PATHS）。遊戲腳本一律只呼叫
# AudioManager.play_bgm / play_sfx，不直接 load() 或操作 AudioStreamPlayer。
# 素材未進場（載入失敗）時靜默跳過、不報錯 —— 與專案「素材未進場不當機」
# 的慣例一致；載入失敗的路徑記 null 不重試（同 launcher 的 idle stream cache）。
# ─────────────────────────────────────────────────────────

const BGM_DIR := "res://assets/audio/BGM/"
const SFX_DIR := "res://assets/audio/SFX/"

## BGM 名稱 → 路徑。遊戲流程用 play_bgm("TITLE" / "MAZE" / "FISHING" / "CATCH")。
const BGM_PATHS := {
	"TITLE": BGM_DIR + "BGM_TITLE.mp3",
	"MAZE": BGM_DIR + "BGM_MAZE.mp3",
	"FISHING": BGM_DIR + "BGM_FISHING.mp3",
	"CATCH": BGM_DIR + "BGM_CATCH.mp3",
}

## SFX 名稱 → 路徑（三款各三支）。UI 音效（ui_confirm／ui_select）已接入
## 各選單界面；coin_push 保留待未來投幣系統實裝。
const SFX_PATHS := {
	# Catch
	"catch_boom": SFX_DIR + "CATCH/catch_boom.wav",
	"catch_hitwall": SFX_DIR + "CATCH/catch_hitwall.mp3",
	"catch_item": SFX_DIR + "CATCH/catch_item.wav",
	# Fishing
	"fishing_boom": SFX_DIR + "FISHING/fishing_boom.wav",
	"fishing_catch": SFX_DIR + "FISHING/fishing_catch.wav",
	"fishing_gainpoints": SFX_DIR + "FISHING/fishing_gainpoints.wav",
	# Maze
	"maze_pickup_heart": SFX_DIR + "MAZE/maze_pickup_heart.mp3",
	"maze_pickup_perl": SFX_DIR + "MAZE/maze_pickup_perl.mp3",
	"maze_player_hurt": SFX_DIR + "MAZE/maze_player_hurt.mp3",
	# UI（預留，尚未接線）
	"ui_confirm": "res://assets/audio/UI/UI_confirm.wav",
	"ui_select": "res://assets/audio/UI/UI_select.wav",
	"coin_push": "res://assets/audio/UI/coin_push.wav",
}

const SFX_POOL_SIZE := 8

# 音量調校（2026-08-31 實機試玩）：BGM 太大聲調低 30%、SFX 太小聲調高 30%。
# 線性倍率：0.7 ≈ −3.1 dB、1.3 ≈ +2.3 dB（大於 1 是增益，引擎允許）。
const BGM_VOLUME := 0.7
const SFX_VOLUME := 1.3

var _bgm_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_index := 0                     # 全池都在播時，輪替的下一個
var _stream_cache: Dictionary = {}      # path → AudioStream；載入失敗記 null 不重試
var _bgm_name := ""


func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGM"
	_bgm_player.volume_linear = BGM_VOLUME
	add_child(_bgm_player)
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SFX%02d" % i
		p.volume_linear = SFX_VOLUME
		add_child(p)
		_sfx_pool.append(p)


## 切換背景音樂。正在播同一首時直接略過（不重播、不從頭來）。
func play_bgm(name: String) -> void:
	if name == _bgm_name and _bgm_player.playing:
		return
	var stream := _get_stream(BGM_PATHS.get(name, ""))
	if stream == null:
		return
	_bgm_player.stream = stream
	_bgm_player.play()
	_bgm_name = name


## 播放單發音效。同一支音效快速連發也不互相打斷：
## 先找池子裡沒在播的 player；全部都在播才輪替最舊的那一支。
func play_sfx(name: String) -> void:
	var stream := _get_stream(SFX_PATHS.get(name, ""))
	if stream == null:
		return
	var p := _next_sfx_player()
	p.stream = stream
	p.play()


func _next_sfx_player() -> AudioStreamPlayer:
	for i in SFX_POOL_SIZE:
		var idx := (_sfx_index + i) % SFX_POOL_SIZE
		if not _sfx_pool[idx].playing:
			_sfx_index = idx
			return _sfx_pool[idx]
	_sfx_index = (_sfx_index + 1) % SFX_POOL_SIZE
	return _sfx_pool[_sfx_index]


func _get_stream(path: String) -> AudioStream:
	if path == "" or _stream_cache.has(path):
		return _stream_cache.get(path, null)
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	_stream_cache[path] = stream
	return stream
