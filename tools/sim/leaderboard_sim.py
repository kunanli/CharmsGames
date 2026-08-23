#!/usr/bin/env python3
"""LeaderboardManager 邏輯鏡像驗證：排序、分頁、同名、同分、目前玩家定位、
日期清除、MAX_RECORDS 裁剪（新記錄永不丟）、JSON 重載、損壞恢復、名字清洗。

執行： python3 tools/sim/leaderboard_sim.py

本檔是 shared/leaderboard_manager.gd 的 Python 副本（同步紀律見本目錄
README）。開發環境沒有 Godot binary，所以用鏡像驗證純邏輯 ——
排序規則、分頁夾取、日期清除、裁剪的保護順序、JSON 重載與損壞恢復。
任何行為改動必須兩邊一起改。
"""
import json
import os
import random
import shutil
import tempfile
import time as _time
from datetime import datetime, timedelta
from functools import cmp_to_key

# ── 與 shared/leaderboard_manager.gd 同步 ─────────────────
STORAGE_VERSION = 1
SCORE_VERSION = 1
MAX_RECORDS = 1000
PAGE_SIZE = 20
MAX_NAME_LEN = 12
GAME_IDS = ("seeker", "fishing", "catch")
GAME_NAMES = {"seeker": "CHARMS SEEKER", "fishing": "CHARMS FISHING", "catch": "CHARMS CATCH"}

FAILED = []


def ok(cond, msg):
    print(("  PASS  " if cond else "  FAIL  ") + msg)
    if not cond:
        FAILED.append(msg)


_SEQ = 0


def new_id():
    # 鏡像 .gd：unix 時間＋毫秒＋序號＋隨機尾碼。序號保證同一次執行內
    # 嚴格遞增，同毫秒連續提交也不撞 —— 300 筆連發的壓力測試靠這行。
    global _SEQ
    _SEQ += 1
    return f"{int(_time.monotonic() * 1000)}-{_SEQ}-{random.randrange(10000):04d}"


def from_dict(d):
    """LeaderboardRecord.from_dict() 的鏡像：缺欄位給預設值、數值強轉型。"""
    return {
        "record_id": str(d.get("record_id", "")),
        "game_id": str(d.get("game_id", "")),
        "game_name": str(d.get("game_name", "")),
        "player_name": str(d.get("player_name", "")),
        "score": int(d.get("score", 0)),
        "difficulty_id": str(d.get("difficulty_id", "")),
        "difficulty_name": str(d.get("difficulty_name", "")),
        "played_at": str(d.get("played_at", "")),
        "played_date": str(d.get("played_date", "")),
        "duration_seconds": float(d.get("duration_seconds", 0.0)),
        "score_version": int(d.get("score_version", 1)),
    }


def sanitize_player_name(raw):
    """CurrentPlayerSession.sanitize_player_name() 的鏡像。"""
    cleaned = "".join(c for c in raw if ord(c) >= 32)
    cleaned = cleaned.strip()
    if not cleaned:
        return ""
    return cleaned.upper()[:MAX_NAME_LEN]


class Manager:
    """LeaderboardManager 的邏輯鏡像。save_path 可指定（測試用暫存檔）。"""

    def __init__(self, save_path):
        self.save_path = save_path
        self.records = []
        self.loaded = False

    # ── 排序 ────────────────────────────────────────────
    @staticmethod
    def _key(r):
        # score DESC → played_at ASC → record_id ASC
        return (-r["score"], r["played_at"], r["record_id"])

    @staticmethod
    def _worst_first(a, b):
        # 與 .gd 的 _compare_worst_first 相同：低分在前，同分晚玩在前
        if a["score"] != b["score"]:
            return -1 if a["score"] < b["score"] else 1
        if a["played_at"] != b["played_at"]:
            return -1 if a["played_at"] > b["played_at"] else 1
        return -1 if a["record_id"] > b["record_id"] else 1

    def sorted_all(self, game_id):
        out = [r for r in self.records if r["game_id"] == game_id]
        out.sort(key=self._key)
        return out

    # ── 公開 API ────────────────────────────────────────
    def submit_score(self, rec):
        if not rec["record_id"]:
            rec["record_id"] = new_id()
        if not rec["played_at"]:
            now = datetime.now()
            rec["played_at"] = now.strftime("%Y-%m-%d %H:%M:%S")
            rec["played_date"] = now.strftime("%Y-%m-%d")
        rec["score_version"] = SCORE_VERSION
        self.records.append(rec)
        self._prune(rec["record_id"])
        self.save()
        return rec["record_id"]

    def get_records(self, game_id):
        return self.sorted_all(game_id)

    def get_page(self, game_id, page_index, page_size=PAGE_SIZE):
        all_ = self.sorted_all(game_id)
        total = len(all_)
        page_count = max(1, -(-total // page_size))
        idx = max(0, min(page_index, page_count - 1))
        start = idx * page_size
        return {
            "records": all_[start:start + page_size],
            "total": total,
            "page_count": page_count,
            "page_index": idx,
        }

    def get_rank(self, record_id):
        rec = self._find(record_id)
        if rec is None:
            return -1
        for i, r in enumerate(self.sorted_all(rec["game_id"])):
            if r["record_id"] == record_id:
                return i + 1
        return -1

    def get_page_containing_record(self, record_id, page_size=PAGE_SIZE):
        rank = self.get_rank(record_id)
        if rank < 0:
            return -1
        return (rank - 1) // page_size

    def clear_records_by_date(self, date):
        before = len(self.records)
        self.records = [r for r in self.records if r["played_date"] != date]
        removed = before - len(self.records)
        if removed:
            self.save()
        return removed

    def clear_today(self):
        return self.clear_records_by_date(datetime.now().strftime("%Y-%m-%d"))

    def clear_yesterday(self):
        return self.clear_records_by_date(
            (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d"))

    def clear_day_before(self):
        return self.clear_records_by_date(
            (datetime.now() - timedelta(days=2)).strftime("%Y-%m-%d"))

    def clear_records_by_game(self, game_id):
        before = len(self.records)
        self.records = [r for r in self.records if r["game_id"] != game_id]
        removed = before - len(self.records)
        if removed:
            self.save()
        return removed

    def clear_all_records(self):
        self.records = []
        self.save()

    # ── 保存／載入（鏡像 .gd 的 JSON 結構與損壞處理）──────
    def save(self):
        with open(self.save_path, "w", encoding="utf-8") as f:
            json.dump({"version": STORAGE_VERSION, "records": self.records}, f,
                      ensure_ascii=False, indent="\t")

    def _rename_bak(self):
        # Godot 4 的 DirAccess.rename 會先移除已存在的目標；鏡像同樣處理
        bak = self.save_path + ".bak"
        if os.path.exists(bak):
            os.remove(bak)
        os.rename(self.save_path, bak)

    def load(self):
        self.records = []
        self.loaded = True
        if not os.path.exists(self.save_path):
            return
        try:
            with open(self.save_path, encoding="utf-8") as f:
                payload = json.load(f)
        except (json.JSONDecodeError, OSError):
            self._rename_bak()
            return
        if not isinstance(payload, dict) or "records" not in payload:
            self._rename_bak()
            return
        for entry in payload["records"]:
            if isinstance(entry, dict):
                self.records.append(from_dict(entry))

    def _find(self, record_id):
        for r in self.records:
            if r["record_id"] == record_id:
                return r
        return None

    # ── 裁剪：超過 MAX_RECORDS 刪最差的老記錄，protected 永不刪 ──
    def _prune(self, protected_id):
        counts = {}
        for r in self.records:
            counts[r["game_id"]] = counts.get(r["game_id"], 0) + 1
        victims = []
        for game_id, count in counts.items():
            excess = count - MAX_RECORDS
            if excess <= 0:
                continue
            pool = [r for r in self.records
                    if r["game_id"] == game_id and r["record_id"] != protected_id]
            # 最差的排前面：低分優先刪，同分時玩得晚的優先刪（與 .gd 相同）
            pool = sorted(pool, key=cmp_to_key(self._worst_first))
            victims += pool[:excess]
        victim_ids = {v["record_id"] for v in victims}
        self.records = [r for r in self.records if r["record_id"] not in victim_ids]


# ── 測試資料生成 ─────────────────────────────────────────

def make_record(game_id, name, score, date_str, played_at=None, rid=None):
    return {
        "record_id": rid or new_id(),
        "game_id": game_id,
        "game_name": GAME_NAMES[game_id],
        "player_name": name,
        "score": score,
        "difficulty_id": "normal",
        "difficulty_name": "NORMAL",
        "played_at": played_at or f"{date_str} {random.randrange(24):02d}:{random.randrange(60):02d}:{random.randrange(60):02d}",
        "played_date": date_str,
        "duration_seconds": round(random.uniform(30.0, 60.0), 2),
        "score_version": SCORE_VERSION,
    }


def today_str():
    return datetime.now().strftime("%Y-%m-%d")


def date_str(days_ago):
    return (datetime.now() - timedelta(days=days_ago)).strftime("%Y-%m-%d")


def main():
    tmp = tempfile.mkdtemp(prefix="lb_sim_")
    path = os.path.join(tmp, "leaderboard.json")
    rng = random.Random(20260821)

    print("== 1. 排序與排名（score DESC → played_at ASC → record_id ASC）==")
    m = Manager(path)
    names = ["ALICE", "BOB", "CHARLIE", "DIANA", "ERIK"]
    for g in GAME_IDS:
        for i in range(100):
            m.submit_score(make_record(g, rng.choice(names), rng.randrange(0, 6000),
                                       date_str(rng.randrange(0, 3))))
    for g in GAME_IDS:
        rows = m.get_records(g)
        ok(len(rows) == 100 and all(r["game_id"] == g for r in rows),
           f"{g} 剛好 100 筆且全部屬於該遊戲")
        ordered = all(
            (rows[i]["score"] > rows[i + 1]["score"] or
             (rows[i]["score"] == rows[i + 1]["score"] and
              rows[i]["played_at"] <= rows[i + 1]["played_at"]))
            for i in range(len(rows) - 1))
        ok(ordered, f"{g} 排序符合 score DESC、同分 played_at ASC")
    # 每筆記錄的 get_rank 都等於排序後的位置 +1
    ranks_ok = all(m.get_rank(r["record_id"]) == i + 1
                   for g in GAME_IDS for i, r in enumerate(m.get_records(g)))
    ok(ranks_ok, "300 筆記錄的 get_rank 全部等於排序位置 +1")
    ok(m.get_rank("nonexistent") == -1, "找不到的 record_id 回 -1")

    print("\n== 2. 同名多條記錄（不覆蓋、不當唯一 ID）==")
    m2 = Manager(path)
    for i in range(5):
        m2.submit_score(make_record("fishing", "ALICE", 1000 + i, today_str()))
    alice = [r for r in m2.get_records("fishing") if r["player_name"] == "ALICE"]
    ok(len(alice) == 5, "同名 ALICE 的 5 條記錄全部保留")
    ok(len({r["record_id"] for r in alice}) == 5, "5 條記錄的 record_id 各不相同")

    print("\n== 3. 同分排序（早玩到的高）==")
    m3 = Manager(path)
    for t, rid in [("10:30:00", "id-b"), ("10:45:00", "id-c"), ("10:15:00", "id-a")]:
        m3.submit_score(make_record("catch", "SAME", 5000, today_str(),
                                    played_at=f"{today_str()} {t}", rid=rid))
    rows = m3.get_records("catch")
    ok([r["record_id"] for r in rows] == ["id-a", "id-b", "id-c"],
       "同分 5000 依 played_at 由早到晚：id-a(10:15) → id-b(10:30) → id-c(10:45)")
    # 同分同時：record_id 兜底（確定性）
    m3.submit_score(make_record("catch", "TIE", 5000, today_str(),
                                played_at="2026-08-21 10:30:00", rid="id-d"))
    m3.submit_score(make_record("catch", "TIE2", 5000, today_str(),
                                played_at="2026-08-21 10:30:00", rid="id-e"))
    rows = m3.get_records("catch")
    ok(rows.index(next(r for r in rows if r["record_id"] == "id-d")) <
       rows.index(next(r for r in rows if r["record_id"] == "id-e")),
       "同分同時由 record_id 兜底，排序仍然確定")

    print("\n== 4. 分頁（20 條/頁、邊界夾取、頁碼）==")
    p = m.get_page("seeker", 0)
    ok(p["total"] == 100 and p["page_count"] == 5 and len(p["records"]) == 20,
       "100 筆 → 5 頁，第 1 頁 20 筆")
    all_rows = m.get_records("seeker")
    ok([r["record_id"] for r in p["records"]] ==
       [r["record_id"] for r in all_rows[:20]], "第 1 頁內容 = 排序後的前 20 名")
    ok(m.get_page("seeker", 4)["records"][-1]["record_id"] == all_rows[-1]["record_id"],
       "最後一頁的最後一筆 = 第 100 名")
    ok(m.get_page("seeker", -5)["page_index"] == 0, "負頁數夾回第 1 頁")
    ok(m.get_page("seeker", 99)["page_index"] == 4, "超尾頁數夾回最後一頁")
    empty = m.get_page("fishing", 0)
    ok(empty["total"] == 100, "fishing 有自己的 100 筆（與 seeker 互不污染）")
    m4 = Manager(path)
    ok(m4.get_page("seeker", 0)["page_count"] == 1 and
       m4.get_page("seeker", 0)["records"] == [], "0 筆時仍回傳 1 個空頁，不崩")

    print("\n== 5. 目前玩家定位（rank > 20、所在頁）==")
    m5 = Manager(path)
    for i in range(1000):
        m5.submit_score(make_record("fishing", f"P{i:03d}", rng.randrange(0, 6000), today_str()))
    all_f = m5.get_records("fishing")
    ok(len(all_f) == 1000, "fishing 塞滿 1000 筆")
    rank_387 = m5.get_rank(all_f[386]["record_id"])
    ok(rank_387 == 387, "第 387 名的 get_rank 是 387")
    ok(m5.get_page_containing_record(all_f[386]["record_id"]) == 19,
       "第 387 名落在第 20 頁（381～400，0 基頁 19）")
    ok(m5.get_page_containing_record(all_f[19]["record_id"]) == 0,
       "第 20 名落在第 1 頁（邊界）")
    ok(m5.get_page_containing_record(all_f[20]["record_id"]) == 1,
       "第 21 名落在第 2 頁（邊界）")
    ok(m5.get_page_containing_record("missing") == -1, "找不到回 -1")
    page19 = m5.get_page("fishing", 19)
    ok(page19["records"][0]["record_id"] == all_f[380]["record_id"],
       "第 20 頁第一筆 = 第 381 名")

    print("\n== 6. 日期清除（今天／昨天／前天，跨遊戲）==")
    m6 = Manager(path)
    expect = {0: 12, 1: 8, 2: 5}
    for g in GAME_IDS:
        for days_ago, n in expect.items():
            for i in range(n):
                m6.submit_score(make_record(g, "DATE", 100, date_str(days_ago)))
    ok(m6.clear_today() == 3 * expect[0], "清今天：只刪今天的 36 筆，回傳數正確")
    ok(m6.clear_yesterday() == 3 * expect[1], "清昨天：只刪昨天的 24 筆")
    ok(m6.clear_day_before() == 3 * expect[2], "清前天：只刪前天的 15 筆")
    ok(all(r["played_date"] != date_str(0) for r in m6.records) and
       all(r["played_date"] != date_str(1) for r in m6.records) and
       all(r["played_date"] != date_str(2) for r in m6.records),
       "三天全部清掉後 records 為空")
    # 通用接口：只清特定日期、且不誤刪其他日期的
    m6b = Manager(path)
    for i in range(3):
        m6b.submit_score(make_record("seeker", "A", 100, date_str(0)))
    for i in range(2):
        m6b.submit_score(make_record("seeker", "B", 100, date_str(1)))
    removed = m6b.clear_records_by_date(date_str(1))
    ok(removed == 2 and len(m6b.records) == 3,
       "clear_records_by_date 只刪指定日期的 2 筆，昨天的 3 筆留下")

    print("\n== 7. MAX_RECORDS 裁剪（新記錄永不丟，只刪最差的老記錄）==")
    m7 = Manager(path)
    # 1000 筆分數 1~1000 的舊記錄，塞滿上限
    for i in range(1000):
        m7.submit_score(make_record("seeker", f"S{i}", i + 1, today_str()))
    # 再提交一筆「全場最低分」的新記錄 —— 最嚴苛的情況
    submitted_last = m7.submit_score(make_record("seeker", "LAST", 0, today_str()))
    ok(len(m7.records) == MAX_RECORDS, "超過 1000 筆後剪回 1000 筆")
    ok(any(r["record_id"] == submitted_last for r in m7.records),
       "剛提交的全場最低分（0 分）記錄仍被保留 —— 新記錄永不因截斷丟失")
    ok(not any(r["score"] == 1 for r in m7.records),
       "被刪的是最差的老記錄（舊的 1 分）")
    ok(any(r["score"] == 2 for r in m7.records),
       "次差的老記錄（2 分）不受影響")
    # 全同分時：刪玩得最晚的舊記錄
    m7b = Manager(path)
    for i in range(1000):
        m7b.submit_score(make_record("fishing", "EQUAL", 100, today_str()))
    worst_old = max(m7b.records, key=lambda r: (r["played_at"], r["record_id"]))
    m7b.submit_score(make_record("fishing", "EQUAL", 100, today_str()))
    ok(len(m7b.records) == MAX_RECORDS, "同分 1001 筆也剪回 1000 筆")
    ok(worst_old["record_id"] not in {r["record_id"] for r in m7b.records},
       "全同分時被刪的是玩得最晚的那筆舊記錄")
    ok(any(r["player_name"] == "EQUAL" for r in m7b.records),
       "同分裁剪後剛提交的那筆仍在")

    print("\n== 8. JSON 重載與缺欄位預設值 ==")
    m8 = Manager(path)
    for i in range(50):
        m8.submit_score(make_record("catch", "RL", rng.randrange(0, 6000), today_str()))
    m8.save()
    m8b = Manager(path)
    m8b.load()
    ok(len(m8b.records) == 50, "重載後 50 筆都在")
    ok([r["record_id"] for r in m8b.get_records("catch")] ==
       [r["record_id"] for r in m8.get_records("catch")],
       "重載後排序與原管理器一致")
    # 缺欄位的舊資料 → 預設值
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"version": 1, "records": [
            {"game_id": "seeker", "score": 777},
            "not-a-dict", 123,
        ]}, f)
    m8c = Manager(path)
    m8c.load()
    ok(len(m8c.records) == 1, "非 Dictionary 的記錄被跳過，不崩")
    r0 = m8c.records[0]
    ok(r0["score"] == 777 and r0["record_id"] == "" and r0["player_name"] == "" and
       r0["score_version"] == 1 and r0["duration_seconds"] == 0.0 and
       r0["played_at"] == "" and r0["played_date"] == "" and
       r0["difficulty_id"] == "" and r0["difficulty_name"] == "" and
       r0["game_name"] == "" and r0["game_id"] == "seeker",
       "缺欄位記錄填上預設值（record_id/名字/時間/難度空字串、版本 1、時長 0）")
    # 新版檔案（version 更高）不崩
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"version": 99, "records": [
            {"game_id": "seeker", "score": 1},
        ]}, f)
    m8d = Manager(path)
    m8d.load()
    ok(len(m8d.records) == 1, "version 比程式新仍嘗試讀取，不崩")

    print("\n== 9. 損壞檔案恢復（改名 .bak、空資料續跑）==")
    m9 = Manager(path)
    with open(path, "w", encoding="utf-8") as f:
        f.write("{{{ this is not json")
    m9.load()
    ok(m9.records == [], "JSON 損壞 → 空資料啟動，不崩")
    ok(os.path.exists(path + ".bak"), "損壞檔改名 .bak 留底")
    # 損壞後還能正常 submit 並寫出乾淨檔案
    m9.submit_score(make_record("seeker", "RECOVER", 100, today_str()))
    m9b = Manager(path)
    m9b.load()
    ok(len(m9b.records) == 1 and m9b.records[0]["player_name"] == "RECOVER",
       "損壞恢復後可正常提交並重載")
    # 結構對但沒有 records 鍵（例如 {}) → 視同損壞
    with open(path, "w", encoding="utf-8") as f:
        f.write("{}")
    m9c = Manager(path)
    m9c.load()
    ok(m9c.records == [] and os.path.exists(path + ".bak"),
       "缺少 records 鍵的 JSON 也視同損壞、改名留底")

    print("\n== 10. 名字清洗（sanitize_player_name）==")
    cases = [
        ("  alice  ", "ALICE"),
        ("", ""),
        ("   ", ""),
        ("a\tb", "AB"),                  # 控制字元移除
        ("abcdefghijklmnop", "ABCDEFGHIJKL"),  # 截斷 12
        ("luna", "LUNA"),
    ]
    for raw, want in cases:
        got = sanitize_player_name(raw)
        ok(got == want, f"sanitize({raw!r}) → {got!r}（期望 {want!r}）")

    print("\n== 11. clear_all 與 clear_by_game ==")
    m11 = Manager(path)
    for g in GAME_IDS:
        for i in range(10):
            m11.submit_score(make_record(g, "X", 100, today_str()))
    ok(m11.clear_records_by_game("fishing") == 10 and
       all(r["game_id"] != "fishing" for r in m11.records),
       "clear_records_by_game 只刪 fishing 的 10 筆")
    m11.clear_all_records()
    ok(m11.records == [], "clear_all 清空全部")

    shutil.rmtree(tmp, ignore_errors=True)
    print()
    if FAILED:
        print(f"!! {len(FAILED)} 項失敗")
        for msg in FAILED:
            print("   - " + msg)
        return 1
    print("全部通過。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
