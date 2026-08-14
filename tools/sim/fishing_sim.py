#!/usr/bin/env python3
"""CharmsFishing：物件放置、可及性（死內容）、寶箱達成率。

執行： python3 tools/sim/fishing_sim.py

常數必須與 games/fishing/fishing.gd 同步（見本目錄 README 的「同步紀律」）。
"""
import math
import random
import statistics as st

# ── 與 games/fishing/fishing.gd 同步 ───────────────────────
PIVOT = (240.0, 96.0)
SURFACE_Y = 96.0
WATER_L, WATER_R, WATER_B = 6.0, 474.0, 266.0
MAX_ANGLE_DEG = 75.0
SWING_PERIOD, RUSH_TIME, RUSH_SWING = 2.4, 15.0, 1.15
LINE_MIN, LINE_MAX = 12.0, 205.0
EXTEND_SPEED, RETRACT_EMPTY = 150.0, 210.0
MOON_USES, MOON_BOOST = 3, 3.0
CHEST = (1000, 2000, 3500)
SHALLOW, MID, DEEP = (112, 158), (162, 208), (212, 258)
RESPAWN_DELAY = 2.2
ROUND_TIME = 60.0
DT = 1 / 60

JUNK, SPEARL, BIGF, STAR, CHARM, ROCK, SHADOW = range(7)
DEF = {
    JUNK:   dict(score=10,  pull=165.0, size=(16, 16), name="雜魚"),
    SPEARL: dict(score=50,  pull=165.0, size=(16, 16), name="小珍珠"),
    BIGF:   dict(score=100, pull=58.0,  size=(32, 16), name="大魚"),
    STAR:   dict(score=200, pull=105.0, size=(16, 16), name="星塵珍珠"),
    CHARM:  dict(score=500, pull=105.0, size=(16, 16), name="Charm"),
    ROCK:   dict(score=0,   pull=34.0,  size=(16, 16), name="石頭"),
    SHADOW: dict(score=0,   pull=105.0, size=(16, 16), name="暗影猫魚"),
}
# 星塵珍珠與 Charm 是 GDD 明寫「每局固定 N 顆」的有限寶物，不補充。
RESPAWN = {JUNK: SHALLOW, SPEARL: SHALLOW, BIGF: (162, 258),
           ROCK: (162, 258), SHADOW: MID}
PLAN = [(JUNK, 8, SHALLOW), (SPEARL, 5, SHALLOW), (BIGF, 4, (MID[0], DEEP[1])),
        (STAR, None, MID), (CHARM, None, DEEP), (ROCK, 6, (MID[0], DEEP[1])),
        (SHADOW, 2, MID)]

FAILED = []


def ok(cond, msg):
    print(("  PASS  " if cond else "  FAIL  ") + msg)
    if not cond:
        FAILED.append(msg)


class Item:
    __slots__ = ("k", "x", "y", "w", "h", "vx")

    def __init__(self, k, x, y, vx=0.0):
        self.k, self.x, self.y, self.vx = k, x, y, vx
        self.w, self.h = DEF[k]["size"]

    def rect(self):
        return (self.x - self.w / 2, self.y - self.h / 2, self.w, self.h)

    def has(self, p):
        x, y, w, h = self.rect()
        return x <= p[0] <= x + w and y <= p[1] <= y + h


def reachable(it):
    """鉤得到嗎？兩件事會造成永遠撈不到的死內容：超出 ±75° 錐形、超過最大線長。"""
    dx, dy = it.x - PIVOT[0], it.y - PIVOT[1]
    if dy <= 0:
        return False
    if abs(math.atan2(dx, dy)) > math.radians(MAX_ANGLE_DEG - 4.0):
        return False
    return math.hypot(dx, dy) <= LINE_MAX - 10.0


def overlaps(c, items, m):
    x, y, w, h = c.rect()
    x -= m; y -= m; w += 2 * m; h += 2 * m
    for o in items:
        ox, oy, ow, oh = o.rect()
        if x < ox + ow and ox < x + w and y < oy + oh and oy < y + h:
            return True
    return False


def spawn_one(k, band, items, rng):
    w, h = DEF[k]["size"]
    vx = 0.0
    if k == BIGF:
        vx = 20.0 * rng.choice([1, -1])
    elif k == SHADOW:
        vx = 12.0 * rng.choice([1, -1])
    # 兩段式：先要求 4px 空隙，擠不下就退讓成「不重疊即可」，
    # 否則族群補充在滿場時會靜靜失敗，魚群隨時間越來越稀。
    for m in (4.0, 0.0):
        for _ in range(40):
            it = Item(k, rng.uniform(WATER_L + w, WATER_R - w),
                      rng.uniform(band[0], band[1]), vx)
            if reachable(it) and not overlaps(it, items, m):
                items.append(it)
                return True
    return False


def populate(rng):
    items = []
    for k, n, band in PLAN:
        cnt = n if n is not None else (rng.randint(4, 5) if k == STAR else rng.randint(2, 3))
        for _ in range(cnt):
            spawn_one(k, band, items, rng)
    return items


def hook_pos(a, L):
    return (PIVOT[0] + math.sin(a) * L, PIVOT[1] + math.cos(a) * L)


def band_area(y0, y1):
    """水層的實際可及面積 —— 鉤子的可及範圍是倒三角形，越淺越窄。"""
    tot = 0.0
    A = math.radians(MAX_ANGLE_DEG - 4.0)
    r = LINE_MAX - 10.0
    for y in range(int(y0), int(y1)):
        dy = y - PIVOT[1]
        if dy <= 0:
            continue
        tot += min(2 * dy * math.tan(A),
                   2 * math.sqrt(max(r * r - dy * dy, 0)), 468.0)
    return tot


def placement(rounds=300):
    print("== 1. 放置與死內容 ==")
    want = {JUNK: 8, SPEARL: 5, BIGF: 4, ROCK: 6, SHADOW: 2}
    unreach, total, short = 0, 0, 0
    counts = {}
    for s in range(rounds):
        rng = random.Random(s)
        its = populate(rng)
        c = {}
        for i in its:
            total += 1
            c[i.k] = c.get(i.k, 0) + 1
            counts[i.k] = counts.get(i.k, 0) + 1
            if not reachable(i):
                unreach += 1
        for k, n in want.items():
            if c.get(k, 0) < n:
                short += 1
    ok(unreach == 0, f"{total} 次放置中沒有任何撈不到的死內容")
    ok(short == 0, f"{rounds} 局都沒有配額短缺")
    print("  平均每局：" + "、".join(
        f"{DEF[k]['name']} {v/rounds:.1f}" for k, v in sorted(counts.items())))

    print("\n  水層可及面積（配額要照這個算，不然淺層會生不出來）：")
    for name, b in [("淺層", SHALLOW), ("中層", MID), ("深層", DEEP)]:
        a = band_area(*b)
        print(f"    {name} y={b[0]}-{b[1]}  {a:8.0f}px²  約放得下 {a/576:.0f} 個")

    print("\n  族群補充可靠度（滿場時強制補 200 次）：")
    rng = random.Random(9)
    its = populate(rng)
    good = 0
    for _ in range(200):
        k = rng.choice(list(RESPAWN))
        if spawn_one(k, RESPAWN[k], its, rng):
            good += 1
        if its:
            its.pop(rng.randrange(len(its)))
    ok(good == 200, f"補充成功 {good}/200")


def play(seed, skill="good", respawn=True):
    rng = random.Random(seed)
    items = populate(rng)
    score, swing_t, moon = 0, 0.0, MOON_USES
    state, L, carried, boost, cur_a = "swing", LINE_MIN, None, False, 0.0
    t_left, resp, caught = ROUND_TIME, [], 0
    while t_left > 0:
        t_left -= DT
        for r in resp:
            r[1] -= DT
        for r in [x for x in resp if x[1] <= 0]:
            spawn_one(r[0], r[2], items, rng)
            resp.remove(r)
        if state == "swing":
            rate = RUSH_SWING if t_left <= RUSH_TIME else 1.0
            swing_t += DT * rate
            a = math.radians(MAX_ANGLE_DEG) * math.sin(2 * math.pi * swing_t / SWING_PERIOD)
            L = LINE_MIN
            tgt, dist, LL = None, 0.0, LINE_MIN
            while LL < LINE_MAX:
                LL += 2.0
                p = hook_pos(a, LL)
                if p[0] <= WATER_L or p[0] >= WATER_R or p[1] >= WATER_B:
                    break
                hit = [i for i in items if i.has(p)]
                if hit:
                    tgt, dist = hit[0], LL
                    break
            if tgt is not None:
                sc = DEF[tgt.k]["score"]
                cost = (dist - LINE_MIN) / EXTEND_SPEED + (dist - LINE_MIN) / DEF[tgt.k]["pull"]
                th = 40.0 if skill == "good" else 0.0
                if t_left < 8.0:
                    th = 15.0
                if sc / max(cost, 0.01) >= th:
                    state, cur_a = "extend", a
        elif state == "extend":
            L += EXTEND_SPEED * DT
            p = hook_pos(cur_a, L)
            hit = [i for i in items if i.has(p)]
            if hit:
                carried = hit[0]
                items.remove(carried)
                state, boost = "retract", False
                if respawn and carried.k in RESPAWN:
                    resp.append([carried.k, RESPAWN_DELAY, RESPAWN[carried.k]])
                if moon > 0 and DEF[carried.k]["pull"] <= 105.0 and DEF[carried.k]["score"] >= 200:
                    moon -= 1
                    boost = True
                elif moon > 0 and DEF[carried.k]["score"] == 0:
                    moon -= 1
                    carried = None
            elif L >= LINE_MAX or p[0] <= WATER_L or p[0] >= WATER_R or p[1] >= WATER_B:
                state, carried, boost = "retract", None, False
        else:
            sp = RETRACT_EMPTY if carried is None else \
                DEF[carried.k]["pull"] * (MOON_BOOST if boost else 1.0)
            L -= sp * DT
            if L <= LINE_MIN:
                L = LINE_MIN
                if carried is not None:
                    if carried.k == SHADOW:
                        t_left = max(0.0, t_left - 3.0)
                    else:
                        score += DEF[carried.k]["score"]
                        caught += 1
                carried, boost, state = None, False, "swing"
    return score, caught


def scores(rounds=40):
    print(f"\n== 2. 寶箱達成率（{rounds} 局）==")
    for skill, label in [("good", "會挑的玩家"), ("greedy", "照單全收")]:
        rs = [play(s, skill) for s in range(rounds)]
        xs = sorted(r[0] for r in rs)
        t = [100 * sum(1 for x in xs if x >= v) // rounds for v in CHEST]
        print(f"  {label:8s} 中位 {xs[rounds//2]:5d}  最高 {xs[-1]:5d}  "
              f"平均撈 {st.mean(r[1] for r in rs):.0f} 件")
        print(f"  {'':8s} 銅 {t[0]:3d}%  銀 {t[1]:3d}%  金 {t[2]:3d}%")

    print("\n  沒有族群補充會怎樣（GDD 原始設定）：")
    xs = sorted(play(s, "greedy", respawn=False)[0] for s in range(rounds))
    t = [100 * sum(1 for x in xs if x >= v) // rounds for v in CHEST]
    print(f"    中位 {xs[rounds//2]}  最高 {xs[-1]}  金 {t[2]}%")
    ok(t[2] == 0,
       f"金寶箱在無補充時拿不到（{CHEST[2]} 分在數學上超過盤面總值）—— "
       "這就是補充機制存在的理由")


def main():
    placement()
    scores()
    print()
    if FAILED:
        print(f"!! {len(FAILED)} 項失敗")
        return 1
    print("全部通過。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
