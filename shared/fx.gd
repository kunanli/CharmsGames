class_name Fx
extends RefCounted

# ─────────────────────────────────────────────────────────
# 純表現用的小工具：粒子爆散與擠壓變形。
#
# 跟 juice.gd 的分工：juice 動的是「整個畫面」，fx 動的是「單一物件」。
# 實機試玩的結論是自動移動整個畫面會讓人暈，所以 game feel 的重心
# 放在這一支 —— 單一物件在動不會暈，資訊量卻更大（看得出是誰、被打到哪裡）。
#
# 一樣只做數學與繪製，不碰任何遊戲數值：粒子不參與碰撞，擠壓只影響
# 繪製時的縮放，不會動到 position。
#
# 為什麼不用 GPUParticles2D：專案的硬規則是所有東西由程式碼生成、
# 不改 .tscn，而且這裡的量很小（一次幾十顆），純 draw_rect 就夠了。
# ─────────────────────────────────────────────────────────

const GRAVITY := 220.0        # px/s²，粒子的基礎重力


class Particle:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.0
	var life_max := 1.0
	var col := Color.WHITE
	var size := 2.0
	var grav := 1.0           # 重力倍率，0 = 不受重力（例如水中或星塵）


var _parts: Array[Particle] = []
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func clear() -> void:
	_parts.clear()


func count() -> int:
	return _parts.size()


## 從 pos 噴出一叢粒子。
## cone/dir 可以做出方向性的噴發（例如水花往上、碎片沿撞擊方向）；
## 預設 cone = TAU 就是四面八方。
func burst(pos: Vector2, count_: int, col: Color, speed := 70.0, life := 0.45,
		size := 2.0, grav := 1.0, dir := 0.0, cone := TAU) -> void:
	for i in count_:
		var p := Particle.new()
		p.pos = pos
		var a := dir + _rng.randf_range(-cone * 0.5, cone * 0.5)
		p.vel = Vector2(cos(a), sin(a)) * speed * _rng.randf_range(0.45, 1.0)
		p.life_max = life * _rng.randf_range(0.7, 1.0)
		p.life = p.life_max
		p.col = col
		p.size = size
		p.grav = grav
		_parts.append(p)


func update(delta: float) -> void:
	var i := _parts.size() - 1
	while i >= 0:
		var p: Particle = _parts[i]
		p.life -= delta
		if p.life <= 0.0:
			_parts.remove_at(i)
		else:
			p.vel.y += GRAVITY * p.grav * delta
			p.pos += p.vel * delta
		i -= 1


## 由呼叫端在正確的圖層（通常是 WORLD）內呼叫，粒子才會跟著鏡頭位移。
func draw(ci: CanvasItem) -> void:
	for p in _parts:
		var t := p.life / p.life_max
		# 邊縮小邊淡出。整數畫面下方點比圓點乾淨，而且位置要對齊像素。
		var s := maxf(1.0, roundf(p.size * t))
		ci.draw_rect(
			Rect2((p.pos - Vector2(s, s) * 0.5).round(), Vector2(s, s)),
			Color(p.col, clampf(t * 1.4, 0.0, 1.0)))


## 擠壓變形。回傳一個縮放向量，直接餵給 draw_set_transform()。
##
## t 從 1 衰減到 0；axis 是撞擊方向 —— 沿該軸壓扁、垂直方向撐開，
## 看起來才像有體積的東西撞上去。
##
## 用阻尼餘弦而不是單純衰減：單純衰減看起來像洩氣，要有一次回彈才有彈性。
static func squash(t: float, axis: Vector2, amount := 0.30) -> Vector2:
	if t <= 0.0:
		return Vector2.ONE
	var e: float = amount * t * cos(t * PI * 2.2)
	var ax := absf(axis.x)
	var ay := absf(axis.y)
	if ax == 0.0 and ay == 0.0:
		ay = 1.0                      # 沒給方向就當成垂直壓扁
	return Vector2(1.0 - e * ax + e * ay, 1.0 - e * ay + e * ax)
