class_name Juice
extends RefCounted

# ─────────────────────────────────────────────────────────
# 三款共用的 game feel 模組：撞擊震動、鏡頭偏移、視差、命中頓格。
#
# 這支只做數學，不碰任何節點 —— 位移由各遊戲自己套用（`draw_set_transform()`
# 或容器節點的 position）。這是刻意的：Seeker 的 player/cat 每幀都在用
# `position` 算移動與碰撞判定，把位移寫進 position 會被移動邏輯修正掉、
# 過格時被硬性清空，而且會動到 9px 的碰撞距離。位移一律走繪製層。
#
# 分層模型（三款一致）：
#   HUD    恆為 0             分數、時間、生命、結算文字、全螢幕閃光
#   WORLD  world_offset()     玩家、敵人、道具，**以及它們實際踩著的背景元素**
#   FAR    bg_offset()        星星、月亮、遠山／屋頂剪影
#
# 「實際踩著的」這條是關鍵：水面線、水體、地面矩形、地面線都算 WORLD。
# 船釘在水面線上、露娜站在地面線上 —— 讓接觸的雙方共用同一個位移，
# 脫節就變成結構上不可能，而不是一個要慢慢調的參數。
# ─────────────────────────────────────────────────────────

## 細膩克制。展場長時間試玩用這組。
const SUBTLE := {
	"shake_max": 3.0,      # trauma 滿值時的震動像素
	"shake_hz": 30.0,      # 震動重新取樣頻率
	"trauma_decay": 2.2,   # trauma 每秒衰減量
	"drift_max": 4.0,      # 鏡頭偏移最大像素
	"drift_k": 6.0,        # 偏移收斂速率
	"parallax": 0.5,       # 遠景吃多少比例的偏移
	"bg_shake": 0.35,      # 遠景吃多少比例的震動
	"stop_scale": 0.5,     # 頓格時間倍率
	"stop_max": 0.12,      # 單次頓格上限（秒）
}

## 街機爽快。
const ARCADE := {
	"shake_max": 6.0,
	"shake_hz": 40.0,
	"trauma_decay": 1.6,
	"drift_max": 10.0,
	"drift_k": 5.0,
	"parallax": 0.55,
	"bg_shake": 0.5,
	"stop_scale": 1.0,
	"stop_max": 0.16,
}

## 背景要往外多畫多少像素。ARCADE 最壞情況是 shake_max + drift_max = 16px，
## 24 留了 50% 餘裕，之後調參數不用再回頭改每一個背景矩形。
const OVERDRAW := 24.0

var preset: Dictionary = ARCADE

var _trauma := 0.0
var _axis := Vector2.ZERO          # 方向性震動的主軸，ZERO 表示全向
var _shake := Vector2.ZERO
var _shake_acc := 0.0
var _look := Vector2.ZERO          # 目前平滑後的偏移量（像素）
var _look_want := Vector2.ZERO     # 這一幀希望看向哪（-1~1）
var _stop := 0.0
var _rng := RandomNumberGenerator.new()


func _init(p: Dictionary = ARCADE) -> void:
	preset = p
	_rng.randomize()


func set_preset(p: Dictionary) -> void:
	preset = p


## 開新局時清乾淨
func reset() -> void:
	_trauma = 0.0
	_axis = Vector2.ZERO
	_shake = Vector2.ZERO
	_shake_acc = 0.0
	_look = Vector2.ZERO
	_look_want = Vector2.ZERO
	_stop = 0.0


## 加一次撞擊。amount 0~1，會累加並飽和在 1。
## 給了 axis 就是方向性震動 —— 沿著該軸抖，玩家才讀得出「我撞到哪一邊」。
func kick(amount: float, axis: Vector2 = Vector2.ZERO) -> void:
	_trauma = minf(1.0, _trauma + amount)
	if axis != Vector2.ZERO:
		_axis = axis.normalized()


## 命中頓格。取 max 而不是累加 —— 同時發生的兩個事件不該把凍結時間接起來。
func freeze(seconds: float) -> void:
	_stop = minf(float(preset["stop_max"]),
		maxf(_stop, seconds * float(preset["stop_scale"])))


## 玩家往哪個方向看（-1~1，會被限制在單位長度內）。
## **每幀都要呼叫。** 沒呼叫就會保持上一幀的傾斜 —— 這正是我們要的：
## 頓格期間遊戲主體不跑、look() 不被呼叫，鏡頭就會保持傾斜穿過凍結而不是回中。
func look(dir: Vector2) -> void:
	_look_want = dir.limit_length(1.0)


## 每幀更新。回傳「這一幀該不該跑遊戲邏輯」—— 頓格中回 false。
func tick(delta: float) -> bool:
	var frozen := _stop > 0.0

	# 頓格期間 trauma 不衰減（維持滿振幅），但震動照樣重新取樣。
	# 畫面凍住卻還在抖才是打擊感；兩個都凍只會看起來像掉幀。
	if not frozen:
		# 線性衰減，不用指數 —— 指數只會趨近 0 永遠到不了，殘留的次像素值
		# 經過整數四捨五入會變成永久的 ±1px 抽動。線性會在 trauma/decay 秒精準歸零。
		_trauma = maxf(0.0, _trauma - float(preset["trauma_decay"]) * delta)
		if _trauma <= 0.0:
			_axis = Vector2.ZERO

	_tick_shake(delta)

	# 1-exp(-k*dt) 是 dx/dt = k*(target-x) 的離散解，收斂速度與 FPS 無關。
	# 固定係數的 lerp(a, b, 0.15) 在 144fps 會比 60fps 快 2.4 倍收斂。
	_look = _look.lerp(_look_want * float(preset["drift_max"]),
		1.0 - exp(-float(preset["drift_k"]) * delta))

	if frozen:
		_stop -= delta
		return false
	return true


func _tick_shake(delta: float) -> void:
	# 振幅用 trauma 的 1.5 次方。
	#
	# 一開始寫的是平方（juice 教材的標準做法），但模擬跑出來發現：
	# shake_max=6 時，平方會讓 trauma 0.2 只產生 0.24px，四捨五入後是 0 ——
	# 「走到邊界震一下」這個功能等於完全看不見，可用的區間只剩 0.5~1.0。
	# 平方原本的理由是「讓尾巴快速掉到四捨五入門檻以下」，但 trauma 是
	# 線性衰減、本來就會精準歸零，那個理由並不成立。
	# 1.5 次方保留了大事件壓過小事件的動態範圍，又把可用區間拉回 0.2~1.0。
	var mag: float = float(preset["shake_max"]) * pow(_trauma, 1.5)
	if mag <= 0.0:
		_shake = Vector2.ZERO
		_shake_acc = 0.0
		return

	# 白雜訊但固定頻率重新取樣。每幀重抽的話，144Hz 螢幕會變成高頻嗡嗡聲；
	# 固定 Hz 在任何更新率下看起來都一樣。
	# 也不用 Perlin —— 振幅只有幾像素時，平滑雜訊看起來像鏡頭在滑，不像撞擊。
	var step := 1.0 / float(preset["shake_hz"])
	_shake_acc += delta
	if _shake_acc < step:
		return
	_shake_acc = fmod(_shake_acc, step)

	if _axis == Vector2.ZERO:
		_shake = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * mag
	else:
		var perp := Vector2(-_axis.y, _axis.x)
		_shake = (_axis * _rng.randf_range(-1.0, 1.0)
			+ perp * _rng.randf_range(-0.3, 0.3)) * mag


# ── 位移輸出 ────────────────────────────────────────────
#
# 符號慣例只在這裡寫一次，各遊戲一律不要自己算：
# look(dir) 的意思是「玩家往 dir 看」，鏡頭往 +look 移動，
# 所以**世界要畫在 -look**。在 Fishing 按左鍵 → _look.x 為負 →
# 世界內容往右移 → 看到更多左邊的湖面。正確。
#
# 而且整個合成值只四捨五入一次。分別 round 再相加會多出最多一整個像素的
# 誤差，兩層看起來就會對不齊。用 round() 不用 floor()：floor 對零不對稱
# （+0.4→0 但 -0.4→-1），會讓靜止時的畫面永久偏移一個像素。

func world_offset() -> Vector2:
	return (_shake - _look).round()


func bg_offset() -> Vector2:
	return (_shake * float(preset["bg_shake"])
		- _look * float(preset["parallax"])).round()


func is_frozen() -> bool:
	return _stop > 0.0


func trauma() -> float:
	return _trauma
