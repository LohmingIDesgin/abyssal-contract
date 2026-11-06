class_name BalanceConfig
extends Resource
## 玩法数值总表。实际用的是 data/balance.tres（GameDB.balance），在检查器里改；
## 这里写的是默认值，.tres 里没改过的项就用它。
## 现在的数都是占位值，要等试玩日志和整局模拟器测出产出再定（见设计对照文档第 5 节）。
## 后面几个阶段改写搏斗、饵料、昼夜时，会把各自的数值也挪进来。

@export_group("水层")
## 三层水（GameDB.DEPTH_NAMES：浅层、深水、渊底）各出几级的生物：每层五个数，依次是 1–5 级占的比例（每层自动归一；
## 这一级在这层水里一种也没有的不算）。2026-11-03 定的：浅层只出 1 级；深水 3 级 < 1 级 < 2 级；
## 渊底 2 级极少、3 级最多、4 级略少于 3 级、5 级略少于 4 级，没有 1 级。生物的等级跟着时期走（FishData.stage_levels），
## 所以一层水里出什么种类、什么时期，是按等级挑出来的：浅层有灰鲦的三个时期、血齿冥鲳的幼年和成长期、磷灯婆的幼年……
@export var layer_levels := PackedFloat32Array([1, 0, 0, 0, 0,  0.3, 0.5, 0.2, 0, 0,  0, 0.05, 0.35, 0.32, 0.28])
## 同一层水、同一级里，幼年期、成长期、成年期的个体各占多少（越老越少；自动归一）
@export var stage_share := PackedFloat32Array([0.45, 0.35, 0.2])
## 只差一级的种类（血齿冥鲳 1–2、盲眼噬骸鳗 2–3）的成长期，两级都有可能：灵魂强度比这一级成长期的平均高出
## 这么多（及以上）就算高的那一级，祭值也跟着高一截。0 = 一半一半（CatchGenerator）
@export var growth_up_soul := 0.0

@export_group("渔获个体")
## 带一个普通词条的概率
@export_range(0.0, 1.0) var affix_chance := 0.35
## 每比 1 级高一级，处理出来的材料多出的比例（0.1 = 10%）。原来 50%：一份饵挂一次以后，深水里拆一条就能换回一份多的饵
@export var yield_per_level := 0.1
## 处理所得的总缩放（新回合机制第 42 条）：拆一条换回的饵不能比钓它花掉的多，不然没有倒计时就能一直钓下去。
## 幼年的小鱼拆了 1 份材料，成长期、成年期至少 2 份（一条换一份饵），理财渔获（白鲟、带铁骨 / 血旺 / 磷腺的、成年的大个）多几份。
## 0.36 是 2026-11-04 换成躯体规模以后重定的（原来 0.4）：个头改成比那一档的平均大多少以后平均是 1（原来约 0.885），
## 0.4 的话渊底全拆每咬一口换回 0.94 份饵、四分之一的夜钓到上限；0.36 回到原来的 0.86
@export var yield_scale := 0.36
## 幼年期、成长期、成年期处理出来的材料倍率
@export var stage_yield := PackedFloat32Array([0.6, 1.0, 1.5])
## 幼年期、成长期、成年期至少拆得出几份材料：每一条都拆得出东西，成长期、成年期的至少够做一份饵
@export var min_materials := PackedInt32Array([1, 2, 2])

@export_group("时期")
## 三个时期各自的（等级跟着时期走以后，挣扎和耐力不再按时期变：强弱看等级）：搏斗里挣扎的倍率、耐力的倍率、灵魂强度的偏移、祭值的时期系数。
## 躯体规模按时期分档（FishData.adult_body，见下面"躯体规模"），2026-11-04 起不再有重量的倍率
@export var stage_struggle_mult := PackedFloat32Array([1.0, 1.0, 1.0])
@export var stage_endurance_mult := PackedFloat32Array([1.0, 1.0, 1.0])
@export var stage_soul_offset := PackedFloat32Array([-8.0, 0.0, 10.0])
@export var stage_tribute := PackedFloat32Array([1.0, 1.2, 1.4])

@export_group("灵魂强度、能量与祭值")
## 灵魂强度（0–100）：平均 soul_base + soul_per_level × (等级 − 1) + 时期偏移，上下浮动 soul_spread（正态的标准差）
@export var soul_base := 30.0
@export var soul_per_level := 10.0
@export var soul_spread := 8.0
## 能量（2026-11-04，原来的"食后成长"改成的纯数值词条，只用来算祭值）：1–5 级生物的平均能量，个体上下浮动 energy_spread（正态，
## 夹在平均的 0.6–1.5 倍之间），再乘词条的 energy_mult。数值照原来祭值的等级系数（1.2 / 2.2 / 3.6 / 5.2 / 7.2）× 10 定，各级的祭值和原来差不多
@export var energy_by_level := PackedFloat32Array([12, 22, 36, 52, 72])
@export var energy_spread := 0.12
## 祭值 = 种类基础值 × 时期系数（stage_tribute）× 能量 ÷ 10 × (tribute_soul_base + 灵魂强度 × tribute_soul_weight) × Π(1 + 词条加成)
## （CatchGenerator.tribute_of）。2026-11-04 起只看种族、时期、灵魂强度、能量，躯体规模（原来的重量、个头）不再算
@export var tribute_soul_base := 1.5
@export var tribute_soul_weight := 0.05

@export_group("躯体规模")
## 躯体规模（2026-11-04 你定的）：一个数值，按它分五档——小型 0.1–0.5（含 0.5）、中型 0.5–2.0（含 2.0）、大型 2.0–5.0、
## 巨型 5.0–15.0、畸变 15.0 以上（每一档含上限、不含下限）。每种生物的成年期是一档（FishData.adult_body，这一种的上限），
## 成长期小一档、幼年期再小一档（最小到小型）；带「变异」的再大一档。数值在那一档里按对数掷，中间的多、两头的少
## （body_quantile）；畸变这一档掷到最后一个数为止。躯体规模管生吞加的饱腹（hunger_for）和分解出的材料（个头：
## 比这一档的平均大多少，CatchGenerator.evaluate），不管祭值
@export var body_lines := PackedFloat32Array([0.1, 0.5, 2.0, 5.0, 15.0, 45.0])

@export_group("冥海侵蚀与海况")
## 冥海侵蚀（v0.23，2026-11-04）：七夜里冥海越来越危险。不加新的等级，只改生物怎么出（for_night 每夜改一份数值表，
## 抛竿、搏斗用它）。第 1 夜以后每过一夜：三个时期的比例各乘 (1 + erosion_stage × 过了几夜)（幼年少、成年多）；
## 灵魂强度的平均 + erosion_soul；特殊词条的机会 × (1 + erosion_special × 过了几夜)；每层水里各级的比例往高的偏 erosion_tilt
@export var erosion_stage := PackedFloat32Array([-0.03, 0.0, 0.05])
@export var erosion_soul := 1.0
@export var erosion_special := 0.15
@export var erosion_tilt := 0.04
## 海况（每夜一种；签约后的第一夜是平静）：calm 平静、rough 躁动、eerie 异化的权重
@export var sea_weights := {"calm": 0.45, "rough": 0.35, "eerie": 0.2}
## 平静 / 躁动：每层水里各级的比例往低 / 往高偏这么多（最低那一级 × (1 − 偏)、最高那一级 × (1 + 偏)，中间的按位置；
## 只出一级的那层不变）
@export var sea_tilt := 0.25
## 异化：特殊词条的机会再乘几
@export var eerie_special := 3.0
## 特殊词条的机会再乘几：总表里是 1，每一夜的那份数值表（for_night）里改
@export var special_chance_mult := 1.0
## 这一份数值表是哪一种夜（for_night 填；总表是空的）：只在某些夜里出的种类看它（FishData.appears_when，阶段 V）
var night_sea := ""
var night_blood_moon := false

@export_group("海上事件和交易")
## 海上事件（阶段 IV，SeaEvents）：从第 event_min_night 夜起，每夜有 event_chance 的机会出一件，
## 在这一夜的第 event_cast_min–event_cast_max 竿（那一竿不扣饵）；唤祂前没抛到就没有了
@export var event_min_night := 2
@export_range(0.0, 1.0) var event_chance := 0.5
@export var event_cast_min := 2
@export var event_cast_max := 3
## 各件的权重：trade 冥市船、hand 溺者之手、wreck 漂来的残骸、blood_moon 血月、whisper 祂的低语
@export var event_weights := {"trade": 3.0, "hand": 2.0, "wreck": 2.0, "blood_moon": 1.5, "whisper": 1.0,
	"ghost": 1.0, "storm": 1.5, "gambler": 1.5}
## 冥市船的价钱：今夜需求的几成（取整到百）。一张恩赐、trade_bait_count 份万能饵、一件道具（各道具的价）。
## 按模拟器定的：0.45 / 0.3 时谨慎的脚本玩家一份契约只买 0.1 张恩赐，太贵了没人换；夜越往后价越高、恩赐管的夜越少，早买划算
@export var trade_boon := 0.35
@export var trade_baits := 0.25
@export var trade_bait_count := 2
@export var trade_items := {"soul_thread": 0.5, "soul_nail": 0.3, "abyss_eye": 0.15}
## 漂来的残骸：花一份饵去钩，一件道具 / wreck_materials 份材料 / 什么也没有 的机会
@export var wreck_odds := {"item": 0.4, "materials": 0.4, "nothing": 0.2}
@export var wreck_materials := 3
## 血月：迎着它钓，这一夜剩下的，每层水里各级再往高偏多少；钓上来的祭值加多少
@export var blood_moon_tilt := 0.35
@export var blood_moon_bonus := 0.2
## 亡魂（阶段 V）：接过它递来的道具，寒气透骨，饱腹掉多少
@export var ghost_hunger := 15.0
## 暴雨（阶段 V）：冒雨钓，这一夜剩下的，每抛一竿多掉多少饱腹、分解每条多几份材料
@export var storm_hunger := 3.0
@export var storm_materials := 1
## 冥市的赌徒（阶段 V）：押上的那一条，赢了祭值多一倍的机会（输了就没了）
@export_range(0.0, 1.0) var gambler_win := 0.5

@export_group("能力与船舱")
## 契约者的能力档（1–3）：体力、收线这些本事是几档，搏斗的强弱表（fight_gaps）按它查。2026-11-04 去掉了玩家等级（生吞不再升级），
## 新的机制接进来之前先跟着夜数走：第 1、2……夜各是几档（补偿之夜按最后一项）。和原来肯吃的玩家升级的节奏差不多
@export var ability_by_night := PackedInt32Array([1, 1, 2, 2, 3, 3, 3])
## 船舱的载荷上限（2026-11-04：原来跟着灵魂等级 3 / 5 / 9，改成一样大，以后用别的机制加）
@export var hold_capacity := 20

@export_group("饱腹")
## 契约者的饱腹（0–hunger_max），签约时是满的，跟着契约过夜（核心调整 G3，设计对照文档 8.3）
@export var hunger_max := 100.0
## 饱腹跟着捕猎行动扣（新回合机制第 36 条）：每抛一竿扣 hunger_per_cast，搏斗里每耗 1 点体力再扣 hunger_per_stamina
## （难打的一场多吃掉几口）。看说明、整理船舱、制饵的时候不扣
@export var hunger_per_cast := 4.0
@export var hunger_per_stamina := 0.05
## 生吞一条加的饱腹 = hunger_per_body × 躯体规模^hunger_body_power × 词条的倍率（多肉 1.4、枯瘦 0.6）：
## 0.3（小型）约 8，1（中型）17，3（大型）约 33，8（巨型）约 59，25（畸变）约 117。
## 17 是 2026-11-04 换成躯体规模以后按整局模拟器重定的（原来按公斤是 12）：幼年的大多成了小型，12 的话吃得不够，
## 三种走法偿清掉了 4–11 个点；17 和换以前差不多
@export var hunger_per_body := 17.0
@export var hunger_body_power := 0.6
## 饿了：饱腹低于 hungry_at 的两个数时，体力上限乘 hungry_stamina 里对应的数（−15%、−35%）；
## 最饿那一档，搏斗里体力还掉得快 starving_drain 倍
@export var hungry_at := PackedFloat32Array([60.0, 30.0])
@export var hungry_stamina := PackedFloat32Array([0.85, 0.65])
@export var starving_drain := 1.2

@export_group("契约")
## 一份契约有几夜（交接文档 §2.2 的原型目标）
@export_range(1, 30) var contract_nights := 7
## 邪神给的烙印：供奉不足扣一枚，扣完再不足就死（设计对照文档 3.1 第 2 条）。2026-11-04 灵魂线并进来了：剪线也扣一枚烙印。
## 烙印不会自己长回来，只有续魂丝补得回一枚
@export_range(0, 9) var brands := 3
## 一夜没有钟（新回合机制，设计对照文档第 9 节）：玩家自己唤祂来收供奉。每次结算了的供奉，只要还有下一夜，发这么多份万能饵
@export_range(0, 9) var supply_baits := 3
## 超额线：献上的祭值达到需求的这么多倍，算超额完成（新回合机制第 39 条，先按 150%；供奉后的奖励卡多一张候选）
@export var over_ratio := 1.5
## 供奉后的奖励卡（新回合机制 9.6，H2）：不够 / 够了 / 超额时各给几张候选，选一张。偿清了、死了不给
@export var reward_choices := PackedInt32Array([0, 2, 3])
## 每一夜黄昏要献多少祭值（第 1、2……夜；核心调整 G2）。最后一夜之后的补偿周期按最后一夜算，不再涨（设计对照文档第 3 条）。
## 2026-11-04 重测（docs/测量与预算.md"去掉玩家等级以后"）：能力档跟着夜数走、船舱 20、剪线扣烙印以后，原来的 1,600–12,000 太松
## （第 5 夜起就在渊底，一口九千多，九成九偿清、一夜两口不到）；三枚烙印又要顶供奉、又要顶剪线，需求也不能太狠。
## 这样定，达标就收 98%、多拆续钓 94%、先吃再备 84% 偿清，一夜三口上下，一份契约 12–15 分钟。
## 2026-11-04 接上永久恩赐（开局一张、每次结算挑一张）、冥海侵蚀和海况以后，原来的 1,800–16,000 太松（100% / 92% / 91%），
## 第 2 夜起抬了两成上下：达标就收 98%、先吃再备 88%、多拆续钓 88%（docs/测量与预算.md"永久恩赐、侵蚀和海况"）
@export var offering_demand := PackedInt32Array([1800, 2400, 4600, 5800, 12000, 15500, 19500])

@export_group("强弱")
## 契约者能力 1、2、3 档时（原来是灵魂 1–3 级），对上 1–5 级的生物算差几级（每行五个数，三行；正数是它更强），TensionModel 按它定难易。
## 2026-11-03 定的：1 级和 1 级的相当，2 级的是较强的对手（操作得当五成钓得上，算上硬撑），3 级以上远超自己，
## 一咬钩必定耗尽体力、只能剪线；2 级和 2、3 级的相当，4 级的较强（五成），5 级的钓不上；3 级和 4 级的相当，
## 5 级的较强，但七成钓得上。差 1 级、0.9 级是照着搏斗机器人（普通的手，算上硬撑）测的：差 1 级四五成、0.9 级七成
## （tests/test_fishing.tscn）。生物自己的挣扎和耐力只差一点点，时期也不改它们：强弱主要看差几级
@export var fight_gaps := PackedFloat32Array([0, 1, 2, 3, 4,  -1, 0, 0, 1, 2,  -3, -2, -1, 0, 0.9])
## 差这么多级以上（远超自己），体力耗尽时硬撑必输：只能剪线
@export var gamble_max_gap := 1.5

@export_group("自动垂钓")
## 开不开放（2026-11-04 你说先暂时禁用，完善以后再开放）：false 时 Q 不起作用，按键提示里也不写；改成 true 就回来了
@export var auto_fishing_enabled := false
## 自动垂钓（2026-11-04）：只打和契约者相当或更弱的（等级差 < 0.5），不剪线、不碰烙印，体力耗尽就算它跑了。
## 钓上来的机会 = auto_success_even + auto_success_per_level × 弱几级，最多 auto_success_max，再乘饿的档（auto_hunger_mult：不饿、饿了、饿得发慌）。
## 机器人（普通的手）打相当和更弱的是百分之百，自动比亲手打差一点：相当的八成五，弱一级九成二，弱两级以上九成九
@export var auto_success_even := 0.85
@export var auto_success_per_level := 0.07
@export var auto_success_max := 0.99
@export var auto_hunger_mult := PackedFloat32Array([1.0, 0.95, 0.85])
## 一场自动搏斗耗多少体力（按耗的体力扣饱腹，和亲手打一样）：相当的 auto_stamina_even，弱一级以上 auto_stamina_weak
## （tests/auto_probe.tscn 量的普通的手：38、14），饿得发慌时乘 starving_drain
@export var auto_stamina_even := 38.0
@export var auto_stamina_weak := 14.0
## 自动收线在画面上走多久（秒）；自动下一竿之前歇多久
@export var auto_reel_seconds := 2.6
@export var auto_cast_delay := 1.2

@export_group("搏斗")
## 契约者的体力上限；每次上钩回满（设计对照文档 3.2 第 10 条）
@export var stamina_max := 100.0
## 按住收线时每秒消耗的体力（和对手同级时）
@export var reel_drain := 5.0
## 张力进了红区（≥ red_tension）时每秒额外消耗的体力：线拉不断，力气全压在人身上
@export var red_tension := 0.95
@export var red_drain := 24.0
## 线放到头、被它直接拽着时每秒消耗的体力（再乘它这一下的拉力）
@export var drag_drain := 14.0
## 松开、没被拽着、不在红区时每秒恢复的体力（同级时）；对手每高一级减半，高两级以上不再恢复
@export var recover_rate := 3.0
## 对手每强一级：收线耗的体力 ×2，挣扎的拉力 +55%，收线速度 −25%，它的耐力掉得慢 25%（弱则反过来）。
## 2026-11-03 按强弱表重测的（原来 ×1.35、+25%、−15%、15%）：强一级的，普通的手五成钓得上（算上硬撑）
@export var level_drain_factor := 2.0
@export var level_pull_step := 0.55
@export var level_reel_step := 0.25
@export var level_endurance_step := 0.25
## 线松着时每秒挣脱的概率（同级时，对手每高一级少 15%）；不挣扎时松手，它慢慢往外游，每秒这么多米（同级时，每高一级快 40%）
@export var slip_chance := 0.3
@export var swim_speed := 0.6

@export_group("硬撑")
## 体力耗尽后，决定剪线还是硬撑的时间（秒）；不选就算硬撑
@export var last_stand_seconds := 3.0
## 硬撑钓上来的概率 = 基础 + 它累的程度（0–1）× fatigue − 等级差 × per_level，夹在 min 到 max 之间；
## 设计对照文档 3.1 第 5 条：大概率落水（当场死亡），小概率钓上
@export var gamble_base := 0.12
@export var gamble_fatigue := 0.3
@export var gamble_per_level := 0.05
@export var gamble_min := 0.03
@export var gamble_max := 0.45

@export_group("饵料")
## 做一份饵能挂几次：一份饵挂一次，真有生物咬钩才扣（新回合机制第 30 条，2026-11-02 改）：什么也没咬、收竿太早、捞到东西都不扣；
## 咬了钩以后没提、没来得及提竿、脱钩、剪线、落水都算用掉了
@export var bait_uses := 1
## 基础组合和生物的材料比例"合不合"的放大：权重 ∝ 吻合度^这个数，越大饵料的倾向越分明
@export var bait_match_power := 2.0
## "什么也没咬"（第 32 条）：对路的饵是 nothing_chance；饵和这层水里最合它的那种生物也不合时，最多再加 mismatch_nothing；
## 万能饵固定 universal_nothing。空竿不扣饵，但白等九秒、照样扣饱腹：对路的饵不该空得比万能饵还多
@export_range(0.0, 1.0) var nothing_chance := 0.08
@export_range(0.0, 1.0) var mismatch_nothing := 0.2
@export_range(0.0, 1.0) var universal_nothing := 0.1
## 新契约者开局带的东西（第 34 条）：几份万能饵、附加物；不送基础材料（原来送血肉 4、矿壳 2、幽光 2，还能做四份）
@export_range(0, 9) var start_baits := 3
@export var start_materials := {}
@export var start_additives := {"rotten_harpy_egg": 1, "drowned_nail": 1, "phosphor_bug": 1}

@export_group("道具")
## 抛竿时捞到东西（不是生物）的概率；捞到东西不扣饵（第 30 条）。附加物只从这里补，
## 一份契约只有二十多竿，从 6% 提到 10%（第 35 条）
@export_range(0.0, 1.0) var salvage_chance := 0.1
## 捞上来的是什么：道具或附加物的 id → 权重。附加物也从这里补（交接文档 §5.3 待定，先这样）。
## 2026-11-04 起祂不再赐道具：道具只从这里捞，或者超额供奉以后的道具卡（data/cards/item_*.tres）
@export var salvage_table := {"soul_thread": 1.0, "soul_nail": 1.0, "abyss_eye": 1.0,
	"rotten_harpy_egg": 1.5, "drowned_nail": 1.5, "phosphor_bug": 1.5}

@export_group("船舱")
## 幼年期、成长期、成年期各占多少载荷（核心调整第 25 条）。原来按灵魂等级 1 / 2 / 4 / 8 / 16，三级以上放不进一级船，
## 改收祭值以后每夜能献的几乎不涨；按时期算，越强的成年个体越值得留。载荷上限见 hold_capacity
@export var load_by_stage := PackedInt32Array([1, 2, 3])


## 按下标取表里的值，越界时取两端；table 是 Array 或 Packed*Array
static func pick(table, index: int, fallback = 0):
	if table.is_empty():
		return fallback
	return table[clampi(index, 0, table.size() - 1)]


## 第 night 夜黄昏要多少祭值；补偿周期按最后一夜算
func demand_for(night: int) -> int:
	return pick(offering_demand, mini(night, contract_nights) - 1, 8000)


## 按权重表（id → 权重）抽一个 id；表是空的返回 ""
static func roll_table(table: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for id in table:
		total += maxf(float(table[id]), 0.0)
	var r := rng.randf() * total
	for id in table:
		r -= maxf(float(table[id]), 0.0)
		if r < 0.0:
			return id
	return ""


## 第 depth 层水里 1–5 级各占的比例（layer_levels 的一行，没归一）
func levels_at(depth: int) -> Array[float]:
	var row := clampi(depth, 0, maxi(0, layer_levels.size() / 5 - 1)) * 5
	var result: Array[float] = []
	for i in 5:
		result.append(maxf(layer_levels[row + i], 0.0) if layer_levels.size() > row + i else 0.0)
	return result


## 能力 ability 档的契约者对上 fish_level 级的生物，算差几级（正数是它更强）
func fight_gap(ability: int, fish_level: int) -> float:
	var row := clampi(ability - 1, 0, maxi(0, fight_gaps.size() / 5 - 1)) * 5
	var i := row + clampi(fish_level - 1, 0, 4)
	return fight_gaps[i] if i < fight_gaps.size() else float(fish_level - ability)


## 第 night 夜契约者是几档能力（补偿之夜按最后一项）
func ability_for(night: int) -> int:
	return pick(ability_by_night, night - 1, 1)


## 自动垂钓对上差 gap 级的生物（只打 gap < 0.5 的），饱腹是 hunger 时钓上来的机会
func auto_success(gap: float, hunger: float) -> float:
	var p := minf(auto_success_max, auto_success_even + auto_success_per_level * maxf(-gap, 0.0))
	return p * pick(auto_hunger_mult, hunger_tier(hunger), 1.0)


## 一场自动搏斗耗多少体力：相当的多，弱一级以上少；饿得发慌时掉得快
func auto_stamina(gap: float, hunger: float) -> float:
	return lerpf(auto_stamina_weak, auto_stamina_even, clampf(gap + 1.0, 0.0, 1.0)) * stamina_drain_mult(hunger)


## 只差一级的种类，成长期的个体算高的那一级的机会（灵魂强度过了门槛：growth_up_soul，按正态分布算）
func growth_up_chance() -> float:
	return 1.0 - normal_cdf(growth_up_soul / maxf(soul_spread, 0.001))


## 标准正态分布的累积概率（Abramowitz–Stegun 7.1.26，误差不到 1e-6）
static func normal_cdf(z: float) -> float:
	var x := absf(z) / sqrt(2.0)
	var t := 1.0 / (1.0 + 0.3275911 * x)
	var erf := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x)
	return 0.5 * (1.0 + (erf if z >= 0.0 else -erf))


## 这个时期（CatchData.Stage）的个体占多少载荷
func load_for_stage(stage: int) -> int:
	return pick(load_by_stage, stage, 1)


## level 级生物的平均能量（不算个体的浮动、词条）
func energy_for(level: int) -> float:
	return pick(energy_by_level, level - 1, 10.0)


## 这一级生物的平均灵魂强度（不算时期的偏移）
func mean_soul(level: int) -> float:
	return soul_base + soul_per_level * (level - 1)


## 饿的档：0 不饿，1 饿了（饱腹 < 60），2 饿得发慌（< 30）
func hunger_tier(hunger: float) -> int:
	var tier := 0
	for line in hungry_at:
		if hunger < line:
			tier += 1
	return tier


## 饱腹是 hunger 时，体力上限是满的几成
func stamina_cap(hunger: float) -> float:
	var tier := hunger_tier(hunger)
	return 1.0 if tier == 0 else pick(hungry_stamina, tier - 1, 1.0)


## 饱腹是 hunger 时，搏斗里体力掉得快几倍
func stamina_drain_mult(hunger: float) -> float:
	return starving_drain if hunger_tier(hunger) >= hungry_at.size() else 1.0


## 海况的名字
const SEA_NAMES := {"calm": "平静", "rough": "躁动", "eerie": "异化"}


## 掷今夜的海况（sea_weights）
func roll_sea(rng: RandomNumberGenerator) -> String:
	return roll_table(sea_weights, rng)


## 第 night 夜、海况 sea（血月 blood_moon）时生物怎么出的那一份数值表（冥海侵蚀、海况、血月）。只改时期的比例、每层水里各级的比例、灵魂强度、
## 特殊词条的机会；其余照抄。抛竿（CastRoll）、搏斗用它，图鉴、供奉、饱腹还用总表
func for_night(night: int, sea: String, blood_moon := false) -> BalanceConfig:
	var c := duplicate() as BalanceConfig
	var k := float(clampi(night - 1, 0, contract_nights - 1))
	var shares := PackedFloat32Array()
	for s in stage_share.size():
		shares.append(stage_share[s] * maxf(0.0, 1.0 + pick(erosion_stage, s, 0.0) * k))
	c.stage_share = shares
	c.soul_base = soul_base + erosion_soul * k
	c.special_chance_mult = special_chance_mult * (1.0 + erosion_special * k) * (eerie_special if sea == "eerie" else 1.0)
	var tilt := erosion_tilt * k + (-sea_tilt if sea == "calm" else (sea_tilt if sea == "rough" else 0.0)) \
		+ (blood_moon_tilt if blood_moon else 0.0)
	if absf(tilt) > 0.0001:
		var table := layer_levels.duplicate()
		for row in table.size() / 5:
			var idx: Array[int] = []
			for i in 5:
				if table[row * 5 + i] > 0.0:
					idx.append(row * 5 + i)
			if idx.size() < 2:
				continue
			for r in idx.size():
				table[idx[r]] *= maxf(0.05, 1.0 + tilt * (2.0 * r / (idx.size() - 1) - 1.0))
		c.layer_levels = table
	c.night_sea = sea
	c.night_blood_moon = blood_moon
	return c


## 一条躯体规模 body、词条倍率 mult 的渔获生吞了加多少饱腹
func hunger_for(body: float, mult := 1.0) -> int:
	return maxi(1, roundi(hunger_per_body * pow(maxf(body, 0.0), hunger_body_power) * mult))


## 躯体规模的数值是哪一档（0 小型、1 中型、2 大型、3 巨型、4 畸变）：每一档含上限、不含下限（0.5 是小型，0.51 是中型）
func body_class_of(value: float) -> int:
	for k in range(1, body_lines.size() - 1):
		if value <= body_lines[k] + 0.0001:
			return k - 1
	return maxi(0, body_lines.size() - 2)


## 第 cls 档的数值范围 [下限, 上限]（畸变的上限是 body_lines 的最后一个数）
func body_range(cls: int) -> Vector2:
	var k := clampi(cls, 0, body_lines.size() - 2)
	return Vector2(body_lines[k], body_lines[k + 1])


## 第 cls 档里位置 t（0–1，按对数）处的数值：0 是下限、1 是上限、0.5 是中间（两头的几何平均）
func body_at(cls: int, t: float) -> float:
	var r := body_range(cls)
	return r.x * pow(r.y / maxf(r.x, 0.0001), clampf(t, 0.0, 1.0))


## 数值在它那一档里的位置 t（body_at 反过来，进化换档时用：大个的还是大个）
func body_position(value: float) -> float:
	var r := body_range(body_class_of(value))
	return clampf(log(maxf(value, 0.0001) / r.x) / log(maxf(r.y / r.x, 1.0001)), 0.0, 1.0)


## 掷躯体规模用的分布：一个 0–1 的随机数 u 换成档里的位置 t。三角形分布（两个均匀数的平均）：中间的多、两头的少
static func body_quantile(u: float) -> float:
	return sqrt(u * 0.5) if u < 0.5 else 1.0 - sqrt((1.0 - u) * 0.5)


## 第 cls 档按 body_quantile 掷出来的平均数（算个头用）：下限 × ((√比 − 1) ÷ (ln 比 ÷ 2))²，比 = 上限 ÷ 下限
func body_mean(cls: int) -> float:
	var r := body_range(cls)
	var half := log(maxf(r.y / r.x, 1.0001)) * 0.5
	var k := (exp(half) - 1.0) / half
	return r.x * k * k

