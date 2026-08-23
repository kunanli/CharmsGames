class_name LeaderboardManager
extends RefCounted

# ─────────────────────────────────────────────────────────
# 本地排行榜：三款遊戲共用一份 JSON，用 game_id 區分。
# 全靜態單例，跟 Palette 同款用法 —— 不註冊 autoload、不改 project.godot。
#
# 排名一律即時計算、不存檔：顯示時排序一次就好。
# 排序規則：score DESC → played_at ASC → record_id ASC 兜底。
# （Array.sort_custom 不保證穩定，第三鍵讓排名完全確定。）
#
# 資料韌性：
#   - 檔案不存在 → 空資料，首次 submit 時自動建立
#   - JSON 損壞 → 改名 .bak 留底、空資料續跑，不讓遊戲崩掉
#   - 缺欄位 → from_dict() 給預設值（舊檔案相容）
#   - 超過 MAX_RECORDS → 刪最差的老記錄；**剛提交的那條永不刪**
# ─────────────────────────────────────────────────────────

const SAVE_PATH := "user://leaderboard.json"
const STORAGE_VERSION := 1
const SCORE_VERSION := 1       # 計分規則版本，每筆記錄統一蓋成這個值
const MAX_RECORDS := 1000      # 每個 game_id 最多保存幾條
const PAGE_SIZE := 20

static var _records: Array = []    # Array[LeaderboardRecord]，跨 game_id 存
static var _loaded := false


# ── 公開 API ─────────────────────────────────────────────

## 提交一條成績：補 id／時間／版本 → 追加 → 裁剪 → 存檔。回傳 record_id。
static func submit_score(record: LeaderboardRecord) -> String:
	_ensure_loaded()
	if record.record_id.is_empty():
		record.record_id = LeaderboardRecord.new_id()
	if record.played_at.is_empty():
		var now := Time.get_datetime_dict_from_system()
		record.played_at = DateUtils.format_datetime(now)
		record.played_date = DateUtils.format_date(now)
	record.score_version = SCORE_VERSION
	_records.append(record)
	_prune(record.record_id)
	save()
	return record.record_id


## 指定遊戲的全部記錄（已排序）。回傳新的 Array，顯示端只讀。
static func get_records(game_id: String) -> Array[LeaderboardRecord]:
	_ensure_loaded()
	var out: Array[LeaderboardRecord] = []
	for r in _records:
		if r.game_id == game_id:
			out.append(r)
	out.sort_custom(_compare)
	return out


## 指定分頁。page_index 0 基（第 1 頁是 0），越界夾到最近的有效頁。
## 回傳 {records, total, page_count, page_index}。
static func get_page(game_id: String, page_index: int, page_size: int = PAGE_SIZE) -> Dictionary:
	var all := get_records(game_id)
	var total := all.size()
	var page_count := maxi(1, int(ceil(float(total) / float(page_size))))
	var idx := clampi(page_index, 0, page_count - 1)
	var start := idx * page_size
	var out: Array[LeaderboardRecord] = []
	for i in range(start, mini(start + page_size, total)):
		out.append(all[i])
	return {
		"records": out,
		"total": total,
		"page_count": page_count,
		"page_index": idx,
	}


## 排名（1 基，以該記錄所屬遊戲的排行榜為準）。找不到回 -1。
static func get_rank(record_id: String) -> int:
	var rec := _find(record_id)
	if rec == null:
		return -1
	var all := get_records(rec.game_id)
	for i in all.size():
		if all[i].record_id == record_id:
			return i + 1
	return -1


## 該記錄落在第幾頁（0 基）。找不到回 -1。預留給未來「查看我的排名」。
static func get_page_containing_record(record_id: String, page_size: int = PAGE_SIZE) -> int:
	var rank := get_rank(record_id)
	if rank < 0:
		return -1
	return (rank - 1) / page_size


## 刪除指定日期的記錄（date 格式 YYYY-MM-DD），回傳刪了幾條。
static func clear_records_by_date(date: String) -> int:
	_ensure_loaded()
	var before := _records.size()
	_records = _records.filter(func(r): return r.played_date != date)
	var removed := before - _records.size()
	if removed > 0:
		save()
	return removed


static func clear_today_records() -> int:
	return clear_records_by_date(DateUtils.today())


static func clear_yesterday_records() -> int:
	return clear_records_by_date(DateUtils.yesterday())


static func clear_day_before_yesterday_records() -> int:
	return clear_records_by_date(DateUtils.day_before_yesterday())


## 刪掉某款遊戲的全部記錄（開發／測試用）。
static func clear_records_by_game(game_id: String) -> int:
	_ensure_loaded()
	var before := _records.size()
	_records = _records.filter(func(r): return r.game_id != game_id)
	var removed := before - _records.size()
	if removed > 0:
		save()
	return removed


## 清空全部（開發測試用。要不要二次確認是 UI 的責任，不是這裡的）。
static func clear_all_records() -> void:
	_ensure_loaded()
	_records.clear()
	save()


static func save() -> void:
	var arr: Array = []
	for r in _records:
		arr.append(r.to_dict())
	var payload := {"version": STORAGE_VERSION, "records": arr}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Leaderboard: 無法寫入 %s（%s）" % [
			SAVE_PATH, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()


## 從硬碟讀回資料。**類內呼叫必須用限定名 LeaderboardManager.load()** ——
## 裸的 load() 會被解析成 GDScript 全域的 load(path)，編譯器報參數不足。
static func load() -> void:
	_records.clear()
	_loaded = true
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_error("Leaderboard: 無法讀取 %s（%s）" % [
			SAVE_PATH, error_string(FileAccess.get_open_error())])
		return
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or not parsed.has("records"):
		# 損壞：把原始檔留底，空資料續跑 —— 寧可少一份排行榜也不要讓遊戲開不了
		push_error("Leaderboard: %s 無法解析，改名 .bak 留底、以空資料啟動" % SAVE_PATH)
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(SAVE_PATH) + ".bak")
		return

	var version := int(parsed.get("version", 0))
	if version > STORAGE_VERSION:
		push_warning("Leaderboard: 檔案版本 %d 比程式支援的 %d 新，仍嘗試讀取" % [
			version, STORAGE_VERSION])

	for entry in parsed["records"]:
		if entry is Dictionary:
			_records.append(LeaderboardRecord.from_dict(entry))
		else:
			push_warning("Leaderboard: 跳過一筆格式錯誤的記錄")


# ── 內部 ─────────────────────────────────────────────────

static func _ensure_loaded() -> void:
	if not _loaded:
		LeaderboardManager.load()   # 限定名：裸 load() 會撞全域函式


static func _find(record_id: String) -> LeaderboardRecord:
	for r in _records:
		if r.record_id == record_id:
			return r
	return null


## 排行榜排序：分數高在前；同分時早玩到的在前；再同就比 id（確定性兜底）。
static func _compare(a: LeaderboardRecord, b: LeaderboardRecord) -> bool:
	if a.score != b.score:
		return a.score > b.score
	if a.played_at != b.played_at:
		return a.played_at < b.played_at
	return a.record_id < b.record_id


## 每個 game_id 超過 MAX_RECORDS 時，刪「最差的老記錄」——
## 分數最低的先刪，同分時玩得晚的先刪。剛提交的（protected_id）永遠不刪。
static func _prune(protected_id: String) -> void:
	var counts := {}
	for r in _records:
		counts[r.game_id] = int(counts.get(r.game_id, 0)) + 1

	var victims: Array[LeaderboardRecord] = []
	for game_id in counts:
		var excess := int(counts[game_id]) - MAX_RECORDS
		if excess <= 0:
			continue
		var pool: Array[LeaderboardRecord] = []
		for r in _records:
			if r.game_id == game_id and r.record_id != protected_id:
				pool.append(r)
		pool.sort_custom(_compare_worst_first)
		for i in mini(excess, pool.size()):
			victims.append(pool[i])

	var victim_ids := {}
	for v in victims:
		victim_ids[v.record_id] = true
	_records = _records.filter(func(r): return not victim_ids.has(r.record_id))


## 與 _compare 相反：分數最低排最前（優先刪），同分時玩得晚的排最前。
static func _compare_worst_first(a: LeaderboardRecord, b: LeaderboardRecord) -> bool:
	if a.score != b.score:
		return a.score < b.score
	if a.played_at != b.played_at:
		return a.played_at > b.played_at
	return a.record_id > b.record_id
