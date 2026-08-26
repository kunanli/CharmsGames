class_name CurrentPlayerSession
extends RefCounted

# ─────────────────────────────────────────────────────────
# 玩家名稱的生命週期（只存在記憶體，不要求永久保存）：
#   首次進入小遊戲      → 要輸入名字
#   遊戲結束 → 重新開始 → 保留名字
#   遊戲結束 → 退出     → 清除名字，下次進任何遊戲都要重輸
#
# launcher 是唯一負責「何時寫入／何時清除」的人；遊戲腳本一律只讀。
# 規則「進入另一款遊戲要重新輸入名字」自動成立 —— 退出排行榜回選單時
# 必然呼叫 clear()，下一次選遊戲就必然是沒有名字的狀態。
# ─────────────────────────────────────────────────────────

const MAX_NAME_LEN := 12

static var player_name := ""


static func set_player(raw: String) -> void:
	player_name = sanitize_player_name(raw)


static func clear() -> void:
	player_name = ""


static func is_active() -> bool:
	return not player_name.is_empty()


## 統一的名字清洗：去控制字元 → 去首尾空白 → 拒絕空字串 → 英文大寫 → 截斷。
## 回傳 "" 代表輸入不合法（空字串或純空白），launcher 要擋下不讓開始遊戲。
static func sanitize_player_name(raw: String) -> String:
	var cleaned := ""
	for i in raw.length():
		var c := raw[i]
		if c.unicode_at(0) < 32:
			continue
		cleaned += c
	cleaned = cleaned.strip_edges()
	if cleaned.is_empty():
		return ""
	return cleaned.to_upper().substr(0, MAX_NAME_LEN)
