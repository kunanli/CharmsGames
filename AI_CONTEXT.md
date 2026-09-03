# AI_CONTEXT — 快速上下文速查

> 本档是给 AI 工具的**快照速查**，内容提炼自 `AGENTS.md`。
> 规格细节的权威是 `AGENTS.md` 与 `Guides/` 的三份 GDD；
> 两边有出入时以 `AGENTS.md` 为准，改了 `AGENTS.md` 记得同步这里。

## 项目概况

Pandora 品牌合作的三款 8-bit 像素小游戏，共用世界观、色盘与结算（排行榜）系统。

### 技术

- **Godot 4.7** / 纯 GDScript / Compatibility renderer
- 逻辑分辨率固定 **480×270**，一格 tile 16px，4 倍整数放大显示
- 复古像素 + Y2K 风格；**只用 `shared/palette.gd` 的 21 色**（原 20 色＋2026-09 企划指定的 MOON_LIGHT），不新增中间色（唯一允许的变体是对既有色套 alpha）
- 画面上的东西目前全部是**程序绘制的色块与线条**（粉色方框的露娜、紫色方框的猫是预期现象），美术素材 M6 才接入
- HUD 文字一律英文（内置字体无中文字符，接中文字型后再改）

### 游戏

| # | 游戏剧名 | 类型 | 主脚本 |
|---|---|---|---|
| 1 | CharmsSeeker | 吃豆人（迷宫追逐） | `games/seeker/seeker.gd` |
| 2 | CharmsFishing | 黄金矿工（垂钓） | `games/fishing/fishing.gd` |
| 3 | CharmsCatch | 接金币（接珠宝躲炸弹） | `games/catch/catch.gd` |

三款共通：单一关卡 60 秒、统一状态机 `READY`（1.5 秒开场停顿）→ 游玩 → `RESULT`。**局终只结算分数与排名**——宝箱系统已于 2026-08 整体移除（原先按分数阈值判铜/银/金并在结算揭示，无随机抽取逻辑），不要再加回来。

## 当前系统

| 系统 | 实现位置 | 说明 |
|---|---|---|
| 流程状态机 | `launcher/launcher.gd` | `enum Mode { MENU, GAME_TITLE, NAME_INPUT, PLAYING, GAME_OVER, LEADERBOARD }`。相当于总管：标题、名字、游戏、局终 Game Over 动画、排行榜面板的切换全在这。**没有独立的 GameManager** |
| 场景管理 | 无独立 SceneManager | **刻意单场景架构**：全项目只有 `Launcher.tscn`（一个 Node2D）。游戏用 `load()` → `Node2D.new()` → `set_script()` → `add_child()` 挂到临时节点，退出 `queue_free()` 整个节点即自动清理。新增游戏只需在 `launcher.gd` 的 `GAMES` 数组加一笔 |
| 标题（Title） | `launcher/launcher.gd` | 一级标题（`assets/title/Title_ChooseGames.png` 全屏）是管理员选择画面：↑↓ 循环选游戏（MAZE/FISHING/CATCH）、B 开清除选单、A 确认进二级标题。**二级标题背景是各款的全屏影片（`assets/title/TItleVideo/Title_*.ogv`，等比例缩放填满 480×270，素材未进场退回标题图 `Title_*.jpg`），没有按钮，底部一行闪烁的 PRESS ANY BUTTON TO START 提示（亮灭二值闪烁，与待机 CLICK TO PLAY 同款；起名 overlay 与待机画面不画）**：按**任意键**→ 起名开局（A/B 例外：**A＋B 同时按住 3 秒** → 管理员密码界面）；二级标题是固定场所，不响应 1/2/3 与 ESC，**唯一回一级的路径是管理员密码界面**（方向指令密码，见「管理员弹窗」行） |
| 玩家名字（PlayerName） | `ui/name_input.gd` + `shared/player_session.gd` | 首次进游戏在**街机虚拟键盘**上输入名字（↑↓←→ 移动、A 确认、B 删除、X 清空、Y 预留、ESC 取消；0-9/A-Z + 右下 OK 钮，最多 9 字，空名按 OK 只有闪+抖回馈）；排行榜面板 B/ESC 回二级时清除。难度已于 2026-08 移除（不在这里选）。**起名是叠在二级标题上的三层 overlay**：launcher 在 NAME_INPUT 模式仍画二级标题图当底层，起名层盖 50% 黑罩再叠各游戏的起名弹窗图（RGBA），键盘钮素材按 game_id 取 `assets/title/Naming/NamingKeyboard/` 的 btn/btn_chosen |
| 排行榜（Leaderboard） | `shared/leaderboard_record.gd` / `leaderboard_manager.gd` / `date_utils.gd` + `ui/game_over.gd`（局终动画）+ `ui/leaderboard_panel.gd`（面板） | 本地存储 `user://leaderboard.json`（version:1，每款最多 1000 条，按 game_id 分榜）。三款共用同一套。游戏只发 `round_finished(score, duration, game_over)` 信号，不知道排行榜存在；组装与提交在 launcher，局终播 **Game Over 动画**（**背景保留游戏场景**——launcher 暂停游戏节点定格最后帧当底、进面板前才释放；只淡入淡出 GAME OVER/TIME UP 文字，**不显示分数/名字/排名**，播完自动进面板，无按钮）。**面板 = 大标题 YOUR SCORE（1920 座标 (960,80)、96px 居中）＋前 10 名单栏（排名 1ST./名字/分数左对齐 X≈370/620/1255、第一行 Y≈190、行距 72px、60px 字）＋底部当前玩家行（MOON_LIGHT 亮青高亮，同格式，名次可能 >10）**，进入时逐行交错显现（淡入＋左滑）；配色：行文字 = MOON（#A0DCFF）、标题与玩家行 = MOON_LIGHT（#90FFFF）；B/ESC 回该款二级标题并清名字 |
| 管理员弹窗 | `ui/admin_password.gd` | 二级标题 **A＋B 同时按住 3 秒**进入的 Modal Overlay，开着时 launcher 不处理任何按键。密码是**方向指令序列「上上下下左右左右」**（↑↑↓↓←→←→ 共 8 位）：每按一个方向键输入一位，输满 8 位按 A 确认（正确 → 回一级、错误清空重填；B 删除一位、ESC 取消回二级） |
| 视觉反馈 | `shared/juice.gd`（全画面）+ `shared/fx.gd`（单物件） | 震动/镜头偏移/顿格/粒子/挤压变形。预设 SUBTLE / ARCADE 两档，目前三款都挂 ARCADE，未实机定案 |

## 场景结构

```
Launcher.tscn          ← 唯一场景，只有 1 个 Node2D（launcher.gd）
└── 所有游戏物件都由代码 add_child() 生成，不写 .tscn
```

绘制分层（三款一致，按 FAR → WORLD → HUD 顺序画）：

| 层 | 内容 | 位移 |
|---|---|---|
| FAR | 星星、月亮、远山/屋顶剪影 | `bg_offset()` |
| WORLD | 玩家、敌人、道具、以及它们实际踩着的背景（水面线、地面线） | `world_offset()` |
| HUD | 分数、时间、生命、结算 | 恒为 0 |

背景一律外扩多画 `Juice.OVERDRAW`（24px）防震动露边。

## 重要脚本

| 脚本 | 职责 |
|---|---|
| `launcher/launcher.gd` | 标题选单与全流程状态机、A＋B 长按管理员密码入口、排行榜接线的组装端 |
| `games/seeker/seeker.gd` | Seeker 主程序与状态机；同目录 `maze.gd`（迷宫数据）、`player.gd`（露娜格子移动）、`cat.gd`（暗影猫 AI） |
| `games/fishing/fishing.gd` | Fishing 单文件实现 |
| `games/catch/catch.gd` | Catch 单文件实现 |
| `shared/palette.gd` | 锁定的共用色盘（原 20 色＋2026-09 企划指定的 MOON_LIGHT，共 21 色） |
| `shared/juice.gd` | 全画面效果：震动、镜头偏移、视差、顿格（状态机） |
| `shared/fx.gd` | 单物件效果：粒子爆散、挤压变形、分数滚动 |
| `shared/leaderboard_record.gd` | 单条记录的字段与序列化 |
| `shared/leaderboard_manager.gd` | 存储/排序/分页/清除，全部 static |
| `shared/player_session.gd` | 玩家名字生命周期（首次进游戏输入、重开保留、退出清除；难度由 launcher 管，不在这里） |
| `shared/date_utils.gd` | 排行榜日期工具（今天/昨天/前天），所有日期运算必须走这里，禁止字符串截断算日期 |
| `ui/leaderboard_panel.gd` | 三款共用的排行榜面板：大标题 YOUR SCORE＋前 10 名单栏＋底部当前玩家行，逐行交错显现（只读） |
| `ui/game_over.gd` | 局终 Game Over 动画：只淡入淡出 GAME OVER/TIME UP 文字（0.35s 淡入→停留至 1s→0.3s 淡出），背景＝暂停定格的游戏场景，播完自动进排行榜（无按钮、无结算信息） |
| `ui/name_input.gd` | 姓名输入屏：街机虚拟键盘（摇杆 + A/B/X/Y 操作，数据驱动 `KEY_ROWS` 布局，OK 钮右下角） |
| `ui/admin_password.gd` | 管理员密码界面：方向指令密码（↑↑↓↓←→←→ 8 位），A 确认、B 删除、ESC 取消 |
| `tools/sim/*.py` | 平衡模拟脚本（Python 移植 GDScript 逻辑，跑几百局用统计验证数值），常量是 `.gd` 的副本，改了 `.gd` 要同步 |

## 输入规则

| 场景 | 按键 | 行为 |
|---|---|---|
| 一级标题 | **1 / 2 / 3** | 进对应款二级标题（底部显示当前难度） |
| 一级标题 | **← →** | 切换难度 EASY / HARD（管理员选择） |
| 二级标题 | **任意键** | 起名开局（无按钮，底部闪烁 PRESS ANY BUTTON TO START 提示；A/B 例外，见下行） |
| 二级标题 | **A＋B 同时按住 3 秒** | 进入管理员密码界面：方向键输入「上上下下左右左右」8 位指令、A 确认（正确回一级管理员界面），B 删除、ESC 取消；不足 3 秒松开 A/B = 普通按键，照常起名开局 |
| 游戏中 | **ESC** | 回该款的二级标题（名字清除） |
| 局终 Game Over 动画 | （无按键） | 只淡入淡出 GAME OVER/TIME UP 文字（0.35s 淡入→停留至 1s→0.3s 淡出，共约 1.3s），播完自动进排行榜面板 |
| 排行榜面板 | **B / ESC** | 回该款的二级标题（名字清除） |

三款操作（GDD 协议，A/B/X 为主动技能键）：

| 游戏 | 移动 | 主动技能 | 备注 |
|---|---|---|---|
| Seeker | 方向键（**不支持 WASD**，A 被技能占用） | **A** 发动 8 秒石化 | 需先捡到月光能量，最多囤 2 个 |
| Fishing | ← → 探看湖面（三款唯一有镜头移动的） | **A / 空格 / ↓ / Enter** 放线；**B / X** 月光能量（每局 3 次，收线途中才有效） | 放线后不可取消 |
| Catch | ← → | **B / X** 引爆护盾清全场炸弹 | 长按同方向 1 秒线性加速到 ×2.5（A/Shift 冲刺已移除），人物贴屏幕最底 |

## 当前开发进度

| 游戏 | 状态 |
|---|---|
| CharmsSeeker | 做到 M4（月光石化 + 击碎暗影猫）。**M5 未做**（每 20 秒加猫，上限 8） |
| CharmsFishing | 四物件改版完成（2026-08：鑽石／寶珠／雲朵／小惡魔，數量翻倍、生成區由企劃調整） |
| CharmsCatch | 依 GDD 完成首版，移动手感已调（60→95 px/s）；掉落物数量翻倍（2026-09） |

待办（优先序）：

1. 实机试玩定案 SUBTLE 或 ARCADE（需要人玩）
2. 对齐 Seeker 与 GDD 的差异（珍珠数 180/200/205、被抓处理，卡企划拍板）
3. M5：每 20 秒加一只暗影猫（坑很多，见 AGENTS.md 待办第 3 条）
4. M6：接美术素材、音效（**目前最大缺口**）、Xbox 手柄
5. M7：导出 Windows / Web，接排行榜

待企划确认：Seeker 珍珠数、被抓无敌 vs 重置。

## 已确定的设计决策

- **单场景纯代码架构**：所有逻辑都在 `.gd` 里，方便 AI 读写与 git diff，不写 `.tscn`。
- **格子坐标 `Vector2i`、像素坐标 `Vector2`**，用各游戏自己的 `cell_center()` 转换，混用是最容易出的 bug。
- **格子移动用纯数学判断**（`move_toward` 等），不用物理节点 —— 物理碰撞会卡墙角、抖动。
- **画布位移（震动、镜头偏移）只走绘制层 `draw_set_transform()`，绝不写进 `position`** —— `position` 每帧参与移动与碰撞判定。
- **镜头移动只有 Fishing 有**（玩家主动按键探看）；Seeker/Catch 禁止自动跟随镜头，实测会晕。
- **排行榜**：score 降序 → played_at 升序 → record_id 升序；新提交的记录永不因裁剪丢失；记录 ID 由时间戳 + 引擎毫秒 + 同次执行递增序号 + 随机尾码组成（防同毫秒撞号）；档损坏自动改名 `.bak` 重来。**面板 = 大标题 YOUR SCORE＋前 10 名单栏＋底部当前玩家行（MOON_LIGHT 亮青）**，行文字 MOON（#A0DCFF）、标题与玩家行 MOON_LIGHT（#90FFFF），进入时逐行交错显现；**Game Over 动画播完自动进面板**（无按钮、无 RESTART，重玩＝回二级重新起名）；B/ESC 回该款二级标题并清名字。
- **起名页是街机虚拟键盘**（2026-08 改版：摇杆 + A/B/X/Y 操作，不依赖系统键盘/软键盘；0-9/A-Z 36 个字符键 + 右下 OK 钮，最多 9 字，空名按 OK 拒绝只给回馈；边界夹住不绕行、输入后自动前进到下一格）。**一级标题的 EASY/HARD 难度已于 2026-08 移除，← → 不再响应**（launcher 无难度状态、排行榜记录无 DIFF 列）。起名界面是二级标题上的三层 overlay（二级标题图 → 50% 黑罩 → 各游戏的 Name 弹窗图 → 文字），`assets/title/Naming/` 的三张 Name 图（RGBA 弹窗样式）在使用中。
- **Catch 移动速度 95 px/s 是刻意偏离 GDD 的 60**（企划试玩后拍板），配套加惯性（ACCEL 900 / FRICTION 700）。人物与提篮已融合为单一物件，接取判定框＝cc_person1 贴图大小（90×71），脚踩屏幕最底（LUNA_Y=270），漏接线同步为 270。A/Shift 冲刺于 2026-08 移除（实机几乎没人用），改长按同方向 1 秒线性加速：×1.5 时难度回升（中位 4450→3350、接取率 85%→79%），调至 ×2.5 后升回 4150/87%，Combo 优势回复；回调难度杠杆是生成间隔、炸弹比例或加速暖机时长。
- **Catch 露娜已换动画场景（2026-09）**：`assets/AnimationScene/C_Player.tscn`（AnimatedSprite2D 两段：`Idle` 8 帧 @9fps 循环；`Hurt` 3 帧 @6fps，接到炸弹扣命时播一次再回 Idle，护盾挡下不播）。实例挂到子节点 `luna_view`（z=-1、纯视觉、position 只当绘制锚点）；动画不自己播（pause 后 `_process` 手动推帧，launcher 停掉游戏节点时画面才跟着冻）；挤压变形写 `luna_view.scale`（原点＝脚底锚点）；缩放 `PLAYER_SCALE = 0.29`（帧 450×284、内容 308×240 ≈ 判定框 90×71），锚点数据在 `P_REFS`（每段取第 0 帧 alpha>32 包围盒，画师改图要重测）。**背景因此搬到 `BgView` 子节点（z=-2，fishing 同款）**——子节点画在父节点 `_draw()` 之后，背景留在父节点会盖住玩家；场景结构不符时退回 cc_person1 静态贴图。
- **Catch 掉落物数量翻倍（2026-09 企划）**：生成间隔减半（0.8~1.1 / 0.7~1.0 / 0.6~0.9 / 0.5~0.75 秒）、同屏上限 2/3/4/5→4/6/8/10，**炸弹比例对折**（10%→35% 变 5%→17.5%）保持炸弹密度不变——炸弹一起翻倍会让 AI 存活率 68%→19%、平均局长 56s→45s，局提前结束，总数与分数反而缩水（catch_sim.py 第 6 节）。结果：有价物 28.6→59.5 颗/局、中位分 4150→4500、接取率 87%→71%；密度升高稀释了可及性约束的边际价值（断言门槛 +0.3→+0.1）。
- **Fishing 四物件改版**（2026-08）：钻石＋200/收线 85/**32×32**（中深层，表面有白光二值闪烁十字星芒）、宝珠＋100/85/32×32（中层）、云朵＋10/160/32×32（任意层）、小恶魔 0 分/105/16×16（任意层，会游动、放线时靠近钩头，上船 −3 秒）。生成区域（企划直接调过）：(112,168)/(162,208)/(212,256)、全区 (112,256)；**数量翻倍** 4 宝珠＋6 钻石＋8 云朵＋4 恶魔＝22 件，放置顺序「带最窄的先放」（宝珠→钻石→云朵→恶魔）、尝试 500 次（40 次会偶发短缺，模拟 10000 局零失败）。**四物全部回补**（同类同层），重生延迟 5~15 秒随剩余时间由慢到快；没有补充则盘面总值天花板只有 1680 分。
- **Fishing 船与露娜已换动画场景（2026-08-31）**：`assets/fishing/F_Luna.png` 静态贴图由 `assets/AnimationScene/F_Player.tscn` 取代（AnimatedSprite2D 四段动画：Idle 待机循环／Hook 放线循环（线伸出与收回途中都播）／GetPoint 宝物上船加分播一次／Hurt 小恶魔上船扣时间播一次，一次性动画播完自动回基础动画）。实例挂到预留的 `luna_view` 接口（纯视觉节点，position 每帧对齐 `_luna_anchor() + _juice.world_offset()`，不参与玩法判定；`_draw_boat()` 检测到 luna_view 非 null 就跳过旧贴图，场景结构不符时退回）。动画不自己播（pause 后 `_process` 手动推帧，launcher 停掉游戏节点时画面才跟着冻）；显示缩放 `PLAYER_SCALE = 0.2`（与旧贴图同尺寸）；锚点数据在 `P_REFS`（每段动画取第 0 帧的 alpha>32 包围盒，「船底贴水面线＋水平置中」，整段动画共用一个 offset——画师所有帧都在同一画布、内容位置一致，**不做逐帧归一化**：逐帧锚定会让船跟着角色肢体摆动而左右滑，画师改图要重测）。
- **Seeker 月光能量是「捡到囤、按 A 发动」**，不是捡到即发；被击碎的猫重生一律回 ACTIVE 不带石化（防中央蹲点刷分）。
- **Seeker 已接美术背景与角色动画（2026-08-31）**：`S_MAP.png`（1920×1080）÷4 拉伸为全屏背景（图内迷宫对齐 `Maze.ORIGIN`×4）；程序星点 `SHOW_STARS` 关闭。露娜跑步动画改用画师交付的 `assets/AnimationScene/S_Player.tscn`（8 帧 walk）替换原 `WALK_FRAMES` 程序绘制——tscn 仅作视觉节点（实例化挂到 player 下、AnimatedSprite2D 保持 pause 由 `_process` 手动推帧，`set_process(false)` 冻结时画面跟着冻），帧归一化数据在 `FRAME_BOXES`（画师改图需重测），显示宽 16px、脚底锚点 +8；**缩放必须在 `_ready()` 设好**（`_anim.scale`），只靠 `_update_anim` 的话 READY 期间 `_process` 不跑、开场会以 464×464 原尺寸显示。
- **Seeker 场道具与月光库存已接美术（2026-08-31）**：珍珠 `S_Perl.png`、月光 `S_Moon.png`（均 220×220，`ITEM_SHOW` 等比缩到 15px 居中画在格内，内容物约 11~13px 与旧 15×15 图视觉一致）；HUD 左下月光库存由程序圆形改为 `S_Moon.png`（14px、间距 20），规则同爱心：有库存全亮、空位 alpha 0.22、用掉那颗播 1 秒「放大 1.25 倍＋淡出」（`_moon_fade`/`_moon_fade_slot` 镜像 `_heart_fade`，触发点在 `_activate_moon()` 的 `moon_stock -= 1` 后）。
- **改任何玩法数值的前后都要跑 `tools/sim/` 对应脚本**对比 —— 平衡全靠数字，看不出来。

## 禁止修改的系统

- **`Launcher.tscn` 及一切 `.tscn` 场景文件** —— 单场景是核心架构决定。
- **480×270 逻辑分辨率与 16px tile** —— 所有坐标以此为准。
- **`shared/palette.gd` 的 21 色** —— 需要新色先跟企划讨论加进色盘（MOON_LIGHT 即此流程的先例），不自创中间色。
- **不要重新引入局末宝箱 / 奖励抽取** —— 2026-08 已整体移除（`CHEST_*` 常量、`chest_tier()`、面板宝箱行、launcher 的 `chest_tiers` 传参全部拆除），局终仅计分数与排名。
- **不引入任何外部套件 / addon / 物理碰撞做格子移动**。
- **`user://leaderboard.json` 的 version:1 格式** 与排行榜排序/裁剪/ID 生成规则（有 300 笔连发的压力测试背书）。
- **`tools/sim/` 的同步纪律** —— 改 `.gd` 数值必须同步 sim 副本并重跑对比。
- **`AGENTS.md` 是单一权威文件** —— 规格变更写进它，本档只做摘要同步，不另立规格。
