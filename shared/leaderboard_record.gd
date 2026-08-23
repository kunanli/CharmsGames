class_name LeaderboardRecord
extends RefCounted

# ─────────────────────────────────────────────────────────
# 一條排行榜記錄。純資料類：不知道排行榜的存在，只管欄位與序列化。
#
# 未來加欄位：to_dict()／from_dict() 各加一行即可。舊檔案缺新欄位時
# from_dict() 會給預設值，不需要遷移腳本；未知欄位一律忽略。
# ─────────────────────────────────────────────────────────

var record_id := ""          # 唯一 ID（時間戳＋隨機尾碼），同秒同分也不撞
var game_id := ""            # "seeker" / "fishing" / "catch"
var game_name := ""          # UI 顯示用（英文標題，專案 HUD 一律英文）
var player_name := ""        # 允許重複，同名多條記錄是合法資料
var score := 0
var difficulty_id := ""      # 目前固定 "normal"（三款都還沒有難度系統）
var difficulty_name := ""    # 目前固定 "NORMAL"
var played_at := ""          # "2026-08-21 10:32:15"，同分時較早者排名高
var played_date := ""        # "2026-08-21"，清除「今天／昨天／前天」用
var duration_seconds := 0.0
var score_version := 1       # 計分規則版本，未來改規則舊資料仍可辨識


func to_dict() -> Dictionary:
	return {
		"record_id": record_id,
		"game_id": game_id,
		"game_name": game_name,
		"player_name": player_name,
		"score": score,
		"difficulty_id": difficulty_id,
		"difficulty_name": difficulty_name,
		"played_at": played_at,
		"played_date": played_date,
		"duration_seconds": duration_seconds,
		"score_version": score_version,
	}


## 從 JSON 的 Dictionary 重建。缺欄位給預設值、數值強轉型 ——
## 扛得住「舊檔案缺新欄位」與「JSON 把 int 讀成 float」兩種情況。
static func from_dict(d: Dictionary) -> LeaderboardRecord:
	var r := LeaderboardRecord.new()
	r.record_id = str(d.get("record_id", ""))
	r.game_id = str(d.get("game_id", ""))
	r.game_name = str(d.get("game_name", ""))
	r.player_name = str(d.get("player_name", ""))
	r.score = int(d.get("score", 0))
	r.difficulty_id = str(d.get("difficulty_id", ""))
	r.difficulty_name = str(d.get("difficulty_name", ""))
	r.played_at = str(d.get("played_at", ""))
	r.played_date = str(d.get("played_date", ""))
	r.duration_seconds = float(d.get("duration_seconds", 0.0))
	r.score_version = int(d.get("score_version", 1))
	return r


static var _seq := 0           # 同一次執行內的嚴格遞增序號（同毫秒也不撞）

## 唯一 ID。unix 時間＋引擎毫秒＋序號＋隨機尾碼 —— 序號保證同一次執行內
## 嚴格遞增，同毫秒連續提交多筆也不撞；跨執行之間靠時間戳分開。
## 不需要去重檢查。隨機尾碼純粹是冗餘的鹽。（Godot 4 啟動時會自動
## randomize 全域 RNG，不需要自己呼叫。）
static func new_id() -> String:
	_seq += 1
	return "%d-%d-%d-%04d" % [
		Time.get_unix_time_from_system(), Time.get_ticks_msec(), _seq, randi() % 10000]
