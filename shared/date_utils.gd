class_name DateUtils
extends RefCounted

# ─────────────────────────────────────────────────────────
# 排行榜的日期工具：今天／昨天／前天、日期格式化、日期比較。
#
# 所有日期運算都走這裡，不允許在別處用字串截斷算日期 ——
# 月底／跨年／時區（DST）用字串算一定會錯。
# 做法：datetime dict → unix 時間戳 → 加減秒數 → 轉回 dict，
# Time API 自己處理月份滾動與日光節約，測試也不用擔心跨月。
# ─────────────────────────────────────────────────────────


## 今天／昨天／前天的日期字串（YYYY-MM-DD，本地系統時間）
static func today() -> String:
	return format_date(Time.get_datetime_dict_from_system())


static func yesterday() -> String:
	return format_date(add_days(Time.get_datetime_dict_from_system(), -1))


static func day_before_yesterday() -> String:
	return format_date(add_days(Time.get_datetime_dict_from_system(), -2))


## datetime dict 加上 n 天（n 可為負）。唯一允許的日期運算入口。
static func add_days(d: Dictionary, n: int) -> Dictionary:
	var unix := Time.get_unix_time_from_datetime_dict(d)
	return Time.get_datetime_dict_from_unix_time(unix + n * 86400)


## 兩個日期字串是否同一天。字串格式固定為 YYYY-MM-DD，字典序即時間序，
## 但比較一律走這裡 —— 未來若格式改變，只需改這一個地方。
static func is_same_date(a: String, b: String) -> bool:
	return a == b


static func format_date(d: Dictionary) -> String:
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


static func format_datetime(d: Dictionary) -> String:
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]
