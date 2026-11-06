extends Node
## 全程展示的自动操作，配合 Movie Maker 录视频（也能不开画面先跑一遍看流程走到哪）。
## 从签约开始：三份万能饵 → 抛竿 → 咬钩搏斗 → 渔获处理（留、吞、拆）→ 船舱和契约书 → 拆出来的材料做饵 → 道具 → 唤祂（先确认）
## → 黄昏供奉 → 补给与奖励卡（挑一张）→ 后面几夜 → 偿清或者死 → 契约结算清单。
## 所有按键和点击都是模拟的真输入（Input.parse_input_event），游戏本身照常运行；画面下方短暂显示按了什么键、为什么按。
## 一夜没有钟（新回合机制）：船舱里的祭值够了、或者饵用完了材料也做不出来，就按 F 唤祂；能力档到了就往深处钓。数值都是游戏里的。
## 不写试玩日志，不改真的名册（跑完放回原样）。
##
## 录视频（每一帧都渲染、写进 AVI，再用 ffmpeg 转 MP4）：
##   Godot_v4.6.3-stable_win64.exe --path . --write-movie 文件.avi --fixed-fps 30 --resolution 1280x720 res://tests/showcase.tscn
## 先不出画面跑一遍（快；固定帧率，所以和录的那一遍一模一样）：
##   Godot_v4.6.3-stable_win64.exe --headless --path . --fixed-fps 30 res://tests/showcase.tscn
## 想完全不碰真的 user://（名册、Godot 自己的运行日志），跑之前把 APPDATA 临时指到别的空文件夹（Windows 上 user:// 在它下面）。
## 录的时候想要画质好一点、录得快一点：项目根目录临时放一个 override.cfg，写 [editor] movie_writer/mjpeg_quality=0.95
## 和 [display] window/vsync/vsync_mode=0（显示器睡着时开着垂直同步，每帧要等很久），录完删掉。

## 这一局（seed 6）在 2026-11-04 接上永久恩赐、冥海侵蚀和海况以后的样子（没重挑）：签约后开局恩赐挑了韧线，
## 契约已偿（第 7 夜），评价守约，约 10 分钟；捞到过东西、用过窥渊之眼、演示过体力耗尽。要录视频时先重挑。
## 规则或者数值再改，随机数的顺序会变，录之前要重新挑。命令行可以换：-- seed=6
const SEED := 6
const NAME := "莫罗"
const PROMISE := "beloved"  ## 许汝之物：录视频时固定分这一样（被潮水带走的那个人）
const MAX_SECONDS := 1200.0  ## 兜底：超过就收尾
const REEL_AT := 0.68        ## 张力低于这个就按住收线
## 道具栏饵料列：第 i 格的中心；水层格子的中心
const BAIT_SLOT_X := 90.0
const BAIT_SLOT_Y0 := 174.0
const BAIT_SLOT_STEP := 72.0
const DEPTH_TILE := Vector2(90, 66)
const DEPTH_BY_LEVEL := [0, 1, 2]  ## 能力 1–3 档钓哪一层：浅层、深水、渊底（和自己相当的那层）
## 供奉后的奖励卡按这个顺序挑（饿了先挑饱餐）
const CARD_ORDER := ["kin", "evolve", "taut_line", "carcass", "bone_pick", "bait_heart", "fed_courage", "blood_lure", "overflow",
	"oddity", "lure", "spare_bait", "steady", "vigor", "dissect", "feast", "item_soul_thread", "item_soul_nail", "item_abyss_eye"]

var fv
var who: Contractor
var _busy := false
var _ending := ""
var _clock := 0.0
var _shown := {}
var _reel_hold := false
var _react := 0.0
var _exhaust := false        ## 故意一直按住，演示体力耗尽
var _fight_id := 0
var _fight_beats := -1
var _decisions := 0
var _last_phase := 0
var _summon_shown := false
var _brands_lost := 0
var _had_roster := false
var _roster_backup := ""
var _overlay: CanvasLayer
var _pill: PanelContainer
var _pill_label: Label
var _pill_left := 0.0
var _ring: Node2D
var _ring_pos := Vector2.ZERO
var _ring_left := 0.0
var _card: ColorRect
var _card_title: Label
var _card_sub: Label


func _ready() -> void:
	PlayLog._failed = true  ## 不写试玩日志
	_had_roster = FileAccess.file_exists(GameState.ROSTER_PATH)
	_roster_backup = FileAccess.get_file_as_string(GameState.ROSTER_PATH) if _had_roster else ""
	GameState.roster.clear()
	GameState.contractor = GameState._fresh_contractor()
	GameState.contractor.promise = PROMISE
	GameState.baits.clear()
	GameState._give_starter_bait()
	var main = load("res://scenes/main/prototype_main.tscn").instantiate()
	add_child(main)
	fv = main.get_node("钓鱼")
	fv.capture_mouse = false  ## 别把桌面上的鼠标锁进窗口
	fv._rng.seed = SEED
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seed="):
			fv._rng.seed = int(arg.substr(5))
	_build_overlay()
	_run()


func _exit_tree() -> void:
	_restore_roster()


func _log(text: String) -> void:
	print("[%02d:%04.1f] %s" % [floori(_clock / 60.0), fmod(_clock, 60.0), text])


# ---------- 主线 ----------

func _run() -> void:
	await _show_card("冥海契约", "当前版本全程展示　·　阶段 0–E、核心调整 G1–G4、新回合机制 H1–H3（2026-11-04）\n所有操作由脚本以真实按键完成", 4.5)
	await _wait(1.2)
	_log("签约")
	for ch in NAME:
		_type_char(ch)
		await _wait(0.35)
	_show_pill("输入名字：%s" % NAME)
	await _wait(1.0)
	_tap(KEY_ENTER, "回车　签下契约")
	await _on_opening()
	await _wait(4.5)
	who = GameState.contractor
	_log("第 1 夜开始")


func _process(delta: float) -> void:
	_clock += delta
	_update_overlay(delta)
	if fv == null:
		return
	who = GameState.contractor
	if OS.get_cmdline_user_args().has("trace") and fv._phase != _last_phase:
		_log("  阶段 %s → %s　rng=%d 水层=%d 饵=%s 篓=%d 材料=%s" % [fv.Phase.keys()[_last_phase],
			fv.Phase.keys()[fv._phase], fv._rng.state, fv._depth, fv._bait.bases if fv._bait else "",
			GameState.baits.size(), who.materials if who else {}])
		_last_phase = fv._phase
	_update_reel(delta)
	if _busy or _ending != "" or fv._phase == fv.Phase.SIGN and not _shown.has("signed_once"):
		if fv._phase != fv.Phase.SIGN:
			_shown.signed_once = true
		return
	if _clock > MAX_SECONDS:
		_start(_finish.bind("（演示时间到）"))
		return
	match fv._phase:
		fv.Phase.READY:
			_start(_on_ready)
		fv.Phase.BITE:
			_start(_on_bite)
		fv.Phase.REELING:
			if _fight_beats != _fight_id:
				_fight_beats = _fight_id
				_start(_on_fight)
		fv.Phase.LAST_STAND:
			_start(_on_last_stand)
		fv.Phase.RESULT:
			_start(_on_result)
		fv.Phase.DECIDE:
			_start(_on_decide)
		fv.Phase.DUSK:
			if fv._offering.is_open and fv._offering._result.is_empty():
				_start(_on_offering)
		fv.Phase.DEAD:
			_start(_on_dead)
		fv.Phase.SIGN:
			_start(_finish.bind(""))
		fv.Phase.EVENT:
			if fv._event_screen.is_open:
				_start(_on_event)
			elif fv._reward.is_open and fv._reward.gift:
				_start(_on_gift)


func _start(beat: Callable) -> void:
	_busy = true
	await beat.call()
	_busy = false


# ---------- 夜里 ----------

## 准备抛竿：船舱里的祭值够了就唤祂；第一次拆出够做一份饵的材料，打开制饵演示一回；饵用完了先做，做不出来就唤祂
func _on_ready() -> void:
	if who.hold_tribute() >= who.demand():
		await _summon("船舱里的祭值够了")
		return
	if not _shown.has("bench") and _craftable() >= 1:
		_shown.bench = true
		await _bench_first()
		return
	if not _shown.has("contract") and not who.hold.is_empty():
		_shown.contract = true
		await _contract_beat()
		return
	if fv._rack.depth != _depth_for_level():
		_shown.mid = true
		await _change_depth(_depth_for_level())
		return
	if who.brands < who.config.brands and who.items.get("soul_thread", 0) > 0:
		await _wait(0.6)
		_tap(KEY_1, "1　续魂丝：补回一枚烙印")
		_shown.thread = true
		_log("用了续魂丝")
		await _wait(1.5)
	if _bait_uses() == 0:
		if _craftable() >= 1:
			await _bench_refill()
		else:
			await _summon("饵用完了，材料也做不出一份")
		return
	await _wait(0.7)
	_tap(KEY_SPACE, "空格　抛竿（咬钩才用掉一份饵）")
	await _wait(0.5)


## 按 F 唤祂：先出确认（剩几份饵、船舱里的祭值、要多少、超额线），第一次多停一会儿让人看清，再按空格
func _summon(why: String) -> void:
	_log("唤祂：%s（饵 %d 份，船舱里 %s / 要 %s）" % [why, _bait_uses(), Gothic.grouped(who.hold_tribute()), Gothic.grouped(who.demand())])
	await _wait(0.8)
	_tap(KEY_F, "F　唤祂：%s" % why)
	await _wait(1.2)
	if not fv._summon.is_open:
		return
	if not _summon_shown:
		_summon_shown = true
		_show_pill("唤祂之前先确认：剩几份饵、船舱里的祭值、黄昏要多少、超额线；确认以后就不能再钓", 4.0)
		await _wait(4.0)
	else:
		await _wait(1.6)
	_tap(KEY_SPACE, "空格　唤祂")
	await _wait(1.0)


func _on_bite() -> void:
	var gap: float = fv._gap
	await _wait(0.3)
	if fv._lured:
		_shown.lured = true
		_log("引深：咬钩的是 %d 级的%s，提竿直接收上来" % [fv._catch.level, fv._catch.display_name()])
	elif gap >= 1.5 and _shown.has("last_stand") and not _shown.has("declined"):
		_shown.declined = true
		_show_pill("浮漂猛沉：是个大家伙，不提竿，放它走")
		while fv._phase == fv.Phase.BITE:
			await _wait(0.1)
		return
	_fight_id += 1
	_exhaust = false
	_react = 0.25  ## 提竿那一下松开以后，再开始按住收线
	_tap(KEY_SPACE, "空格　提竿")
	await _wait(0.3)


## 上钩以后：第一次有窥渊之眼就用；第二夜在中层钩上比自己强的，故意一直按住，演示体力耗尽
func _on_fight() -> void:
	await _wait(1.2)
	if fv._phase != fv.Phase.REELING:
		return
	var demo: bool = _shown.has("mid") and not _shown.has("last_stand") and who.brands > 1 \
		and (fv._gap >= 0.5 or who.night >= 3)
	if who.items.get("abyss_eye", 0) > 0 and not _shown.has("eye"):
		_shown.eye = true
		_log("用了窥渊之眼")
		_tap(KEY_3, "3　窥渊之眼：看清线那头是什么")
		await _wait(2.0)
	if fv._gap >= 0.5 and who.items.get("soul_nail", 0) > 0 and not _shown.has("nail") and not demo \
			and fv._phase == fv.Phase.REELING:
		_shown.nail = true
		_log("用了镇魂钉")
		_tap(KEY_2, "2　镇魂钉：这一场按高一级算")
		await _wait(1.5)
	if fv._phase == fv.Phase.REELING and demo:
		_exhaust = true
		_log("演示体力耗尽")
		_show_pill("一直按住空格硬拉：张力进红区，体力很快耗尽", 4.0)


func _on_last_stand() -> void:
	await _wait_real(1.6)
	if who.brands > 0:
		_tap(KEY_X, "X　剪线：扣一枚烙印")
	else:
		_tap(KEY_SPACE, "空格　硬撑")
	_shown.last_stand = true
	_exhaust = false
	await _wait_real(2.0)


func _on_result() -> void:
	if fv._status.text.begins_with("你把它拉了上来"):
		_log("捞上来：%s" % fv._status.text)
		_shown.salvage = true
	await _wait(1.4)
	if fv._phase != fv.Phase.RESULT:
		return
	_tap(KEY_SPACE, "空格　继续")
	await _wait(0.5)


func _on_decide() -> void:
	await _wait(3.4)
	if fv._phase != fv.Phase.DECIDE:
		return
	if fv._reveal.is_item():  ## 捞上来的东西也亮相一下：空格收下
		_tap(KEY_SPACE, "空格　收下")
		await _wait(1.2)
		return
	var c: CatchData = fv._catch
	if fv._reveal._note.begins_with("进化"):
		_shown.evolved = true
		_log(fv._reveal._note)
	var action := _choose(c)
	if action == "swap":
		await _swap_out(_worse_kept(c))
		action = "keep" if who.can_keep(c) else "eat"
		if fv._phase != fv.Phase.DECIDE:
			return
	var keys := {"keep": KEY_1, "eat": KEY_2, "dismantle": KEY_3}
	var names := {"keep": "1　留下：放进船舱，黄昏供奉用", "eat": "2　生吞：顶饿",
		"dismantle": "3　处理：拆成三类材料"}
	_tap(keys[action], names[action])
	_decisions += 1
	_log("钓上 %d 级%s%s（祭值 %s，饱腹 +%d；契约者饱腹 %.0f）→ %s" % [c.level, c.stage_name(), c.display_name(),
		Gothic.grouped(c.tribute), c.food, who.hunger, action])
	await _wait(2.2)


## 渔获怎么分：
## - 值得留的（祭值有今夜需求的两成）：船舱里的祭值还不够需求的 1.3 倍就留；放不下就打开契约书把祭值更低的那条处理掉再留
## - 第二、三条依次演示生吞、处理
## - 其余：饿了就生吞；手里的饵（篓里的加上材料还做得出的）不到两份就处理；不然留进船舱带到下一夜（船舱 20），放不下才处理
func _choose(c: CatchData) -> String:
	var demand := who.demand()
	var useful := c.tribute >= demand * 0.2
	var short := who.hold_tribute() < demand * 1.3
	if useful and short and who.can_keep(c):
		return "keep"
	if useful and short and _worse_kept(c) != null:
		return "swap"
	if _decisions == 1:
		return "eat"
	if _decisions == 2:
		return "dismantle"
	if who.hunger_tier() >= 1:
		return "eat"
	if _bait_uses() + _craftable() < 2 or not who.can_keep(c):
		return "dismantle"
	return "keep"


## 船舱里可以换出来给 c 腾地方的那条：祭值比 c 低、换掉以后放得下
func _worse_kept(c: CatchData) -> CatchData:
	var best: CatchData = null
	for k in who.hold:
		if k.tribute >= c.tribute or who.free_load() + k.load_cost < c.load_cost:
			continue
		if best == null or k.tribute < best.tribute:
			best = k
	return best


## 看渔获的时候打开契约书，把船舱里那条更差的处理掉，再合上
func _swap_out(k: CatchData) -> void:
	if k == null:
		return
	_log("船舱满了：处理掉%s（祭值 %s）腾地方" % [k.display_name(), Gothic.grouped(k.tribute)])
	_tap(KEY_TAB, "Tab　船舱满了：打开契约书")
	await _wait(4.0)
	var index := who.hold.find(k)
	for i in index:
		_tap(KEY_RIGHT, "→　选中更差的那条")
		await _wait(0.6)
	_tap(KEY_2, "2　处理掉%s，腾出位置" % k.display_name())
	await _wait(1.6)
	_tap(KEY_TAB, "Tab　合上契约")
	await _wait(2.0)


# ---------- 制饵、船舱、换水层 ----------

## 第一次拆出够做一份饵的材料：打开制饵，放两份基础材料和一份附加物，看这瓶饵在别的水层招来什么，做一份
func _bench_first() -> void:
	_log("制饵")
	_show_pill("拆出来的材料够做一份饵了：两份基础材料 + 一份附加物，一份饵挂一次", 3.5)
	await _wait(1.0)
	_tap(KEY_E, "E　打开制饵")
	await _wait(1.8)
	var bases := _craftable_bases()
	for m in bases:
		var key: int = KEY_1 + Materials.ALL.find(m)
		await _pick(key, "%d　%s" % [key - KEY_0, Materials.DISPLAY[m]])
	await _pick(KEY_4, "4　皮屑肉糜混合物（用不完的基础款）")
	await _wait(1.0)
	_tap(KEY_RIGHT, "→　看这瓶饵在中层招来什么")
	await _wait(2.0)
	_tap(KEY_LEFT, "←　回到浅滩")
	await _wait(0.8)
	_tap(KEY_SPACE, "空格　制作")
	await _wait(2.0)
	_tap(KEY_E, "E　回到船上")
	await _wait(1.4)


## 饵用完了：打开制饵，用身上的材料能做几份做几份（最多三份）
func _bench_refill() -> void:
	_log("饵用完了，用拆出来的材料做")
	_tap(KEY_E, "E　制饵")
	await _wait(1.6)
	var made := 0
	while made < 3 and _craftable() >= 1:
		var bases := _craftable_bases()
		_tap(KEY_BACKSPACE, "退格　清空")
		await _wait(0.4)
		for m in bases:
			var key: int = KEY_1 + Materials.ALL.find(m)
			await _pick(key, "%d　%s" % [key - KEY_0, Materials.DISPLAY[m]])
		await _pick(KEY_4, "4　皮屑肉糜混合物")
		_tap(KEY_SPACE, "空格　制作")
		made += 1
		await _wait(1.3)
	_tap(KEY_E, "E　回到船上")
	await _wait(1.2)


func _contract_beat() -> void:
	_log("契约书")
	await _wait(0.6)
	_tap(KEY_TAB, "Tab　打开契约书：烙印、能力档、船舱")
	await _wait(5.5)
	if who.hold.size() > 1:
		_tap(KEY_RIGHT, "→　选下一条")
		await _wait(1.5)
	_tap(KEY_TAB, "Tab　合上契约")
	await _wait(1.5)


## 能力档到了就往深处钓（和整局模拟器的走法一样，DEPTH_BY_LEVEL）
func _depth_for_level() -> int:
	return DEPTH_BY_LEVEL[clampi(who.ability - 1, 0, DEPTH_BY_LEVEL.size() - 1)]


## 点水层格子换到 depth：左键往深处一层、右键往浅处一层
func _change_depth(depth: int) -> void:
	var names: Array = GameDB.DEPTH_NAMES
	_log("换到%s" % names[depth])
	await _wait(0.8)
	while fv._rack.depth != depth:
		var deeper: bool = depth > fv._rack.depth
		var next: int = fv._rack.depth + (1 if deeper else -1)
		_click(DEPTH_TILE, not deeper, "%s水层格子　换到%s" % ["点" if deeper else "右键", names[next]])
		await _wait(1.2)
	await _wait(0.8)


# ---------- 黄昏 ----------

func _on_offering() -> void:
	_log("黄昏供奉：要 %s，船舱里 %s" % [Gothic.grouped(who.demand()), Gothic.grouped(who.hold_tribute())])
	await _wait(3.2)
	var pick := _pick_offering()
	if pick.is_empty():
		_show_pill("船舱里的祭值凑不够 %s：一条也不献，留着带到下一夜（渔获不会腐坏）" % Gothic.grouped(who.demand()), 3.2)
		await _wait(3.2)
	for i in pick:
		var c: CatchData = who.hold[i]
		_tap(KEY_1 + i, "%d　挑出%s（祭值 %s）" % [i + 1, c.display_name(), Gothic.grouped(c.tribute)])
		await _wait(0.9)
	await _wait(0.6)
	_tap(KEY_SPACE, "空格　献上")
	await _wait(3.8)
	var r: Dictionary = fv._offering._result
	_log("供奉：献上 %s / 要 %s → %s" % [Gothic.grouped(r.tribute), Gothic.grouped(r.demand), "够了" if r.met else "不够"])
	if r.brand_lost:
		_brands_lost += 1
	if r.repaid:
		_ending = "repaid"
	_tap(KEY_SPACE, "空格　继续")
	await _wait(1.0)
	if r.repaid:
		await _on_settlement()
		await _finish("契约已偿")
	elif not r.died:
		await _on_reward()


## 签约以后的开局恩赐（v0.23）：三条引擎各一张，按 CARD_ORDER 挑
func _on_opening() -> void:
	while not fv._reward.is_open:
		await _wait(0.2)
	var cards: Array = fv._reward.cards
	await _wait(2.6)
	var best := 0
	for i in range(cards.size() - 1, -1, -1):
		if _rank(cards[i].id) < _rank(cards[best].id):
			best = i
	var card: RewardCard = cards[best]
	_log("开局恩赐：%s → 挑了%s" % ["、".join(cards.map(func(x: RewardCard) -> String: return x.display_name)), card.display_name])
	_tap(KEY_1 + best, "%d　挑「%s」（%s）" % [best + 1, card.display_name, card.duration])
	await _wait(1.6)
	_tap(KEY_SPACE, "空格　收下")
	await _wait(1.2)


## 海上事件（阶段 IV）：停一下让人看清；残骸手里饵够就钩，冥市船买得起恩赐就换，其余的都不接
func _on_event() -> void:
	await _wait(2.8)
	if not fv._event_screen.is_open:
		return
	var ev: Dictionary = fv._event_screen.event
	var opts: Array = SeaEvents.options(ev, who, fv._bait_count())
	var pick := -1
	if ev.id == "wreck" and fv._bait_count() >= 2:
		pick = 0
	elif ev.id == "trade" and not opts.is_empty() and opts[0].enabled and ev.offers[0].kind == "boon":
		pick = 0
	_log("海上事件：%s → %s" % [SeaEvents.NAMES.get(ev.id, ev.id), opts[pick].label if pick >= 0 else SeaEvents.LEAVE.get(ev.id, "离开")])
	if pick >= 0:
		_tap(KEY_1 + pick, "%d　%s" % [pick + 1, opts[pick].label])
	else:
		_tap(KEY_SPACE, "空格　%s" % SeaEvents.LEAVE.get(ev.id, "离开"))
	await _wait(1.6)


## 祂的低语给的恩赐（全程展示不接低语，这里只是兜底）：挑第一张
func _on_gift() -> void:
	await _wait(2.4)
	_tap(KEY_1, "1　挑一张")
	await _wait(1.0)
	_tap(KEY_SPACE, "空格　收下")
	await _wait(1.2)


## 卡在 CARD_ORDER 里排第几（不在里面的排最后）
func _rank(id: String) -> int:
	var i := CARD_ORDER.find(id)
	return i if i >= 0 else CARD_ORDER.size()


## 供奉后的补给与奖励卡：有候选就按 CARD_ORDER 挑一张（饿了先挑饱餐），停一下让人看清，再收下；没凑够只有补给，直接继续
func _on_reward() -> void:
	while not fv._reward.is_open:
		await _wait(0.2)
	var cards: Array = fv._reward.cards
	await _wait(2.4 + 0.15 * cards.size())
	if cards.is_empty():
		_tap(KEY_SPACE, "空格　继续：没凑够，只有补给")
		await _wait(1.6)
		return
	var best := 0
	for i in range(cards.size() - 1, -1, -1):
		var hungry_feast: bool = who.hunger_tier() >= 1 and cards[i].id == "feast"
		if hungry_feast or _rank(cards[i].id) < _rank(cards[best].id) and not (who.hunger_tier() >= 1 and cards[best].id == "feast"):
			best = i
	var card: RewardCard = cards[best]
	_log("奖励卡：%s → 挑了%s" % ["、".join(cards.map(func(x: RewardCard) -> String: return x.display_name)), card.display_name])
	_shown.cards = true
	_tap(KEY_1 + best, "%d　挑「%s」（%s）" % [best + 1, card.display_name, card.duration])
	await _wait(1.8)
	_tap(KEY_SPACE, "空格　收下：补给和这张卡")
	await _wait(1.6)


## 从船舱里挑一组：祭值够需求、多出来的（按比例）最少；凑不够就一条也不挑。船舱里多于 12 条时只在最值钱的 12 条里挑
func _pick_offering() -> Array:
	var hold := who.hold
	var need := who.demand()
	var order := range(hold.size())
	order.sort_custom(func(a: int, b: int) -> bool: return hold[a].tribute > hold[b].tribute)
	order = order.slice(0, 12)
	var best: Array = []
	var best_score := INF
	for mask in range(1, 1 << order.size()):
		var tribute := 0
		var pick: Array = []
		for j in order.size():
			if mask & (1 << j):
				var i: int = order[j]
				pick.append(i)
				tribute += hold[i].tribute
		if tribute < need:
			continue
		var score := float(tribute - need) / maxf(need, 1.0) * 1000.0 + pick.size()
		if score < best_score:
			best_score = score
			best = pick
	return best


func _on_dead() -> void:
	_ending = "dead"
	_log("死了")
	while fv._death.busy:
		await _wait(0.2)
	await _wait(1.5)
	_tap(KEY_SPACE, "空格　继续")
	await _on_settlement()
	await _finish("坠入冥海" if fv._death_cause == "fall" else "被祂吞噬")


## 结算清单：等字都浮出来，停一会儿让人看清，再按空格去签下一位
func _on_settlement() -> void:
	while not fv._settlement.is_open:
		await _wait(0.2)
	_log("结算：%s，评价 %s" % [Settlement.outcome_text(fv._pending_record), fv._pending_record.get("rating", "")])
	_show_pill("契约结算清单：许汝之物、结局和评价、献上的祭值、献过的种类和时期", 4.0)
	while fv._settlement.busy:
		await _wait(0.2)
	await _wait(3.5)
	_tap(KEY_SPACE, "空格　下一位契约者")
	await _wait(3.0)


func _finish(outcome: String) -> void:
	_ending = "done"
	_log("收尾：%s" % outcome)
	print("SUMMARY seed=%d outcome=%s t=%.0f shown=%s brands_lost=%d" % [fv._rng.seed, outcome, _clock,
		",".join(_shown.keys()), _brands_lost])
	await _show_card("演示结束", outcome + "\n名册上记下了这一位", 4.0, true)
	_restore_roster()
	get_tree().quit()


# ---------- 小事 ----------

func _bait_uses() -> int:
	var n := 0
	for b in GameState.baits:
		n += b.uses
	return n


## 身上的材料还能做几份饵（两份一份，附加物用基础款）
func _craftable() -> int:
	var n := 0
	for m in Materials.ALL:
		n += who.materials.get(m, 0)
	return n / 2


## 做一份饵用哪两份基础材料：最多的那一类先用，不够两份就搭第二多的
func _craftable_bases() -> Array:
	var order := Materials.ALL.duplicate()
	order.sort_custom(func(a, b) -> bool: return who.materials.get(a, 0) > who.materials.get(b, 0))
	var first: String = order[0]
	if who.materials.get(first, 0) >= 2:
		return [first, first]
	return [first, order[1]]


func _pick(key: int, label: String) -> void:
	_tap(key, label)
	await _wait(0.55)


## 收线：张力低于 REEL_AT 就按住空格，高了就松开（反应慢一点点，像人）；演示体力耗尽时一直按住
func _update_reel(delta: float) -> void:
	var reeling: bool = fv._phase == fv.Phase.REELING and fv._model != null
	if not reeling:
		if _reel_hold:
			_reel_hold = false
			_key(KEY_SPACE, false)
		return
	var want: bool = _exhaust or fv._model.tension < REEL_AT
	_react -= delta
	# 以游戏里按没按住为准：提竿那一下的松开、别的按键都不会让这里和游戏对不上
	if want != fv._holding and _react <= 0.0:
		_react = 0.1
		_reel_hold = want
		_key(KEY_SPACE, want)
	if not _exhaust and _pill_left <= 0.0:
		_show_pill("按住空格收线　·　松开放线：张力停在青色区域", 0.6)


func _key(keycode: int, pressed: bool, unicode := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = pressed
	e.unicode = unicode
	Input.parse_input_event(e)


func _tap(keycode: int, label: String) -> void:
	_show_pill(label)
	_key(keycode, true)
	await _wait(0.1)
	_key(keycode, false)


func _type_char(ch: String) -> void:
	_key(KEY_NONE, true, ch.unicode_at(0))
	_key(KEY_NONE, false, ch.unicode_at(0))


## 点一下骨架栏（水层格子、饵料格）：画一个点击圈，把这一下鼠标按键直接交给骨架栏自己的 _gui_input。
## 不走 Input.parse_input_event：不开画面跑的时候鼠标事件到不了界面，先跑的那一遍就和录的那一遍对不上
func _click(pos: Vector2, right: bool, label: String) -> void:
	_show_pill(label)
	_ring_pos = pos
	_ring_left = 0.6
	var b := InputEventMouseButton.new()
	b.position = pos - fv._rack.global_position
	b.global_position = pos
	b.button_index = MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
	b.pressed = true
	fv._rack._gui_input(b)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _restore_roster() -> void:
	if _had_roster:
		var f := FileAccess.open(GameState.ROSTER_PATH, FileAccess.WRITE)
		if f:
			f.store_string(_roster_backup)
			f.close()
	elif FileAccess.file_exists(GameState.ROSTER_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.ROSTER_PATH))


# ---------- 画面上加的：按键提示、点击圈、开头和结尾 ----------

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	_pill = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.035, 0.72)
	style.border_color = Color(Gothic.BRONZE_LIGHT, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 5
	_pill.add_theme_stylebox_override("panel", style)
	_pill_label = Gothic.label("", 16, Gothic.BONE, 3)
	_pill.add_child(_pill_label)
	_pill.modulate.a = 0.0
	_overlay.add_child(_pill)
	_ring = Node2D.new()
	_ring.draw.connect(func() -> void:
		if _ring_left > 0.0:
			var k := _ring_left / 0.6
			_ring.draw_arc(_ring_pos, 18.0 + (1.0 - k) * 14.0, 0.0, TAU, 32, Color(Gothic.BRONZE_LIGHT, k), 2.5, true))
	_overlay.add_child(_ring)
	_card = ColorRect.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.color = Color(0.005, 0.01, 0.014, 0.92)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	_overlay.add_child(_card)
	_card_title = Gothic.label("", 44, Gothic.BRONZE_LIGHT, 6)
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_title.position = Vector2(0, 270)
	_card_title.size = Vector2(1280, 60)
	_card.add_child(_card_title)
	_card_sub = Gothic.label("", 18, Gothic.BONE, 4)
	_card_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_sub.position = Vector2(0, 345)
	_card_sub.size = Vector2(1280, 80)
	_card.add_child(_card_sub)


func _show_pill(text: String, seconds := 1.6) -> void:
	_pill_label.text = text
	_pill.reset_size()
	_pill_left = seconds


func _update_overlay(delta: float) -> void:
	_pill_left -= delta
	_pill.modulate.a = clampf(_pill_left / 0.3, 0.0, 1.0)
	var s := _pill.get_combined_minimum_size()
	_pill.position = Vector2(640.0 - s.x * 0.5, 666.0)
	_ring_left = maxf(0.0, _ring_left - delta)
	_ring.queue_redraw()


func _show_card(title: String, sub: String, seconds: float, stay := false) -> void:
	_card_title.text = title
	_card_sub.text = sub
	var t := create_tween()
	t.tween_property(_card, "modulate:a", 1.0, 0.5)
	await t.finished
	await _wait_real(seconds)
	if stay:
		return
	t = create_tween()
	t.tween_property(_card, "modulate:a", 0.0, 0.6)
	await t.finished
