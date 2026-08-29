class_name ReadyGo
extends Node2D

## 開場 READY 動畫（2026-08）：實例化 assets/AnimationScene/UI_Animate/Ready_go.tscn
## （AnimatedSprite2D，Ready_GO 動畫 24 幀 @14FPS ≈ 1.71 秒），淡入 → 播完 → 淡出 →
## 自行釋放。純展示層：不發信號、不碰遊戲狀態機 —— READY → 正式遊戲的轉場由各遊戲
## 自己的 READY 計時器驅動，所以淡出絕不會阻塞流程。素材缺檔時直接消失，不報錯。

const SCENE_PATH := "res://assets/AnimationScene/UI_Animate/Ready_go.tscn"
const ANIM_NAME := "Ready_GO"
const FADE_SECONDS := 0.25          # 淡入／淡出各 0.25 秒（需求 0.2~0.3）
const ANIM_SECONDS := 24.0 / 14.0   # 24 幀 @14FPS（≈1.714 秒）；遊戲用它定 READY 時長
const CENTER := Vector2(240, 135)   # 480×270 邏輯畫面正中（素材 256×256）
const SCALE := 0.5                  # 縮放：256×256 太大，實機試玩後定為一半（128×128）

var _sprite: AnimatedSprite2D
var _tween: Tween


## 建立並掛到 parent（遊戲節點）下。遊戲節點自己 _draw() 先畫，動畫疊在最上層。
static func create(parent: Node) -> ReadyGo:
	var rg := ReadyGo.new()
	parent.add_child(rg)
	return rg


func _ready() -> void:
	var scene := load(SCENE_PATH)
	if scene == null:
		queue_free()          # 素材沒進場：不報錯、不阻塞，直接跳過
		return
	_sprite = scene.instantiate() as AnimatedSprite2D
	_sprite.centered = true
	_sprite.position = CENTER
	_sprite.scale = Vector2(SCALE, SCALE)
	_sprite.modulate.a = 0.0          # 先全透明再淡入，避免開場閃出儲存的最後一幀
	add_child(_sprite)
	_sprite.animation_finished.connect(_on_animation_finished)
	_sprite.frame = 0
	_sprite.play(ANIM_NAME)
	_tween = create_tween()
	_tween.tween_property(_sprite, "modulate:a", 1.0, FADE_SECONDS)


func _on_animation_finished() -> void:
	# 淡出由自己處理、自己釋放；遊戲流程不停下來等它
	_tween = create_tween()
	_tween.tween_property(_sprite, "modulate:a", 0.0, FADE_SECONDS)
	_tween.tween_callback(queue_free)
