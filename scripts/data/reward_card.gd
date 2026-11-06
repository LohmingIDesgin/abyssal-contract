class_name RewardCard
extends Resource
## 供奉后的奖励卡（新回合机制 9.6，H2）：结算了的供奉，只要还有下一夜，除了固定的补给（三份万能饵），
## 够了给两张、超额给三张候选（RewardCards.choice_count），选一张。在 data/cards/ 下新建 .tres 即可添加。
## 2026-11-04（v0.23 第 10 节）起分四类：
## - 永久恩赐（permanent）：这份契约剩下的每一夜都管，换人才没（Contractor.boons）。签约时也先挑一张（RewardCards.draw_opening）
## - 立刻生效：饱餐、余饵、道具卡
## - 一夜卡：壮魂、镇魂、剖腹、引深，留到下一夜里触发，有次数的只触发那么多次，没用掉的到再唤祂时清掉（Contractor.card_effects）

@export var id: String
@export var display_name: String
## 卡面上写的效果
@export_multiline var description: String
## 卡面上写的持续多久："一次"、"下一夜每一场搏斗"、"立刻"
@export var duration: String
## 卡上的小静物（GPT 画的）；还没有的时候卡面上只写字
@export var icon: Texture2D
## 效果——
## 一夜卡：vigor 搏斗里体力多撑 amount（比例）/ lure 下一夜第一次咬钩的换成比你高一级的，直接钓上来（引深）/
##   dissect 处理材料 × amount / steady 搏斗按你高一级算
## 立刻：feast 饱腹 + amount / spare_bait 万能饵 + amount / item 拿到 amount 件道具 item_id
## 永久恩赐（v0.23 第 10.5 节）：
##   evolve 进化：每夜钓上的第一条（成年的不算）长一个时期，幼年的有 amount 的机会直接长成年
##   bone_pick 剔骨：分解时多 amount 份这条身上最多的那种材料 / bait_heart 饵心：两份相同的基础材料做的饵，多给 amount 份
##   carcass 残躯为饵：分解一条以后，这一夜下一条留下的祭值 + amount
##   fed_courage 饱食之勇：生吞以后，下一场搏斗体力消耗 − amount / taut_line 韧线：搏斗里体力消耗一直 − amount
##   blood_lure 血诱：生吞以后，这一夜下一次咬钩的有 amount 的机会换成比你高一级的（照样搏斗）
##   kin 同族之献：献上的同一种族每凑满两条，这两条祭值 + amount，一夜最多加献上总数的 cap
##   oddity 异象收藏：船舱里带特殊词条的，每过一夜祭值 + amount，最多 + cap
##   overflow 满溢之献：超额线改成需求的 amount 倍；超额的那一夜，下一夜的补给多 cap 份
## 阶段 V（2026-11-04）加的：
##   abyss_walker 深渊行者：在比能力档深的水里（深水对 1 档、渊底对 1–2 档）搏斗，体力消耗 − amount
##   regular 冥市熟客：冥市船的价钱 − amount，碰上冥市船的机会 × cap
##   ride_waves 逐浪：躁动、异化的夜里钓上来的，祭值 + amount
##   crown_catch 渔获加冕：每次供奉，献上的最值钱的一条再加它祭值的 amount
##   hungry_offer 空腹之献：饱腹低于 cap 时供奉，献上的总数 + amount
##   bone_flute 骨笛：分解一条成年的以后，下一场搏斗按低一级算（每夜 uses 次）
@export_enum("vigor", "lure", "dissect", "steady", "feast", "spare_bait", "evolve", "item",
	"bone_pick", "bait_heart", "carcass", "fed_courage", "blood_lure", "taut_line", "kin", "oddity", "overflow",
	"abyss_walker", "regular", "ride_waves", "crown_catch", "hungry_offer", "bone_flute") var effect := "vigor"
## 效果的数值（见 effect）
@export var amount := 1.0
## 一夜卡：下一夜里能触发几次；永久恩赐：每一夜能触发几次。0 = 不限（壮魂一整夜都管）。拿到就生效的不看
@export var uses := 1
## 永久恩赐的上限（同族之献、异象收藏），或者附带的数（满溢之献：超额那一夜多给几份饵）
@export var cap := 0.0
## 道具卡给的道具（effect 是 item 时）
@export var item_id := ""
## 只有超额供奉（三张候选）时才抽得到（道具卡，2026-11-04：祂不再赐道具，道具只从这里和打捞来）
@export var over_only := false
## 永久恩赐（v0.23）：这份契约一直管
@export var permanent := false
## 属于哪条引擎，第一个是主的：resource 资源（拆）、capture 捕获（吃 / 搏斗）、tribute 祭值（留 / 献）。
## 抽候选时身上有同标签恩赐的多一点（RewardCards.weight）；签约时三条引擎各出一张（draw_opening）
@export var tags: PackedStringArray = []


## 拿到就生效（饱餐、余饵、道具卡），不留到下一夜
func is_instant() -> bool:
	return effect in ["feast", "spare_bait", "item"]
