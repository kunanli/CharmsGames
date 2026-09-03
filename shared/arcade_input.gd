class_name ArcadeInput

# ─────────────────────────────────────────────────────────
# 街機按鍵綁定的唯一入口（2026-09）：A／B／投幣三顆街機鍵各對應一個
# InputMap action，鍵盤與 Xbox 手柄同時綁在 project.godot 的 [input]：
#
#   arcade_a    ＝ 鍵盤 A ＋ 手柄 A（button_index 0）
#   arcade_b    ＝ 鍵盤 S ＋ 手柄 B（button_index 1）
#                 （2026-09：鍵盤 B 的邏輯全部改到 S，鍵盤 B 不再有用）
#   coin_insert ＝ 鍵盤 Y ＋ 手柄 View/Back（button_index 4）
#
# 標題選單、起名、管理員密碼／清除選單、排行榜面板與三款遊戲的技能鍵
# 一律走這裡的 action 判斷，不要直接比 KEY_A／KEY_B keycode —— 之後換
# 鍵位或加手柄只改 project.godot，程式不動。
#
# 注意：手柄按鈕事件（InputEventJoypadButton）不會進 _unhandled_key_input
# （那裡只收鍵盤），要同時吃鍵盤與手柄的節點請用 _unhandled_input(event)，
# 先過濾 InputEventKey／InputEventJoypadButton 再用下面的 pressed/released。
# 方向鍵不在此列：遊戲內移動吃內建 ui_left 等 action（手柄十字鍵／左搖杆
# 引擎預設已綁），選單的方向移動維持鍵盤直讀 keycode。
# ─────────────────────────────────────────────────────────

const ACTION_A := "arcade_a"
const ACTION_B := "arcade_b"
const ACTION_COIN := "coin_insert"


## 這個輸入事件是否「按下」了該街機鍵（鍵盤與手柄按鈕事件都算）。
## action 被人從 project.godot 的 [input] 拿掉時安全回 false，
## 不讓 is_action_pressed 刷錯誤。
static func pressed(event: InputEvent, action: String) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)


## 這個輸入事件是否「放開」了該街機鍵。
static func released(event: InputEvent, action: String) -> bool:
	return InputMap.has_action(action) and event.is_action_released(action)


## 輪詢版（_process 裡做邊沿檢測用）：該街機鍵此刻是否被按住。
static func held(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)
