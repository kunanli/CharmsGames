class_name Palette
extends RefCounted

# ─────────────────────────────────────────────────────────
# 三款共用色盤 v1 —— 對應 Guides/charms-palette.png
#
# 硬規則（美術規格書第三條）：**只用本檔列出的顏色**（原 20 色，
# 2026-09 企劃指定新增 MOON_LIGHT 與排行榜主色三色 ACCENT_* 後
# 為 24 色），不自行新增中間色、不用漸層、不用圖層混合產生新色。
# 需要新色請先跟企劃討論再加進色盤，加了之後這支檔案要一起更新。
#
# 為什麼這麼嚴：480×270 用 4 倍整數放大，一個像素會變成螢幕上的
# 4×4 方塊。色數一失控，8-bit 的質感就散了。
#
# 美術總則：整個畫面幾乎都是靛藍與紫色的夜色，只有三樣東西該發光 ——
# 露娜帽上的心形徽章（LUNA_LIGHT）、地上的星塵珍珠（PEARL）、
# 以及暗影猫那雙黃眼睛（CAT_EYE）。其他一切都應該退到背景裡去。
# ─────────────────────────────────────────────────────────

# ── 夜空與背景 ──────────────────────────────────────────
const NIGHT := Color("12102E")      # 最深夜色／陰影
const BG := Color("1E1C46")         # 主背景
const FAR := Color("2E2A5C")        # 遠景剪影
const NEAR := Color("3E3A76")       # 近景／天空漸層

# ── 牆體與魔法藤蔓 ──────────────────────────────────────
const WALL_DARK := Color("4A5BA8")  # 牆體暗部
const WALL := Color("6E82D2")       # 牆體主色
const WALL_LIGHT := Color("A0B4EC") # 牆體高光

# ── 露娜（主角）─────────────────────────────────────────
const LUNA_DARK := Color("C86E9E")  # 斗篷暗部
const LUNA := Color("EEB4D2")       # 主色／帽子
const LUNA_LIGHT := Color("FFE0F0") # 高光／心形徽章（品牌識別，務必跳出來）

# ── 暗影猫（反派）───────────────────────────────────────
const CAT_DARK := Color("2A1A4A")   # 身體暗部
const CAT := Color("5A3A8C")        # 身體主色
const CAT_GLOW := Color("A878DC")   # 紫色暗影特效
const CAT_EYE := Color("FFE066")    # 眼睛（全畫面唯一暖色，玩家靠這個定位威脅）

# ── 收集物與 UI ─────────────────────────────────────────
const PEARL := Color("F0E2B4")      # 星塵珍珠
const GOLD := Color("FFD37A")       # Pandora 金／得分
const MOON := Color("A0DCFF")       # 月光能量／石化
const MOON_LIGHT := Color("90FFFF") # 比 MOON 更亮的青（2026-09 企劃指定）
const WARN := Color("FF9A6A")       # 警示／倒數 10 秒
const TEXT := Color("F0F4FF")       # 文字主色（白）
const TEXT_DIM := Color("8890C0")   # 文字次要色

# ── 排行榜主色（2026-09 企劃指定，一款一色：標題／玩家行文字）────
const ACCENT_MAZE := Color("D80E85")     # maze（seeker）排行榜主色
const ACCENT_FISHING := Color("123BF4")  # fishing 排行榜主色
const ACCENT_CATCH := Color("A40CE8")    # catch 排行榜主色
