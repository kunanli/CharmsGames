class_name CoinManager
extends RefCounted

# ─────────────────────────────────────────────────────────
# 投幣系統（2026-09）：街機的代幣餘額，與「開一局要不要扣幣」的閘門。
#
# 跟 CurrentPlayerSession 同款靜態單例 —— 不註冊 autoload、不改
# project.godot。幣量**只存記憶體**：投幣是實體行為，每次啟動歸 0、
# 不落地保存；要跨執行保存的只有管理員的 UNLIMITED COINS 開關，
# 那份狀態在 Settings（user://settings.cfg），這裡只轉讀。
#
# launcher 是唯一呼叫 add_coin()（二級標題按 Y）與 consume_coin()
# （開局閘門）的人；三款小遊戲不知道投幣存在，別的流程要動幣量
# 一律走這個類，不許直接改 coins。
# ─────────────────────────────────────────────────────────

## 開一局要消耗的投幣數（企劃暫定 1 枚；二級標題顯示「餘額/需求」如 0/1）。
const START_COST := 1

## 目前投幣餘額。只存記憶體：啟動歸 0、投一枚 +1，不設上限。
static var coins := 0


static func get_coins() -> int:
	return coins


## 投幣（二級標題按 Y）。無限投幣 ON 也照常累計 —— 顯示是 ∞ 看不出
## 數量，但管理者把 ON 關掉後，先前投的幣仍在。
static func add_coin(amount: int = 1) -> int:
	coins += amount
	return coins


## 名下有沒有至少一枚幣（純餘額判斷，不含無限投幣；開局閘門用 consume_coin）。
static func has_coin() -> bool:
	return coins >= 1


## 開局閘門（檢查＋扣幣一次做完）：無限投幣 ON 永遠放行且**不扣幣**；
## OFF 時餘額夠 START_COST 才扣一枚放行。回傳 false = 幣不夠，呼叫端
## 只管抖 Coin 圖＋播音效，不准自行改動幣量。
static func consume_coin() -> bool:
	if is_unlimited_coins():
		return true
	if coins < START_COST:
		return false
	coins -= START_COST
	return true


## 起名中止的退幣（2026-09，name_input 空名按 B／← 發 aborted 後呼叫）：
## 把開局閘門吃掉的那枚補回。無限投幣 ON 時閘門沒扣過幣，這裡也不補 ——
## ON/OFF 在起名期間不會變（SETTING 只能從一級標題進），用當下開關判斷
## 是安全的。只准用在「玩家主動中止起名」這一條路，其他流程動幣量走
## add_coin／consume_coin。
static func refund_start_cost() -> void:
	if is_unlimited_coins():
		return
	coins += START_COST


## UNLIMITED COINS 開關的唯一事實在 Settings（跨執行保存），這裡轉讀。
## 遊戲流程統一走這個名字，不要各自直接呼叫 Settings。
static func is_unlimited_coins() -> bool:
	return Settings.is_unlimited_coins()
