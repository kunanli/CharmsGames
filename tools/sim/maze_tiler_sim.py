#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""maze_tiler_sim.py — 驗證 maze_tiler.gd 的「邏輯迷宮 → TileMap 美術」拼接規則。

與其他 sim 不同，這支不跑平衡，只做規則正確性檢查（純邏輯，無隨機數）：
  1. 解碼 tile_maze.tscn 示範地圖的 tile_data，確認每格都對到 8 個已知 tile。
  2. 用本檔的拼接規則（＝maze_tiler.gd 的副本）對示範地圖做回還原：
     端點／頂部／底部必須逐格一致，中間1／中間2 視為等價。
  3. 對企劃給的 ASCII 範例地圖與遊戲實際迷宮（maze.gd 的副本）跑規則，
     確認零 missing、轉角全部落在 MazeCorner 層。
  4. 邊界案例：孤立 1×1 牆塊必須被回報為 missing。

改了 games/seeker/maze_tiler.gd 的規則要同步改這裡（見 tools/sim/README.md 的同步紀律）。
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TSCN = ROOT / "assets/seeker/Map/TileMap/tile_maze.tscn"

# ── maze_tiler.gd 的常數副本 ──────────────────────────────
T_H_LEFT, T_H_MID1, T_H_MID2, T_H_RIGHT = (0, 0), (1, 0), (2, 0), (3, 0)
T_V_TOP, T_V_MID1, T_V_MID2, T_V_BOTTOM = (0, 1), (0, 2), (0, 3), (0, 4)
T_CORNER = T_V_MID1
KNOWN = {T_H_LEFT, T_H_MID1, T_H_MID2, T_H_RIGHT,
         T_V_TOP, T_V_MID1, T_V_MID2, T_V_BOTTOM}

TILE_NAME = {
    T_H_LEFT: "橫向左端", T_H_MID1: "橫向中1", T_H_MID2: "橫向中2",
    T_H_RIGHT: "橫向右端", T_V_TOP: "縱向頂部", T_V_MID1: "縱向中1",
    T_V_MID2: "縱向中2", T_V_BOTTOM: "縱向底部",
}

# maze.gd 的常數副本（2026-09-02，改了 .gd 要一起改）
COLS, ROWS = 22, 14
BLOCKS = [(3, 2, 3, 2), (10, 2, 2, 2), (13, 2, 4, 2), (3, 6, 4, 2),
          (19, 4, 2, 2), (16, 6, 2, 2), (7, 9, 3, 1), (13, 9, 3, 1)]
LOGO_TOP_LEFT, LOGO_SIZE = (8, 5), (5, 2)

FAILURES = []


def check(cond, msg):
    if cond:
        print(f"  PASS  {msg}")
    else:
        print(f"  FAIL  {msg}")
        FAILURES.append(msg)


# ── maze_tiler.gd 的規則副本 ──────────────────────────────

def classify(walls, x, y):
    """回傳 (base_tile, corner_overlay: bool) 或 (None, False) 代表 missing。"""
    l = (x - 1, y) in walls
    r = (x + 1, y) in walls
    u = (x, y - 1) in walls
    d = (x, y + 1) in walls
    if not u and not d:                       # 橫向帶
        if not l and not r:
            return None, False                # 孤立 1×1
        if r and not l:
            return T_H_LEFT, False
        if l and not r:
            return T_H_RIGHT, False
        return (T_H_MID1 if x % 2 == 0 else T_H_MID2), False
    if not l and not r:                       # 縱向帶
        if d and not u:
            return T_V_TOP, False
        if u and not d:
            return T_V_BOTTOM, False
        return (T_V_MID1 if y % 2 == 0 else T_V_MID2), False
    # 轉角／T 形／十字
    if r and not l:
        base = T_H_LEFT
    elif l and not r:
        base = T_H_RIGHT
    else:
        base = T_H_MID1 if x % 2 == 0 else T_H_MID2
    return base, True


def build(walls, cols, rows):
    """回傳 {cell: (base, overlay)} 與 missing 清單。"""
    out, missing = {}, []
    for y in range(rows):
        for x in range(cols):
            if (x, y) not in walls:
                continue
            base, ov = classify(walls, x, y)
            if base is None:
                missing.append((x, y))
            else:
                out[(x, y)] = (base, ov)
    return out, missing


def parse_ascii(text):
    walls, cols, rows = set(), 0, 0
    for line in text.rstrip("\n").split("\n"):
        line = line.rstrip()
        cols = max(cols, len(line))
        for x, ch in enumerate(line):
            if ch == "#":
                walls.add((x, rows))
        rows += 1
    return walls, cols, rows


# ── tile_maze.tscn 的 tile_data 解碼（Godot format 2，每格 3 個 int32）──

def decode_tscn():
    raw = TSCN.read_text(encoding="utf-8")
    m = re.search(r"tile_data = PackedInt32Array\(([^)]*)\)", raw)
    vals = [int(v) for v in m.group(1).split(",")]
    assert len(vals) % 3 == 0, "tile_data 不是 3 的倍數"

    def s16(v):
        v &= 0xFFFF
        return v - 0x10000 if v & 0x8000 else v

    cells = {}
    for i in range(0, len(vals), 3):
        c, src, alt = vals[i], vals[i + 1], vals[i + 2]
        x, y = s16(c & 0xFFFF), s16((c >> 16) & 0xFFFF)
        ax, ay = s16((src >> 16) & 0xFFFF), s16(alt & 0xFFFF)
        assert src & 0xFFFF == 0 and alt >> 16 == 0, "示範地圖不該有非 0 source／alternative"
        cells[(x, y)] = (ax, ay)
    return cells


SYM = {T_H_LEFT: "L", T_H_RIGHT: "R", T_H_MID1: "A", T_H_MID2: "B",
       T_V_TOP: "T", T_V_BOTTOM: "M", T_V_MID1: "C", T_V_MID2: "D"}


def print_grid(result, missing, cols, rows, title):
    print(f"\n  {title}")
    for y in range(rows):
        row = ""
        for x in range(cols):
            if (x, y) in missing:
                row += " ? "
            elif (x, y) in result:
                base, ov = result[(x, y)]
                sym = SYM[base]
                if ov:
                    sym = sym.lower()        # 小寫 = MazeCorner 有疊加
                row += f"[{sym}]"
            else:
                row += " . "
        print(f"    y={y:2d} {row}")
    print("    圖例：L/R=橫向左/右端 A/B=橫向中1/中2 T/M=縱向頂/底 C/D=縱向中1/中2，"
          "小寫＝該格另在 MazeCorner 疊了縱向中1（轉角/T形/十字）")


def mid_eq(a, b):
    """中間1／中間2 視為等價（示範地圖與規則的交替相位可以不同）。"""
    h_mids = {T_H_MID1, T_H_MID2}
    v_mids = {T_V_MID1, T_V_MID2}
    return a == b or (a in h_mids and b in h_mids) or (a in v_mids and b in v_mids)


def main():
    print("== 1. 解碼 tile_maze.tscn 示範地圖 ==")
    demo = decode_tscn()
    check(len(demo) == 51, f"示範地圖共 51 格（實際 {len(demo)}）")
    check(all(t in KNOWN for t in demo.values()), "每格都對到 8 個已知 tile")
    bad = {c: t for c, t in demo.items() if t not in KNOWN}
    check(not bad, f"無未知 tile {bad if bad else ''}")

    print("\n== 2. 規則回還原：對示範地圖的牆格重推 tile ==")
    walls = set(demo.keys())
    cols = max(x for x, _ in demo) + 1
    rows = max(y for _, y in demo) + 1
    result, missing = build(walls, cols, rows)
    check(not missing, f"示範地圖無 missing（{missing if missing else ''}）")
    mismatch = [(c, demo[c], result.get(c)) for c in demo
                if c not in result
                or not mid_eq(demo[c], result[c][0])
                or result[c][1]]
    check(not mismatch, f"51 格全部一致（端點逐格、中間1/2 等價）{mismatch[:5] if mismatch else ''}")
    check(not any(ov for _, ov in result.values()),
          "示範地圖沒有轉角 → MazeCorner 層應為空")

    print("\n== 3. 企劃 ASCII 範例地圖 ==")
    example = """\
########################
#..........#...........#
#..######..#...........#
#......................#
#..........####........#
########################
"""
    walls, cols, rows = parse_ascii(example)
    result, missing = build(walls, cols, rows)
    check(not missing, f"範例地圖無 missing（{missing if missing else ''}）")
    corners = [c for c, (_, ov) in result.items() if ov]
    # 外框 4 角 + (11,0) 吊牆與外框相接的 T 形 + 貼框塊 y4 整排 4 格 + 外框底對應 4 格
    check((11, 0) in corners, "(11,0) 吊牆接外框處是 T 形交接（橫向中間+疊加）")
    print(f"  轉角疊加格：{sorted(corners)}")
    check(len(corners) == 13, "範例地圖 13 個轉角疊加格（外框4 + T形1 + 貼框塊8）")
    print_grid(result, missing, cols, rows, "範例地圖鋪設結果")

    print("\n== 4. 遊戲實際迷宮（maze.gd 副本：外框 + BLOCKS + 中央 Logo 牆）==")
    walls = set()
    for x in range(COLS):
        walls.add((x, 0))
        walls.add((x, ROWS - 1))
    for y in range(ROWS):
        walls.add((0, y))
        walls.add((COLS - 1, y))
    for bx, by, bw, bh in BLOCKS:
        for x in range(bx, bx + bw):
            for y in range(by, by + bh):
                walls.add((x, y))
    for x in range(LOGO_TOP_LEFT[0], LOGO_TOP_LEFT[0] + LOGO_SIZE[0]):
        for y in range(LOGO_TOP_LEFT[1], LOGO_TOP_LEFT[1] + LOGO_SIZE[1]):
            walls.add((x, y))
    result, missing = build(walls, COLS, ROWS)
    check(not missing, f"遊戲迷宮無 missing（{missing if missing else ''}）")
    corners = [c for c, (_, ov) in result.items() if ov]
    # 轉角格＝「橫向與縱向都延續」的格：
    #   實心矩形（寬高都 ≥2）的每一格都是；3×1 單行塊整條是純橫向帶，一個都沒有；
    #   外框環上，內側鄰格是牆的格也是（例如 (19,4,2,2) 貼著右外框 → 外框 x21 的
    #   y4/y5 兩格變成交接格；外框 4 個角本身也算）。
    exp = 0
    for bx, by, bw, bh in BLOCKS + [LOGO_TOP_LEFT + LOGO_SIZE]:
        if bw >= 2 and bh >= 2:
            exp += bw * bh
    for x in range(COLS):    # 外框頂/底：內側鄰格是牆的格（含 4 個框角）
        if (x, 1) in walls:
            exp += 1
        if (x, ROWS - 2) in walls:
            exp += 1
    for y in range(1, ROWS - 1):    # 外框左/右：內側鄰格是牆的格
        if (1, y) in walls:
            exp += 1
        if (COLS - 2, y) in walls:
            exp += 1
    check(len(corners) == exp, f"轉角疊加格數 = {exp}（實際 {len(corners)}）")
    for c in [(7, 9), (8, 9), (9, 9)]:
        base, ov = result[c]
        check(not ov and base in (T_H_LEFT, T_H_MID1, T_H_MID2, T_H_RIGHT),
              f"3×1 障礙塊 {c} 是純橫向帶（{TILE_NAME[base]}），無轉角疊加")
    print_grid(result, missing, COLS, ROWS, "遊戲迷宮鋪設結果")

    print("\n== 5. 邊界案例 ==")
    case = """\
#####
#...#
#.#.#
#...#
#####
"""
    walls, cols, rows = parse_ascii(case)
    result, missing = build(walls, cols, rows)
    check(missing == [(2, 2)], f"孤立 1×1 牆塊回報 missing：{missing}")
    # T 形與十字
    case2 = """\
..#..
..#..
#####
..#..
..#..
"""
    walls, cols, rows = parse_ascii(case2)
    result, missing = build(walls, cols, rows)
    check(not missing, "十字沒有 missing（用 橫向中間+縱向中1疊加 表現）")
    base, ov = result[(2, 2)]
    check(base in (T_H_MID1, T_H_MID2) and ov, "十字中心 = 橫向中間 + Corner 疊加")
    base, ov = result[(2, 0)]
    check(base == T_V_TOP and not ov, "十字上端 = 縱向頂部（死路端點）")

    print()
    if FAILURES:
        print(f"共 {len(FAILURES)} 項 FAIL")
        sys.exit(1)
    print("全部 PASS —— 拼接規則與 maze_tiler.gd 一致")


if __name__ == "__main__":
    main()
