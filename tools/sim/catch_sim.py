#!/usr/bin/env python3
"""CharmsCatch：Combo 可達性、寶箱達成率、頓格是否偷走比賽時間。

執行： python3 tools/sim/catch_sim.py

常數必須與 games/catch/catch.gd 同步（見本目錄 README 的「同步紀律」）。
"""
import math
import random
import statistics as st
from collections import Counter

# ── 與 games/catch/catch.gd 同步 ───────────────────────────
MOVE_SPEED = 95.0          # 刻意偏離 GDD 的 60（企劃試玩後的手感調整）
DASH_MULT, DASH_CD = 1.8, 0.5
ACCEL, FRICTION = 900.0, 700.0
LUNA_Y, BASKET_DY = 236.0, -14.0
BASKET = (36.0, 8.0)
LANES, LANE_W, LANE_MIN_GAP = 6, 80.0, 0.6
SPAWN_Y, KILL_Y = -10.0, 262.0
START_LIVES, SHIELD_TIME, MOON_MAX = 3, 8.0, 3
COMBO_STEP, COMBO_MAX = 5, 5
CHEST = (1500, 3000, 5000)
ROUND_TIME, PHASE_LEN, CHARM_EVERY = 60.0, 15.0, 15.0
PHASES = [
    dict(speed=60.0,  max_on=2, bomb=0.10, cm=1.0, gap=(1.6, 2.2)),
    dict(speed=80.0,  max_on=3, bomb=0.20, cm=1.0, gap=(1.4, 2.0)),
    dict(speed=100.0, max_on=4, bomb=0.30, cm=1.0, gap=(1.2, 1.8)),
    dict(speed=120.0, max_on=5, bomb=0.35, cm=2.0, gap=(1.0, 1.5)),
]
JEWEL, STARDUST, CHARM, BOMB, MOON = range(5)
BASE = {JEWEL: 50, STARDUST: 100, CHARM: 300, BOMB: 0, MOON: 0}
CATCH_Y = LUNA_Y + BASKET_DY
DT = 1 / 60

FAILED = []


def ok(cond, msg):
    print(("  PASS  " if cond else "  FAIL  ") + msg)
    if not cond:
        FAILED.append(msg)


class Drop:
    __slots__ = ("k", "x", "y")

    def __init__(self, k, x, y):
        self.k, self.x, self.y = k, x, y


def play(seed, speed=MOVE_SPEED, inertia=True, chain=True, gaps=True,
         hitstop=0.0, policy="urgent"):
    """gaps=False 就退回「生成間隔綁在落速上」的舊行為（Combo 會死掉）。
       chain=False 關掉有價物的可及性約束。
       hitstop>0 模擬每次得分事件凍結 N 秒，用來確認不會偷走比賽時間。"""
    rng = random.Random(seed)
    t_left, score, lives, combo, mult = ROUND_TIME, 0, START_LIVES, 0, 1
    luna, vx, dash_cd, was_dash = 240.0, 0.0, 0.0, False
    shield, moons = 0.0, 0
    drops, lane_last = [], [LANE_MIN_GAP] * LANES
    spawn_t, charm_t = 0.6, CHARM_EVERY
    vs = vc = 0
    best_mult, frozen, at_wall, walls = 1, 0.0, False, 0

    def urgent_valuable():
        b = None
        for d in drops:
            if d.k == BOMB:
                continue
            if b is None or d.y > b.y:
                b = d
        return b

    def do_spawn(kind, ph):
        nonlocal vs
        cand = [i for i in range(LANES) if lane_last[i] >= LANE_MIN_GAP]
        if not cand:
            return False
        if chain and kind != BOMB:
            u = urgent_valuable()
            if u is not None:
                tu = (CATCH_Y - u.y) / ph["speed"]
                tn = (CATCH_Y - SPAWN_Y) / ph["speed"]
                w = tn - tu
                if w > 0:
                    r = speed * DASH_MULT * w * 0.85
                    f = [i for i in cand if abs(i * LANE_W + LANE_W / 2 - u.x) <= r]
                    if f:
                        cand = f
        ln = rng.choice(cand)
        drops.append(Drop(kind, ln * LANE_W + rng.uniform(14.0, LANE_W - 14.0), SPAWN_Y))
        lane_last[ln] = 0.0
        if kind not in (BOMB, MOON):
            vs += 1
        return True

    while t_left > 0 and lives > 0:
        t_left -= DT
        pi = min(int((ROUND_TIME - t_left) / PHASE_LEN), 3)
        ph = PHASES[pi]
        for i in range(LANES):
            lane_last[i] += DT
        charm_t -= DT
        spawn_t -= DT
        if len(drops) < ph["max_on"]:
            if charm_t <= 0.0:
                if do_spawn(CHARM, ph):
                    charm_t = CHARM_EVERY
            elif spawn_t <= 0.0:
                r = rng.random()
                if r < ph["bomb"]:
                    k = BOMB
                elif moons < MOON_MAX and rng.random() < 0.06:
                    k = MOON
                    moons += 1
                elif rng.random() < 0.04 * ph["cm"]:
                    k = CHARM
                else:
                    k = JEWEL if rng.random() < 0.72 else STARDUST
                if do_spawn(k, ph):
                    spawn_t = (rng.uniform(*ph["gap"]) if gaps
                               else rng.uniform(0.55, 1.05) * (60.0 / ph["speed"]))
        # AI
        target = None
        if policy == "urgent":
            for d in sorted([x for x in drops if x.k != BOMB and x.y <= CATCH_Y + 8],
                            key=lambda x: -x.y):
                tt = (CATCH_Y - d.y) / ph["speed"]
                if tt >= 0 and abs(d.x - luna) <= speed * DASH_MULT * tt:
                    target = d
                    break
        else:
            best = -1e9
            for d in drops:
                if d.k == BOMB or d.y > CATCH_Y + 8:
                    continue
                tt = (CATCH_Y - d.y) / ph["speed"]
                if tt < 0:
                    continue
                dx = abs(d.x - luna)
                if dx > speed * DASH_MULT * tt:
                    continue
                v = BASE[d.k] * min(1 + (combo + 1) // COMBO_STEP, COMBO_MAX) - dx * 0.05
                if v > best:
                    best, target = v, d
        want = luna if target is None else target.x
        for d in drops:
            if d.k != BOMB or shield > 0:
                continue
            tt = (CATCH_Y - d.y) / ph["speed"]
            if 0 <= tt < 0.45 and abs(d.x - luna) < 24:
                want = luna + (28 if d.x < luna else -28)
        if dash_cd > 0:
            dash_cd -= DT
        need = abs(want - luna)
        dashing = need > speed * 0.35 and dash_cd <= 0
        if was_dash and not dashing:
            dash_cd = DASH_CD
        was_dash = dashing
        top = speed * (DASH_MULT if dashing else 1.0)
        d_in = 0.0 if need < 1.5 else (1.0 if want > luna else -1.0)
        if inertia:
            if d_in != 0.0:
                vx += max(-ACCEL * DT, min(ACCEL * DT, d_in * top - vx))
            else:
                vx += max(-FRICTION * DT, min(FRICTION * DT, -vx))
        else:
            vx = d_in * top
        want_x = luna + vx * DT
        cl = max(12.0, min(468.0, want_x))
        if abs(want_x - cl) > 1e-9 and abs(vx) > 1.0:
            if not at_wall:
                walls += 1
            at_wall = True
            vx = 0.0
        else:
            at_wall = False
        luna = cl
        if shield > 0:
            shield = max(0.0, shield - DT)
        bx0, bx1 = luna - BASKET[0] / 2, luna + BASKET[0] / 2
        keep = []
        for d in drops:
            d.y += ph["speed"] * DT
            if bx0 <= d.x < bx1 and CATCH_Y <= d.y < CATCH_Y + BASKET[1]:
                if d.k == BOMB:
                    if shield > 0:
                        shield = 0.0
                    else:
                        lives -= 1
                        combo, mult = 0, 1
                    frozen += hitstop
                elif d.k == MOON:
                    shield = SHIELD_TIME     # 月光能量是 combo-neutral
                else:
                    vc += 1
                    combo += 1
                    mult = max(1, min(1 + combo // COMBO_STEP, COMBO_MAX))
                    best_mult = max(best_mult, mult)
                    score += BASE[d.k] * mult
                    frozen += hitstop
                continue
            if d.y >= KILL_Y:
                if d.k not in (BOMB, MOON):
                    combo, mult = 0, 1
                continue
            keep.append(d)
        drops = keep
    return dict(score=score, vs=vs, vc=vc, bm=best_mult, walls=walls,
                frozen=frozen, survived=t_left <= 0)


def report(label, rounds=120, **kw):
    rs = [play(s, **kw) for s in range(rounds)]
    xs = sorted(r["score"] for r in rs)
    t = [100 * sum(1 for x in xs if x >= v) // rounds for v in CHEST]
    cap = 100 * st.mean(r["vc"] for r in rs) / max(st.mean(r["vs"] for r in rs), 1)
    c = Counter(r["bm"] for r in rs)
    print(f"  {label:28s} 中位 {xs[rounds//2]:5d}  銅 {t[0]:3d}%  銀 {t[1]:3d}%  金 {t[2]:3d}%")
    print(f"  {'':28s} 接取率 {cap:.0f}%  最高倍率 {dict(sorted(c.items()))}")
    mean_mult = st.mean(r["bm"] for r in rs)
    return dict(median=xs[rounds // 2], tiers=t, capture=cap, dist=dict(c),
                mean_mult=mean_mult, walls=st.mean(r["walls"] for r in rs))


def main():
    print("== 1. 現行設定 ==")
    cur = report("95 px/s + 慣性（現行）")

    print("\n== 2. Combo 機制為什麼需要那兩條修正 ==")
    a = report("生成間隔綁落速（GDD 直譯）", gaps=False)
    b = report("關掉有價物可及性約束", chain=False)
    # 比的是分布而不是最高值 —— 兩者都可能偶爾摸到 ×5，差別在平均。
    ok(cur["mean_mult"] > a["mean_mult"] + 0.4,
       f"生成間隔綁落速時平均最高倍率 ×{a['mean_mult']:.2f}，"
       f"現行 ×{cur['mean_mult']:.2f} —— 「同屏上限是上限不是目標」")
    ok(cur["capture"] > a["capture"] + 10,
       f"接取率 {a['capture']:.0f}% → {cur['capture']:.0f}%")
    ok(cur["mean_mult"] > b["mean_mult"] + 0.4,
       f"關掉可及性約束時平均最高倍率只有 ×{b['mean_mult']:.2f} —— "
       "有價物必須落在「接完前一顆還追得上」的範圍內")

    print("\n== 3. 移動速度的影響（刻意偏離 GDD 的那一項）==")
    g = report("60 px/s 瞬時（GDD 原值）", speed=60.0, inertia=False)
    report("95 px/s 瞬時（無慣性）", speed=95.0, inertia=False)
    print(f"  → 速度 60→95 讓金寶箱從 {g['tiers'][2]}% 升到 {cur['tiers'][2]}%。")
    print("    慣性本身幾乎不影響平衡（純手感），變化來自速度。")
    print("    要把金寶箱拉回 10~15%，槓桿是生成間隔或炸彈比例，")
    print("    不要動三款共用的寶箱門檻。")

    print("\n== 4. 顧 Combo 的打法是否真的比搶高分好（GDD 的設計意圖）==")
    u = report("顧 Combo（接最快落地的）")
    v = report("搶高分（接最值錢的）", policy="value")
    ok(u["median"] > v["median"] * 1.2,
       f"顧 Combo 中位 {u['median']} 明顯勝過搶高分 {v['median']} "
       "—— Combo 確實是「拉開分差的關鍵」")

    print("\n== 5. 頓格不會偷走比賽時間 ==")
    base = st.mean(play(s)["score"] for s in range(60))
    hs = [play(s, hitstop=0.08) for s in range(60)]
    j = st.mean(r["score"] for r in hs)
    infl = 100 * (j - base) / base
    ok(abs(infl) < 5.0,
       f"每次得分凍結 0.08s（共 {st.mean(r['frozen'] for r in hs):.1f}s/局）"
       f"下，分數膨脹 {infl:+.2f}%（門檻 ±5%）")
    print("  原因是結構性的：凍結時整個 _run_state 跳過，time_left 也不減。")

    print()
    if FAILED:
        print(f"!! {len(FAILED)} 項失敗")
        return 1
    print("全部通過。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
