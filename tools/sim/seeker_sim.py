#!/usr/bin/env python3
"""CharmsSeeker：迷宮結構、暗影猫 AI、M4 石化狀態機、難度。

執行： python3 tools/sim/seeker_sim.py

常數必須與 games/seeker/*.gd 同步（見本目錄 README 的「同步紀律」）。
"""
import math
import random
import statistics as st

# ── 與 games/seeker/maze.gd 同步 ───────────────────────────
LEVEL_SIZE = (330.0, 210.0)
COLS, ROWS = 22, 14
CELL_SIZE = (LEVEL_SIZE[0] / COLS, LEVEL_SIZE[1] / ROWS)
ORIGIN = (75.0, 46.0)
BLOCKS = [
    (3, 2, 3, 2), (10, 2, 2, 2), (13, 2, 4, 2),
    (3, 6, 4, 2), (19, 4, 2, 2), (16, 6, 2, 2),
    (7, 9, 3, 1), (13, 9, 3, 1),
]
PLAYER_START = (10, 10)
LOGO_CELL = (10, 6)
LOGO_SIZE = (5, 2)
LOGO_TOP_LEFT = (LOGO_CELL[0] - LOGO_SIZE[0] // 2, LOGO_CELL[1] - LOGO_SIZE[1] // 2)
LOGO_WALL = [(x, y) for x in range(LOGO_TOP_LEFT[0], LOGO_TOP_LEFT[0] + LOGO_SIZE[0])
             for y in range(LOGO_TOP_LEFT[1], LOGO_TOP_LEFT[1] + LOGO_SIZE[1])]
MOON_CELLS = [(1, 1), (COLS - 2, 1), (1, ROWS - 2), (COLS - 2, ROWS - 2)]

# ── 與 games/seeker/player.gd / cat.gd / seeker.gd 同步 ────
PSPEED = 72.0
CATCH_DIST = 9.0
AMBUSH_LEAD, WANDER_RETARGET, WANDER_POUNCE = 4, 2.5, 6
CHASER, AMBUSHER, WANDERER = 0, 1, 2
CAT_SPEED = {CHASER: 60.0, AMBUSHER: 66.0, WANDERER: 54.0}
CAT_HOME = {CHASER: (7, 5), AMBUSHER: (13, 5), WANDERER: (11, 7)}
CAT_DELAY = {CHASER: 0.0, AMBUSHER: 2.5, WANDERER: 5.0}
SCORE_BREAK = [50, 100, 200, 400]
PETRIFY_TIME, PETRIFY_WARN, REVIVE_TIME, REVIVE_GRACE = 8.0, 2.0, 5.0, 1.0
MOON_STOCK_MAX = 2

UP, LEFT, DOWN, RIGHT = (0, -1), (-1, 0), (0, 1), (1, 0)
ORDER = [UP, LEFT, DOWN, RIGHT]        # 經典小精靈優先級：上→左→下→右
DT = 1 / 60

walls = set()
for x in range(COLS):
    walls.add((x, 0)); walls.add((x, ROWS - 1))
for y in range(ROWS):
    walls.add((0, y)); walls.add((COLS - 1, y))
for bx, by, bw, bh in BLOCKS:
    for x in range(bx, bx + bw):
        for y in range(by, by + bh):
            walls.add((x, y))
for c in LOGO_WALL:
    walls.add(c)   # 中央 Logo 牆 5×2 格（maze.gd 的 _build_walls）

OPEN = [(x, y) for x in range(1, COLS - 1) for y in range(1, ROWS - 1)
        if (x, y) not in walls]


def is_open(c):
    return 0 <= c[0] < COLS and 0 <= c[1] < ROWS and c not in walls


def cell_center(c):
    return (
        ORIGIN[0] + c[0] * CELL_SIZE[0] + CELL_SIZE[0] / 2,
        ORIGIN[1] + c[1] * CELL_SIZE[1] + CELL_SIZE[1] / 2,
    )


FAILED = []


def ok(cond, msg):
    print(("  PASS  " if cond else "  FAIL  ") + msg)
    if not cond:
        FAILED.append(msg)


# ── 暗影猫 ─────────────────────────────────────────────────
ACTIVE, PETRIFIED, BROKEN = range(3)


class Cat:
    def __init__(self, kind, rng):
        self.kind = kind
        self.home = CAT_HOME[kind]
        self.speed = CAT_SPEED[kind]
        self.delay = CAT_DELAY[kind]
        self.rng = rng
        self.setup()

    def setup(self):
        self.cell = self.home
        self.pos = list(cell_center(self.home))
        self.dir = (0, 0)
        self.target = self.home
        self.hold = self.delay
        self.wander = self.home
        self.wtimer = 0.0
        self.status = ACTIVE
        self.revive = 0.0

    def petrify(self):
        if self.status != BROKEN:
            self.status = PETRIFIED
            self.dir = (0, 0)

    def unpetrify(self):
        if self.status == PETRIFIED:
            self.status = ACTIVE

    def shatter(self):
        self.status = BROKEN
        self.revive = REVIVE_TIME
        self.dir = (0, 0)

    def dangerous(self):
        return self.status == ACTIVE and self.hold <= 0.0

    def breakable(self):
        return self.status == PETRIFIED

    def update_target(self, pcell, pdir, dt):
        if self.kind == CHASER:
            self.target = pcell
        elif self.kind == AMBUSHER:
            raw = (pcell[0] + pdir[0] * AMBUSH_LEAD, pcell[1] + pdir[1] * AMBUSH_LEAD)
            self.target = (max(1, min(raw[0], COLS - 2)), max(1, min(raw[1], ROWS - 2)))
        else:
            self.wtimer -= dt
            if self.wtimer <= 0.0 or self.wander == self.cell:
                self.wander = self.rng.choice(OPEN)
                self.wtimer = WANDER_RETARGET
            near = abs(self.cell[0] - pcell[0]) + abs(self.cell[1] - pcell[1])
            self.target = pcell if near <= WANDER_POUNCE else self.wander

    def choose_dir(self):
        opts = []
        for d in ORDER:
            if self.dir != (0, 0) and d == (-self.dir[0], -self.dir[1]):
                continue                                  # 不准回頭
            if is_open((self.cell[0] + d[0], self.cell[1] + d[1])):
                opts.append(d)
        if not opts:
            back = (-self.dir[0], -self.dir[1])
            if self.dir != (0, 0) and is_open((self.cell[0] + back[0], self.cell[1] + back[1])):
                return back                               # 死路才准回頭
            return (0, 0)
        best, bd = opts[0], math.inf
        for d in opts:
            n = (self.cell[0] + d[0], self.cell[1] + d[1])
            dist = (n[0] - self.target[0]) ** 2 + (n[1] - self.target[1]) ** 2
            if dist < bd:
                bd, best = dist, d
        return best

    def step(self, dt):
        if self.status == BROKEN:
            self.revive -= dt
            if self.revive <= 0.0:
                # 一律回到 ACTIVE，並給 1 秒半透明待命（見 cat.gd 的 _revive 註解）
                self.cell = self.home
                self.pos = list(cell_center(self.home))
                self.dir = (0, 0)
                self.status = ACTIVE
                self.hold = REVIVE_GRACE
            return
        if self.status == PETRIFIED:
            return
        if self.hold > 0.0:
            self.hold -= dt
            return
        if self.dir == (0, 0):
            self.dir = self.choose_dir()
            if self.dir == (0, 0):
                return
        tgt = cell_center((self.cell[0] + self.dir[0], self.cell[1] + self.dir[1]))
        dx, dy = tgt[0] - self.pos[0], tgt[1] - self.pos[1]
        L = math.hypot(dx, dy)
        step = self.speed * dt
        if L <= step:
            self.pos = list(tgt)
            self.cell = (self.cell[0] + self.dir[0], self.cell[1] + self.dir[1])
            self.dir = self.choose_dir()
        else:
            self.pos[0] += dx / L * step
            self.pos[1] += dy / L * step


def structural():
    print("== 1. 迷宮結構 ==")
    # 減 1 顆玩家出生格；中央 Logo 牆是障礙，不在走道格裡（與 maze.gd 同步）
    beans = len(OPEN) - len([c for c in MOON_CELLS if is_open(c)]) - 1
    print(f"  走道格 {len(OPEN)}，鋪完後珍珠 {beans} 顆")
    for name, c in [("PLAYER_START", PLAYER_START)] + \
                   [(f"CAT {k}", CAT_HOME[k]) for k in (CHASER, AMBUSHER, WANDERER)]:
        ok(is_open(c), f"{name} {c} 是通路")
    ok(all(not is_open(c) for c in LOGO_WALL),
       f"中央 Logo 牆 {LOGO_SIZE[0]}×{LOGO_SIZE[1]} 格（{LOGO_TOP_LEFT} 起）全是障礙")
    ok(all(is_open(c) for c in MOON_CELLS), "四角月光能量都在通路上")
    # LOGO 牆與所有障礙塊至少隔一格（Chebyshev ≥ 2），守 BLOCKS 的生成規則
    sets = [[(x, y) for x in range(bx, bx + bw) for y in range(by, by + bh)]
            for bx, by, bw, bh in BLOCKS] + [LOGO_WALL]
    gap_ok = True
    for i in range(len(sets)):
        for j in range(i + 1, len(sets)):
            d = min(max(abs(x1 - x2), abs(y1 - y2)) for x1, y1 in sets[i] for x2, y2 in sets[j])
            if d < 2:
                gap_ok = False
                print(f"    間距不足：{sets[i]} 與 {sets[j]} 只隔 {d} 格")
    ok(gap_ok, "所有障礙塊（含中央 Logo 牆）之間至少隔 1 格")
    seen, stack = {OPEN[0]}, [OPEN[0]]
    while stack:
        x, y = stack.pop()
        for d in ORDER:
            n = (x + d[0], y + d[1])
            if is_open(n) and n not in seen:
                seen.add(n)
                stack.append(n)
    ok(len(seen) == len(OPEN), "所有走道連通（沒有進不去的區域）")


def no_safe_spot():
    print("\n== 2. 沒有安全點（貪婪 AI 配靜態目標會不會卡進 limit cycle）==")
    for kind, label in [(CHASER, "直追"), (AMBUSHER, "預判")]:
        never = []
        for pc in OPEN:
            rng = random.Random(1)
            c = Cat(kind, rng)
            c.hold = 0.0
            ppos = cell_center(pc)
            hit = False
            for _ in range(int(20 / DT)):
                c.update_target(pc, (0, 0), DT)
                c.step(DT)
                if math.dist(ppos, c.pos) < CATCH_DIST:
                    hit = True
                    break
            if not hit:
                never.append(pc)
        ok(not never,
           f"{label}貓從全部 {len(OPEN)} 個站立點都能在 20 秒內抓到靜止的露娜"
           f"{'' if not never else ' —— 失敗於 ' + str(never[:5])}")


def m4_state_machine():
    print("\n== 3. M4 石化狀態機 ==")
    rng = random.Random(0)
    cats = [Cat(k, rng) for k in (CHASER, AMBUSHER, WANDERER)]
    for c in cats:
        c.hold = 0.0

    stock = 0
    for _ in range(4):
        stock = min(stock + 1, MOON_STOCK_MAX)
    ok(stock == MOON_STOCK_MAX, f"四角四顆但同時最多囤 {MOON_STOCK_MAX} 個")

    for c in cats:
        c.petrify()
    ok(all(c.status == PETRIFIED for c in cats), "啟動後全部石化")

    score, chain = 0, 0
    for c in cats:
        score += SCORE_BREAK[min(chain, 3)]
        chain += 1
        c.shatter()
    ok(score == 350, f"三隻連續擊碎 = 50+100+200 = {score}")

    # 中央蹲點刷分是否已封住
    rng = random.Random(2)
    cats = [Cat(k, rng) for k in (CHASER, AMBUSHER, WANDERER)]
    for c in cats:
        c.hold = 0.0
        c.petrify()
    pet, score, chain, breaks, t = PETRIFY_TIME, 0, 0, 0, 0.0
    while t < PETRIFY_TIME:
        for c in cats:
            if c.breakable():
                score += SCORE_BREAK[min(chain, 3)]
                chain += 1
                breaks += 1
                c.shatter()
        pet -= DT
        if pet <= 0:
            for c in cats:
                c.unpetrify()
        for c in cats:
            c.step(DT)
        t += DT
    ok(breaks == 3 and score == 350,
       f"整段石化最多碎 {breaks} 次、共 {score} 分 —— 中央蹲點刷分已封住"
       f"（石化重生的話會是 1550）")

    # 重生時序
    rng = random.Random(3)
    c = Cat(CHASER, rng)
    c.hold = 0.0
    c.petrify()
    c.shatter()
    for _ in range(int(4.9 / DT)):
        c.step(DT)
    ok(c.status == BROKEN, "碎掉後 4.9 秒仍在 BROKEN")
    for _ in range(int(0.2 / DT)):
        c.step(DT)
    ok(c.status == ACTIVE and not c.dangerous(),
       "5 秒後重生為 ACTIVE，且有 1 秒半透明待命不會秒扣命")
    for _ in range(int(1.1 / DT)):
        c.step(DT)
    ok(c.dangerous(), "待命結束後恢復威脅")


def difficulty(rounds=30):
    print(f"\n== 4. 難度：會閃避的玩家（{rounds} 局）==")
    deaths_all, survived = [], 0
    for seed in range(rounds):
        rng = random.Random(seed)
        cats = [Cat(k, rng) for k in (CHASER, AMBUSHER, WANDERER)]
        pcell = PLAYER_START
        ppos = list(cell_center(pcell))
        pdir = (0, 0)
        lives, t, deaths = 3, 0.0, 0
        while t < 60.0 and lives > 0:
            t += DT
            at_c = (abs(ppos[0] - cell_center(pcell)[0]) < 1e-6 and
                    abs(ppos[1] - cell_center(pcell)[1]) < 1e-6)
            if pdir == (0, 0) or at_c:
                best, bs = None, -1
                for d in ORDER:
                    n = (pcell[0] + d[0], pcell[1] + d[1])
                    if not is_open(n):
                        continue
                    if pdir != (0, 0) and d == (-pdir[0], -pdir[1]):
                        continue
                    nc = cell_center(n)
                    s = min(math.dist(nc, c.pos) for c in cats)
                    if s > bs:
                        bs, best = s, d
                if best is None:
                    back = (-pdir[0], -pdir[1])
                    best = back if is_open((pcell[0] + back[0], pcell[1] + back[1])) else (0, 0)
                pdir = best
            if pdir != (0, 0):
                tgt = cell_center((pcell[0] + pdir[0], pcell[1] + pdir[1]))
                dx, dy = tgt[0] - ppos[0], tgt[1] - ppos[1]
                L = math.hypot(dx, dy)
                s = PSPEED * DT
                if L <= s:
                    ppos = list(tgt)
                    pcell = (pcell[0] + pdir[0], pcell[1] + pdir[1])
                else:
                    ppos[0] += dx / L * s
                    ppos[1] += dy / L * s
            for c in cats:
                c.update_target(pcell, pdir, DT)
                c.step(DT)
            for c in cats:
                if c.dangerous() and math.dist(ppos, c.pos) < CATCH_DIST:
                    lives -= 1
                    deaths += 1
                    pcell = PLAYER_START
                    ppos = list(cell_center(pcell))
                    pdir = (0, 0)
                    for k in cats:
                        k.setup()
                    t += 1.2 + 1.5          # DYING + READY
                    break
        deaths_all.append(deaths)
        if lives > 0:
            survived += 1
    print(f"  撐完 60 秒：{survived}/{rounds} 局")
    print(f"  平均死亡：{st.mean(deaths_all):.2f} 次/局")
    print("  （基準：M3c 三隻貓時為 0.63 次/局、30/30 撐完。M5 加貓後應在此重測）")


def bump_rate(rounds=30):
    print(f"\n== 5. 撞牆頻率（決定 kick 值會不會太吵）==")
    for style, label in [("normal", "一般走位"), ("wallhug", "故意一直頂牆")]:
        counts = []
        for seed in range(rounds):
            rng = random.Random(seed)
            cell, pos, d, want = PLAYER_START, list(cell_center(PLAYER_START)), (0, 0), (0, 0)
            bumps, t = 0, 0.0
            while t < 60.0:
                t += DT
                at_c = (abs(pos[0] - cell_center(cell)[0]) < 1e-6 and
                        abs(pos[1] - cell_center(cell)[1]) < 1e-6)
                if at_c or d == (0, 0):
                    opens = [k for k in ORDER if is_open((cell[0] + k[0], cell[1] + k[1]))]
                    if style == "wallhug":
                        blocked = [k for k in ORDER
                                   if not is_open((cell[0] + k[0], cell[1] + k[1]))]
                        want = (rng.choice(blocked) if blocked and rng.random() < 0.6
                                else (rng.choice(opens) if opens else (0, 0)))
                    else:
                        want = rng.choice(opens) if opens else (0, 0)
                if d == (0, 0):
                    if want != (0, 0) and is_open((cell[0] + want[0], cell[1] + want[1])):
                        d = want
                    else:
                        continue
                tgt = cell_center((cell[0] + d[0], cell[1] + d[1]))
                dx, dy = tgt[0] - pos[0], tgt[1] - pos[1]
                L = math.hypot(dx, dy)
                step = PSPEED * DT
                if L <= step:
                    pos = list(tgt)
                    cell = (cell[0] + d[0], cell[1] + d[1])
                    if want != (0, 0) and is_open((cell[0] + want[0], cell[1] + want[1])):
                        d = want
                    if not is_open((cell[0] + d[0], cell[1] + d[1])):
                        bumps += 1
                        d = (0, 0)
                else:
                    pos[0] += dx / L * step
                    pos[1] += dy / L * step
            counts.append(bumps)
        m = st.mean(counts)
        ok(m <= 30, f"{label}：{m:.1f} 次/分鐘（超過 30 就代表 kick 值太吵）")


def main():
    structural()
    no_safe_spot()
    m4_state_machine()
    difficulty()
    bump_rate()
    print()
    if FAILED:
        print(f"!! {len(FAILED)} 項失敗")
        return 1
    print("全部通過。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
