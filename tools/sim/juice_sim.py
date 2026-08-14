#!/usr/bin/env python3
"""shared/juice.gd 與 shared/fx.gd 的數學驗證。

執行： python3 tools/sim/juice_sim.py

這裡的常數必須與 GDScript 保持同步（見本目錄 README 的「同步紀律」）。
"""
import math
import random

# ── 與 shared/juice.gd 同步 ────────────────────────────────
SUBTLE = dict(shake_max=3.0, shake_hz=30.0, trauma_decay=2.2, drift_max=4.0,
              drift_k=6.0, parallax=0.5, bg_shake=0.35, stop_scale=0.5, stop_max=0.12)
ARCADE = dict(shake_max=6.0, shake_hz=40.0, trauma_decay=1.6, drift_max=10.0,
              drift_k=5.0, parallax=0.55, bg_shake=0.5, stop_scale=1.0, stop_max=0.16)
OVERDRAW = 24.0
NAMES = {id(SUBTLE): "SUBTLE", id(ARCADE): "ARCADE"}
DTS = [1 / 30, 1 / 60, 1 / 144]


def vround(v):
    """Godot Vector2.round()：四捨五入且對零對稱（half away from zero）。"""
    def r(x):
        return math.floor(x + 0.5) if x >= 0 else math.ceil(x - 0.5)
    return (r(v[0]), r(v[1]))


class Juice:
    def __init__(self, preset=ARCADE, seed=0):
        self.p = preset
        self.rng = random.Random(seed)
        self.reset()

    def reset(self):
        self.t = 0.0
        self.axis = None
        self.shake = (0.0, 0.0)
        self.acc = 0.0
        self.look = (0.0, 0.0)
        self.want = (0.0, 0.0)
        self.stop = 0.0

    def kick(self, amount, axis=None):
        self.t = min(1.0, self.t + amount)
        if axis and axis != (0.0, 0.0):
            L = math.hypot(*axis)
            self.axis = (axis[0] / L, axis[1] / L)

    def freeze(self, seconds):
        self.stop = min(self.p["stop_max"],
                        max(self.stop, seconds * self.p["stop_scale"]))

    def look_at(self, d):
        L = math.hypot(*d)
        self.want = d if L <= 1.0 else (d[0] / L, d[1] / L)

    def tick(self, dt):
        frozen = self.stop > 0.0
        if not frozen:
            # 線性衰減。指數衰減永遠到不了 0，殘留的次像素值四捨五入後
            # 會變成永久的 ±1px 抽動。
            self.t = max(0.0, self.t - self.p["trauma_decay"] * dt)
            if self.t <= 0.0:
                self.axis = None
        self._tick_shake(dt)
        a = 1.0 - math.exp(-self.p["drift_k"] * dt)
        tx = self.want[0] * self.p["drift_max"]
        ty = self.want[1] * self.p["drift_max"]
        self.look = (self.look[0] + (tx - self.look[0]) * a,
                     self.look[1] + (ty - self.look[1]) * a)
        if frozen:
            self.stop -= dt
            return False
        return True

    def _tick_shake(self, dt):
        # 1.5 次方而不是平方 —— 平方會讓 trauma 0.2 只產生 0.24px，
        # 四捨五入後是 0，小碰撞完全看不見。
        mag = self.p["shake_max"] * (self.t ** 1.5)
        if mag <= 0.0:
            self.shake = (0.0, 0.0)
            self.acc = 0.0
            return
        step = 1.0 / self.p["shake_hz"]
        self.acc += dt
        if self.acc < step:
            return
        self.acc = math.fmod(self.acc, step)
        if self.axis is None:
            self.shake = (self.rng.uniform(-1, 1) * mag,
                          self.rng.uniform(-1, 1) * mag)
        else:
            ax, ay = self.axis
            px, py = -ay, ax
            m = self.rng.uniform(-1, 1)
            n = self.rng.uniform(-0.3, 0.3)
            self.shake = ((ax * m + px * n) * mag, (ay * m + py * n) * mag)

    def world_offset(self):
        return vround((self.shake[0] - self.look[0], self.shake[1] - self.look[1]))

    def bg_offset(self):
        b, q = self.p["bg_shake"], self.p["parallax"]
        return vround((self.shake[0] * b - self.look[0] * q,
                       self.shake[1] * b - self.look[1] * q))


# ── 與 shared/fx.gd 同步 ───────────────────────────────────
def squash(t, axis, amount=0.30):
    if t <= 0.0:
        return (1.0, 1.0)
    e = amount * t * math.cos(t * math.pi * 2.2)
    ax, ay = abs(axis[0]), abs(axis[1])
    if ax == 0.0 and ay == 0.0:
        ay = 1.0
    return (1.0 - e * ax + e * ay, 1.0 - e * ay + e * ax)


FAILED = []


def ok(cond, msg):
    print(("  PASS  " if cond else "  FAIL  ") + msg)
    if not cond:
        FAILED.append(msg)


def main():
    print("== 1. trauma 衰減會精準歸零（抓指數殘留）==")
    for p in (SUBTLE, ARCADE):
        for dt in DTS:
            j = Juice(p)
            j.kick(1.0)
            limit = 1.0 / p["trauma_decay"] + 1.0
            t, stopped = 0.0, None
            while t < 3.0:
                j.tick(dt)
                t += dt
                if j.world_offset() == (0, 0) and j.t <= 0.0:
                    stopped = t
                    break
            ok(stopped is not None and stopped <= limit,
               f"{NAMES[id(p)]} dt=1/{round(1/dt)} 於 {stopped and round(stopped,3)}s 歸零"
               f"（上限 {limit:.2f}s）")
        j = Juice(p)
        j.kick(1.0)
        for _ in range(600):
            j.tick(1 / 60)
        ok(all(j.world_offset() == (0, 0) for _ in range(120) if j.tick(1 / 60) or True),
           f"{NAMES[id(p)]} 靜置 2 秒零抽動")

    print("\n== 2. 漂移幀率無關（1-exp(-k*dt) 的存在理由）==")
    for p in (SUBTLE, ARCADE):
        res = {}
        for dt in DTS:
            j = Juice(p)
            j.look_at((1.0, 0.0))
            t = 0.0
            while t < 0.5:
                j.tick(dt)
                t += dt
            res[dt] = j.look[0]
        spread = max(res.values()) - min(res.values())
        ok(spread < 0.5, f"{NAMES[id(p)]} 三種 dt 差距 {spread:.4f}px（< 0.5）")

    print("\n== 3. 位移上界，佐證 OVERDRAW ==")
    for p in (SUBTLE, ARCADE):
        j = Juice(p, seed=7)
        rng = random.Random(11)
        mw = mb = 0
        for _ in range(100000):
            if rng.random() < 0.02:
                j.kick(rng.uniform(0.05, 1.0),
                       None if rng.random() < 0.5 else (rng.uniform(-1, 1), rng.uniform(-1, 1)))
            if rng.random() < 0.01:
                j.freeze(rng.uniform(0.02, 0.16))
            j.look_at((rng.uniform(-1, 1), rng.uniform(-1, 1)))
            j.tick(rng.choice(DTS))
            w, b = j.world_offset(), j.bg_offset()
            mw = max(mw, abs(w[0]), abs(w[1]))
            mb = max(mb, abs(b[0]), abs(b[1]))
        ok(mw <= OVERDRAW and mb <= OVERDRAW,
           f"{NAMES[id(p)]} world 最大 {mw}px、bg 最大 {mb}px，都在 OVERDRAW={OVERDRAW:.0f} 內")

    print("\n== 4. 整數輸出與靜止零偏移 ==")
    j = Juice(ARCADE, seed=3)
    rng = random.Random(5)
    allint = True
    for _ in range(20000):
        if rng.random() < 0.03:
            j.kick(rng.uniform(0.1, 1.0))
        j.look_at((rng.uniform(-1, 1), 0.0))
        j.tick(1 / 60)
        for v in j.world_offset() + j.bg_offset():
            if v != int(v):
                allint = False
    ok(allint, "所有輸出恆為整數")
    j = Juice(ARCADE)
    j.look_at((0.0, 0.0))
    for _ in range(300):
        j.tick(1 / 60)
    ok(j.world_offset() == (0, 0) and j.bg_offset() == (0, 0),
       "完全靜止時精準 (0,0)，無 floor 造成的半像素偏移")

    print("\n== 5. 震動取樣率（144fps 不能變成高頻嗡嗡聲）==")
    for p in (SUBTLE, ARCADE):
        j = Juice(p, seed=1)
        j.kick(1.0)
        prev, changes, t = j.shake, 0, 0.0
        while t < 1.0:
            j.t = 1.0                     # 固定 trauma，只測取樣率
            j.tick(1 / 144)
            t += 1 / 144
            if j.shake != prev:
                changes += 1
                prev = j.shake
        ok(changes <= p["shake_hz"] + 1,
           f"{NAMES[id(p)]} dt=1/144 每秒變化 {changes} 次（上限 {p['shake_hz']:.0f}+1，非 144）")

    print("\n== 6. 頓格永遠不會偷走比賽時間 ==")
    for p in (SUBTLE, ARCADE):
        j = Juice(p, seed=1)
        rng = random.Random(3)
        t_left, frozen, frames = 60.0, 0.0, 0
        while t_left > 0:
            frames += 1
            if rng.random() < 0.02:
                j.kick(rng.uniform(0.2, 1.0))
                j.freeze(rng.uniform(0.03, 0.16))
            if not j.tick(1 / 60):
                frozen += 1 / 60
                continue                  # 跟三款的 _process 一樣：整個 _run_state 跳過
            t_left -= 1 / 60
        ok(abs(frames / 60.0 - (60.0 + frozen)) < 0.1,
           f"{NAMES[id(p)]} 邏輯 60s 照跑完，只多花 {frozen:.2f}s 掛鐘時間")

    print("\n== 7. 方向性震動確實沿軸 ==")
    j = Juice(ARCADE, seed=2)
    j.kick(1.0, (1.0, 0.0))
    xs, ys = [], []
    for _ in range(400):
        j.t = 1.0
        j.tick(1 / 60)
        xs.append(abs(j.shake[0]))
        ys.append(abs(j.shake[1]))
    ok(sum(xs) / len(xs) > 2.5 * sum(ys) / len(ys),
       f"水平軸：|x| 均 {sum(xs)/len(xs):.2f} vs |y| {sum(ys)/len(ys):.2f}")

    print("\n== 8. 擠壓變形（shared/fx.gd）==")
    s = squash(1.0, (1.0, 0.0))
    ok(s[0] < 1.0 and s[1] > 1.0,
       f"水平撞擊 → 橫向壓扁縱向撐開 {tuple(round(x,3) for x in s)}")
    s = squash(1.0, (0.0, 1.0))
    ok(s[0] > 1.0 and s[1] < 1.0,
       f"垂直撞擊 → 縱向壓扁橫向撐開 {tuple(round(x,3) for x in s)}")
    ok(squash(0.0, (1.0, 0.0)) == (1.0, 1.0), "t=0 精準回到原尺寸")
    sig, t = [], 1.0
    while t > 0:
        sig.append(1 if 0.30 * t * math.cos(t * math.pi * 2.2) > 0 else -1)
        t -= 1 / 60 / 0.20
    flips = sum(1 for i in range(1, len(sig)) if sig[i] != sig[i - 1])
    ok(flips >= 1, f"有回彈（形變正負號翻轉 {flips} 次），不是單純洩氣")
    peak = max(abs(squash(t / 100, (1.0, 0.0))[0] - 1.0) for t in range(101))
    ok(peak < 0.35, f"最大形變 {peak*100:.0f}%，不會誇張到失真")

    print("\n== 各事件的震動可見度（決定觸發表的值要設多少）==")
    print(f"  {'trauma':>7} | {'SUBTLE':>8} | {'ARCADE':>8} | 可見?")
    for t in (0.06, 0.12, 0.20, 0.30, 0.34, 0.45, 0.55, 0.70, 0.90, 1.00):
        a = ARCADE["shake_max"] * t ** 1.5
        b = SUBTLE["shake_max"] * t ** 1.5
        vis = "看不見" if round(a) == 0 else ("剛好" if round(a) == 1 else "明顯")
        print(f"  {t:7.2f} | {b:7.2f}px | {a:7.2f}px | {vis}")
    print("  → ARCADE 可見門檻 trauma ≈ 0.19，SUBTLE ≈ 0.30。")
    print("    要兩組預設都看得見的事件，觸發值請設 ≥ 0.30。")

    print()
    if FAILED:
        print(f"!! {len(FAILED)} 項失敗")
        return 1
    print("全部通過。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
