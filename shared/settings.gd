class_name Settings
extends RefCounted

# ─────────────────────────────────────────────────────────
# 管理員 SETTING 選單的設定值，跨執行保存（user://settings.cfg，
# Godot 內建 ConfigFile，跟排行榜 JSON 分開存）。
# 全靜態單例，跟 Palette / LeaderboardManager 同款用法 ——
# 不註冊 autoload、不改 project.godot。
#
# 目前只有 UNLIMITED COINS 一個開關（launcher 的 SETTING 二級選單
# 切換）。投幣系統（shared/coin_manager.gd 的 CoinManager）的開局閘門
# 用 is_unlimited_coins() 讀這裡的狀態；未來加設定就是一個 static
# var ＋ 一對 get/set ＋ _save() 裡的一行。
# ─────────────────────────────────────────────────────────

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"
const UNLIMITED_COINS_KEY := "unlimited_coins"

static var unlimited_coins := false
static var _loaded := false


static func is_unlimited_coins() -> bool:
	_ensure_loaded()
	return unlimited_coins


static func set_unlimited_coins(value: bool) -> void:
	_ensure_loaded()
	unlimited_coins = value
	_save()


## 從 user://settings.cfg 讀回設定。沒存過檔就用預設值（全部關閉）。
## 檔名刻意避開 load()／save()：裸 load() 會被解析成 GDScript 全域
## 函式（LeaderboardManager 踩過的坑，見它的 load() 註解）。
static func _load() -> void:
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	unlimited_coins = bool(cf.get_value(SECTION, UNLIMITED_COINS_KEY, false))


static func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, UNLIMITED_COINS_KEY, unlimited_coins)
	cf.save(SAVE_PATH)


static func _ensure_loaded() -> void:
	if not _loaded:
		_load()
