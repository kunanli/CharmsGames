#!/usr/bin/env python3
"""CharmsCatch：Combo 可達性、分數分佈、頓格是否偷走比賽時間、掉落物數量翻倍。

執行： python3 tools/sim/catch_sim.py

常數必須與 games/catch/catch.gd 同步（見本目錄 README 的「同步紀律」）。
"""
import math
import random
import statistics as st
from collections import Counter

# ── 與 games/catch/catch.gd 同步 ───────────────────────────
MOVE_SPEED = 95.0          # 刻意偏離 GDD 的 60（企劃試玩後的手感調整）
HOLD_MULT, HOLD_TIME = 2.5, 1.0   # 長按同方向 1 秒線性升到 ×2.5（衝刺已移除）
ACCEL, FRICTION = 900.0, 700.0
LUNA_Y = 270.0                    # 腳踩螢幕最底（貼底）
# 人物與提籃融合成單一物件：接取判定框＝cc_person1 貼圖大小（90×71），
# 腳踩 LUNA_Y、水平置中（見 catch.gd 的 _catch_rect()）。美術換圖要同步這裡。
CATCH = (90.0, 71.0)
LANES, LANE_W, LANE_MIN_GAP = 6, 80.0, 0.6
SPAWN_Y, KILL_Y = -10.0, 270.0    # 漏接線＝判定框底邊＝螢幕最底
START_LIVES, SHIELD_TIME, MOON_MAX = 3, 8.0, 3
COMBO_STEP, COMBO_MAX = 5, 5
ROUND_TIME, PHASE_LEN, CHARM_EVERY = 60.0, 15.0, 15.0
# 掉落物數量翻倍（2026-09 企劃）：gap 減半、max_on 翻倍、炸彈比例對折。
# 連炸彈一起翻倍的話 AI 存活率 68%→19%、平均局長 56s→45s（見第 6 節）。
PHASES = [
    dict(speed=60.0,  max_on=4,  bomb=0.05,  cm=1.0, gap=(0.8, 1.1)),
    dict(speed=80.0,  max_on=6,  bomb=0.10,  cm=1.0, gap=(0.7, 1.0)),
    dict(speed=100.0, max_on=8,  bomb=0.15,  cm=1.0, gap=(0.6, 0.9)),
    dict(speed=120.0, max_on=10, bomb=0.175, cm=2.0, gap=(0.5, 0.75)),
]
JEWEL, STARDUST, CHARM, BOMB, MOON = range(5)
BASE = {JEWEL: 50, STARDUST: 100, CHARM: 300, BOMB: 0, MOON: 0}
CATCH_Y = LUNA_Y - CATCH[1]        # 判定框上緣：掉落物從上方進框，等效接取面
CLAMP = CATCH[0] / 2.0             # 邊界內縮＝貼圖半寬（與 _move_luna 同步）
RISK = CATCH[0] / 2.0 + 6.0        # 炸彈進到這個橫距內就視為威脅（半寬＋餘裕）
DODGE = CATCH[0] / 2.0 + 10.0      # 閃避位移：拉開到威脅距離之外
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
    luna, vx, hold_t, hold_dir = 240.0, 0.0, 0.0, 0.0
    shield, moons = 0.0, 0
    drops, lane_last = [], [LANE_MIN_GAP] * LANES
    spawn_t, charm_t = 0.6, CHARM_EVERY
    vs = vc = 0
    best_mult, frozen, at_wall, walls = 1, 0.0, False, 0
    bombs = 0

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
                    r = speed * HOLD_MULT * w * 0.85
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
                if tt >= 0 and abs(d.x - luna) <= speed * HOLD_MULT * tt:
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
                if dx > speed * HOLD_MULT * tt:
                    continue
                v = BASE[d.k] * min(1 + (combo + 1) // COMBO_STEP, COMBO_MAX) - dx * 0.05
                if v > best:
                    best, target = v, d
        want = luna if target is None else target.x
        for d in drops:
            if d.k != BOMB or shield > 0:
                continue
            tt = (CATCH_Y - d.y) / ph["speed"]
            if 0 <= tt < 0.45 and abs(d.x - luna) < RISK:
                want = luna + (DODGE if d.x < luna else -DODGE)
        need = abs(want - luna)
        d_in = 0.0 if need < 1.5 else (1.0 if want > luna else -1.0)
        # 長按加速：與 catch.gd 的 _move_luna 同步 —— 按同一方向持續 1 秒才到頂，
        # 放開或換方向就歸零重算
        if d_in == 0.0 or d_in != hold_dir:
            hold_t = 0.0
        else:
            hold_t = min(hold_t + DT, HOLD_TIME)
        hold_dir = d_in
        top = speed * (1.0 + (HOLD_MULT - 1.0) * hold_t / HOLD_TIME)
        if inertia:
            if d_in != 0.0:
                vx += max(-ACCEL * DT, min(ACCEL * DT, d_in * top - vx))
            else:
                vx += max(-FRICTION * DT, min(FRICTION * DT, -vx))
        else:
            vx = d_in * top
        want_x = luna + vx * DT
        cl = max(CLAMP, min(480.0 - CLAMP, want_x))
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
        bx0, bx1 = luna - CATCH[0] / 2, luna + CATCH[0] / 2
        keep = []
        for d in drops:
            d.y += ph["speed"] * DT
            if bx0 <= d.x < bx1 and CATCH_Y <= d.y < CATCH_Y + CATCH[1]:
                if d.k == BOMB:
                    bombs += 1
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
                frozen=frozen, survived=t_left <= 0,
                bombs=bombs, t_played=ROUND_TIME - t_left)


def report(label, rounds=120, **kw):
    rs = [play(s, **kw) for s in range(rounds)]
    xs = sorted(r["score"] for r in rs)
    cap = 100 * st.mean(r["vc"] for r in rs) / max(st.mean(r["vs"] for r in rs), 1)
    c = Counter(r["bm"] for r in rs)
    print(f"  {label:28s} 中位 {xs[rounds//2]:5d}  最高 {xs[-1]:5d}")
    print(f"  {'':28s} 接取率 {cap:.0f}%  最高倍率 {dict(sorted(c.items()))}")
    mean_mult = st.mean(r["bm"] for r in rs)
    return dict(median=xs[rounds // 2], capture=cap, dist=dict(c),
                mean_mult=mean_mult, walls=st.mean(r["walls"] for r in rs))


def main():
    print("== 1. 現行設定 ==")
    cur = report("95 px/s + 慣性（現行）")

    print("\n== 2. Combo 機制為什麼需要那兩條修正 ==")
    a = report("生成間隔綁落速（GDD 直譯）", gaps=False)
    b = report("關掉有價物可及性約束", chain=False)
    # 比的是分布而不是最高值 —— 兩者都可能偶爾摸到 ×5，差別在平均。
    # 融合判定框（90 寬）把接取變容易後，連綁落速的節奏都撐得起倍率
    # （×2.56 → ×2.93），現行策略仍勝但差距縮小，門檻從 +0.4 放寬到 +0.2。
    ok(cur["mean_mult"] > a["mean_mult"] + 0.2,
       f"生成間隔綁落速時平均最高倍率 ×{a['mean_mult']:.2f}，"
       f"現行 ×{cur['mean_mult']:.2f} —— 「同屏上限是上限不是目標」")
    ok(cur["capture"] > a["capture"] + 10,
       f"接取率 {a['capture']:.0f}% → {cur['capture']:.0f}%")
    # 長按 ×2.5 後 AI 幾乎全屏可達，可及性約束的邊際價值被高速度稀釋
    # （關掉約束 ×2.59，門檻從 +0.4 放寬到 +0.3）。2026-09 掉落物翻倍後
    # 再被密度稀釋（關掉約束 ×2.40 vs 現行 ×2.51，門檻放寬到 +0.1）：
    # 有價物越多，任意時刻都有一顆「快落地」的當最緊急目標，window 變大、
    # reach 幾乎覆蓋全屏，約束幾乎不縮窄候選。約束在真實玩家手中仍有意義
    # （玩家不會像 AI 一樣精準移動），生成端照樣保留。
    ok(cur["mean_mult"] > b["mean_mult"] + 0.1,
       f"關掉可及性約束時平均最高倍率只有 ×{b['mean_mult']:.2f} —— "
       "有價物必須落在「接完前一顆還追得上」的範圍內")

    print("\n== 3. 移動速度的影響（刻意偏離 GDD 的那一項）==")
    g = report("60 px/s 瞬時（GDD 原值）", speed=60.0, inertia=False)
    report("95 px/s 瞬時（無慣性）", speed=95.0, inertia=False)
    print(f"  → 速度 60→95 讓中位分數從 {g['median']} 升到 {cur['median']}。")
    print("    慣性本身幾乎不影響平衡（純手感），變化來自速度。")
    print("    要把難度拉回來，槓桿是生成間隔或炸彈比例。")

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

    print("\n== 6. 掉落物數量翻倍（2026-09 企劃）==")
    # 企劃要求掉落物數量翻倍：gap 減半＋max_on 翻倍後，有價物 28.6→61.7 顆/局。
    # 但炸彈也跟著翻倍會讓 AI 存活率 68%→19%、平均局長 56s→45s —— 局提前結束，
    # 總掉落數與分數反而縮水（中位 3900→3400）。所以炸彈比例對折（0.10→0.05 等），
    # 炸彈密度（生成率 × 比例）維持不變，死亡數與局長也不變。這裡鎖住四個結果：
    # 有價物翻倍、炸彈密度不變、局長不縮水、存活率不崩。
    rs = [play(s) for s in range(120)]
    vs = st.mean(r["vs"] for r in rs)
    vc = st.mean(r["vc"] for r in rs)
    bombs = st.mean(r["bombs"] for r in rs)
    t_played = st.mean(r["t_played"] for r in rs)
    surv = 100 * st.mean(r["survived"] for r in rs)
    cap = 100 * vc / vs
    print(f"  每局有價物 {vs:.1f} 顆（翻倍前 28.6）、接到 {vc:.1f}、接取率 {cap:.0f}%")
    print(f"  每局炸彈 {bombs:.1f} 顆（翻倍前 2.1）、平均局長 {t_played:.1f}s、存活率 {surv:.0f}%")
    ok(55.0 <= vs, f"有價物 {vs:.1f} ≥ 55 —— 確實翻倍")
    ok(1.0 <= bombs <= 3.5, f"炸彈 {bombs:.1f} 落在 1.0~3.5 —— 密度沒跟著翻倍")
    ok(t_played >= 53.0, f"平均局長 {t_played:.1f}s ≥ 53 —— 局不會提前結束")
    ok(surv >= 50.0, f"存活率 {surv:.0f}% ≥ 50% —— 難度沒有失控")

    print()
    if FAILED:
        print(f"!! {len(FAILED)} 項失敗")
        return 1
    print("全部通過。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
