extends Control
## 钓鱼原型：选饵 → 抛竿 → 等待（会有假咬钩）→ 咬钩时提竿 → 张力收线 → 结果。
## 抛竿时就决定了咬钩的是什么、并生成好这条个体（CatchGenerator），搏斗不会改变它。
## 钓上来以后画面压暗、渔获放大浮在正中（CatchReveal），选留下 / 生吞 / 处理才能接着钓（放生 2026-11-04 删了）；
## Tab 打开契约书（契约者、船、船舱里的渔获）。
## 搏斗（TensionModel）：契约者有体力，线拉不断；咬钩时浮漂沉得多猛、上钩后右上角的"对手"都按等级差（契约者的能力档对生物的等级）给出强弱。
## 饱腹（核心调整 G3）：每抛一竿、每场搏斗耗的体力都扣（新回合机制第 36 条），饿了体力上限降一截
## （张力计下面的饱腹管、体力管上饿掉的一截），生吞加回来。
## 搏斗中按 X 剪线（扣一枚烙印，2026-11-04 灵魂线并进了烙印）；体力耗尽时画面放慢，剪线还是硬撑（LastStand），硬撑输了落水即死（DeathScreen），
## 换下一位契约者（GameState.next_contractor）。契约结束（偿清、落水、被吞）以后先出结算清单（SettlementScreen），再签下一位。
## 制饵（E）：BaitBench，盖在压暗的海面上，两份基础材料 + 一份附加物。一份饵挂一次，真有生物咬钩才扣（什么也没咬、收竿太早、
## 捞到东西不扣）；没有空钩：没有饵就不能抛竿（新回合机制第 30、31 条）。
## 一夜没有钟（第 9 节）：按 F（或者点道具栏上"唤祂"那一格）先确认（SummonPrompt），再进黄昏供奉；
## 结算了的供奉，只要还有下一夜，发几份万能饵（Contractor.offer 的 supply）。
## 供奉后的补给与奖励卡（RewardScreen，H2）：补给照给，够了再从两张、超额从三张候选里挑一张，卡的效果到下一夜里触发：
## 引深让第一次咬钩的换成高一级的、提竿就一路收上来（Phase.LURED，不搏斗）；镇魂、壮魂在提竿时用上；进化在钓上来时；剖腹在处理时。
## 图鉴（C，CodexScreen）：准备抛竿、看结果、选去处的时候能开（选去处时翻到刚钓上来的那种）；签约时点"翻看图鉴"。
## 自动垂钓（Q，2026-11-04）：自动抛竿、提竿、收放线，照样扣饵、饱腹；搏斗不演，按等级差和饿不饿算钓上来的机会（BalanceConfig.auto_success），
## 跑了就跑了，不剪线、不碰烙印。钓上来的放得下就留进船舱。比你强的、带特殊词条的、捞到东西的，咬钩那一刻停住（Phase.BITE 不走），
## 你按空格接手提竿、Esc 放它走，自动就关了；船舱放不下、饵用完了也停，交给你。
## 操作：空格，或在水面上按住鼠标左键；X 剪线；E 制饵；Tab 契约书；F 唤祂；C 图鉴。
## 画面分层：WaterView（2D 海面/船/灯/鱼线）→ FirstPersonArms（3D 手和竿，透明 SubViewport）
##          → 后期调色（shaders/grade.gdshader）→ 哥特风 HUD。
## HUD（参照 docs/reference/ui_style.webp）：左上骨架道具栏（水层、能力档、船舱、饵料）、右上张力计、
## 右下罗盘和按键提示、顶部状态文字。字体是思源宋体（系统里有 Noto Serif SC 就用）。

## LURED：引深（奖励卡）引上来的，提竿以后不搏斗，一路收上来；AUTO：自动垂钓收线（不演搏斗）
enum Phase { SIGN, READY, WAITING, BITE, REELING, LAST_STAND, RESULT, DECIDE, DUSK, DEAD, SETTLE, LURED, AUTO, EVENT }

@export_category("船的显示 / Boat")
## 船头顶部在屏幕高度中的位置。越小越靠上，船露出越多；原先为 0.76。
@export_range(0.35, 0.95, 0.01) var boat_screen_top := 0.66:
	set(value):
		boat_screen_top = value
		if is_instance_valid(_water):
			_water.boat_screen_top = value
## 船的宽度占屏幕宽度的比例，保持贴图长宽比。
@export_range(0.6, 1.8, 0.01) var boat_width_ratio := 1.18:
	set(value):
		boat_width_ratio = value
		if is_instance_valid(_water):
			_water.boat_width_ratio = value
## 用 3D 木船（assets/models/木船2.glb）；关掉就是原来的船头贴图（上面两项只管贴图）
@export var boat_3d := true:
	set(value):
		boat_3d = value
		if is_instance_valid(_water):
			_water.use_3d_boat = value
## 3D 木船里人坐的位置（米，船头柱顶 +4.87、船尾 −4.09）：越大越靠前，船头越近、在画面里越大
@export_range(-3.0, 4.0, 0.05) var boat_seat_z := 1.47:
	set(value):
		boat_seat_z = value
		if is_instance_valid(_water):
			_water.boat_seat_z = value
## 转头的范围（度，左右加起来）：移动鼠标、按住 A / D 都能转；黄昏祂出来、签约、死的时候拉回正前方。
## 只有 3D 木船能转（船头贴图是一张固定的画）
@export_range(0.0, 90.0, 5.0) var look_range := 60.0
## 钓鱼时把鼠标藏起来、锁在窗口里，移动鼠标就是转头；按住 Alt、或者打开契约书、制饵、看渔获、供奉时才放出来
## （自动演示、截图工具关掉它，免得抢走桌面上的鼠标）
@export var capture_mouse := true
## 鼠标每移动一个像素转多少（弧度）
@export_range(0.0005, 0.01, 0.0005) var look_sensitivity := 0.0025

const LOOK_KEY_SPEED := 1.0    ## 按住 A / D 每秒转多少（弧度）
const LOOK_RESPONSE := 4.0     ## 视线追上目标的快慢（越大越跟手）
var _look_target := 0.0
var _look_yaw := 0.0

const NIBBLE_TIME := 0.35
const SLOW_MOTION := 0.35          ## 体力耗尽、做决定的时候画面放慢到几倍速
const LAST_STAND_GRACE := 0.6      ## 刚耗尽的这一小会儿不认空格，免得收线时连按的手误选了硬撑（真实时间）
const HOLD_ON_SECONDS := 1.2       ## 选了硬撑以后，咬牙撑多久才见分晓（真实时间）
const LURE_SECONDS := 1.8          ## 引深：提竿以后一路收上来要多久（不搏斗）
## 祂发怒（供奉不够）的四级：世界震多狠（WaterView.quake）、眼睛亮闪多亮（GodPresence.flare）
const ANGER_QUAKE: Array[float] = [0.6, 0.85, 1.1, 1.5]
const ANGER_FLARE: Array[float] = [1.0, 1.3, 1.6, 2.0]
## 后期调色里跟着黄昏变的两样：月光（黄昏是日轮的红光）、雾的颜色。[uniform 名, 黑夜, 黄昏]
const GRADE_DUSK := [["moon_color", Color(0.86, 0.93, 0.92), Color(1.0, 0.4, 0.2)],
	["mist_color", Color(0.42, 0.5, 0.51), Color(0.36, 0.17, 0.13)]]
const GRADE_SHAFTS := 0.35         ## 月光光柱的强度（grade.gdshader 的 shafts 默认值）
## 饿到下一档时日志里的一句（饿了、饿得发慌）
const HUNGER_NOTES: Array[String] = ["肚子空了，体力上限降了一截。", "饿得发慌：体力上限又降了，搏斗里力气也掉得更快。"]

var _phase := Phase.SIGN
var _holding := false
var _rng := RandomNumberGenerator.new()
var _baits: Array[Bait] = []
var _target: FishData
var _catch: CatchData              ## 这一竿咬钩的个体，抛竿时生成
var _bait: Bait                    ## 这一竿挂的饵（真有生物咬钩时扣一份）
var _salvage := ""                 ## 这一竿挂住的不是生物，是一件东西（道具或附加物的 id）
var _steadied := false             ## 这一场钉过镇魂钉了
var _identified := false           ## 这一场用过窥渊之眼了
var _lured := false                ## 这一竿是引深引上来的（CastRoll 的 lured）：提竿以后不搏斗
var _blood := false                ## 这一竿是血诱（恩赐）换来的高一级的（CastRoll 的 blood）：照样搏斗
var _event_id := ""                ## 这一竿等来的是海上事件（CastRoll 的 event，阶段 IV）："" = 不是
var _event: Dictionary = {}        ## 正在看的那件事（SeaEvents.start）
var _event_text := ""              ## 祂的低语：挑恩赐之前先记下的那一行
var _event_screen: EventScreen
var _auto := false                 ## 自动垂钓开着
var _auto_timer := 0.0             ## 自动：离下一竿还有几秒
var _auto_p := 0.0                 ## 自动：这一场钓上来的机会
var _takeover := ""                ## 自动停在咬钩那一刻等你接手（为什么停：比你强的 / 带特殊词条的 / 捞到东西）；"" = 没停
var _model: TensionModel
var _fight_time := 0.0
var _depth := 0
var _timer := 0.0                  ## WAITING：距咬钩的剩余时间；BITE：提竿窗口剩余
var _nibbles: Array[float] = []    ## 假咬钩发生时 _timer 的值，降序
var _nibble_anim := 0.0
var _lateral := 0.0                ## 入水点左右偏移，鱼挣扎时会左右窜
var _cast_flight := 0.0
var _time := 0.0
var _gap := 0.0                    ## 这一竿的对手比契约者强几级（抛竿时定，BalanceConfig.fight_gap）
var _decide_time := 0.0            ## LAST_STAND：已经过去的真实时间
var _holding_on := false           ## LAST_STAND：选了硬撑，正在撑
var _slow_tween: Tween
var _strain_amount := 0.0
var _sky_tween: Tween              ## 天色转红 / 退回去、祂浮出来 / 沉回去
var _night_clock := 0.0            ## 这一夜钓了多久（真实时间；开着界面、看渔获、黄昏时不走）：天气按它放
var _death_cause := "fall"
var _sky_rng := RandomNumberGenerator.new()  ## 天气用的随机数：和 _rng 分开，同一个种子钓到什么、结局都不变
var _weather: Weather              ## 今夜的天气（天黑时定，签约前是 null）
var _birds_flown := false          ## 今夜的大鸟飞过了没有
var _pending_record := {}          ## 刚走的那一位的结算清单（Settlement.record），看完了才记进名册

var _rack: BoneRack
var _water: WaterView
var _grade: ColorRect
var _arms: FirstPersonArms
var _gauge: TensionGauge
var _compass: Compass
var _keys: VBoxContainer
var _hint_list: Array = []
var _status: Label
var _hint: Label
var _log: RichTextLabel
var _reveal: CatchReveal
var _dim: ColorRect
var _captions: VBoxContainer
var _contract: ContractScreen
var _strain: ColorRect             ## 体力见底、生死关头时屏幕四周泛起的暗红
var _last_stand: LastStand
var _death: DeathScreen
var _bench: BaitBench
var _night_bar: NightBar
var _god: GodPresence
var _birds: SkyBirds
var _rain: RainLayer
var _offering: OfferingScreen
var _reward: RewardScreen
var _signing: SigningScreen
var _settlement: SettlementScreen
var _summon: SummonPrompt
var _items: ItemBar
var _qte: BiteQte                  ## 咬钩那一下的 [空格] 提竿！（浮出来、细线往中间收）
var _bite_window := 1.0            ## 这一次咬钩的提竿窗口（秒），QTE 的细线按它收
var _codex: CodexScreen


func _ready() -> void:
	_rng.randomize()
	_sky_rng.randomize()
	_build_ui()
	GameState.baits_changed.connect(_refresh_bait_list)
	GameState.contractor.changed.connect(_refresh_status)
	GameState.contractor_changed.connect(_on_contractor_changed)
	_refresh_bait_list()
	_refresh_status()
	_open_signing()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _look_locked():
		_look_target = clampf(_look_target + event.relative.x * look_sensitivity, -_look_max(), _look_max())
	if not is_visible_in_tree() or not event is InputEventKey or event.echo:
		return
	if _event_screen.is_open:  ## 海上事件：[1]–[3] 选，空格、Esc 不选
		if event.pressed:
			if event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE:
				_event_screen.choose(-1)
			elif event.keycode >= KEY_1 and event.keycode <= KEY_3:
				_event_screen.choose(event.keycode - KEY_1)
		get_viewport().set_input_as_handled()
		return
	if _reward.is_open and (_reward.opening or _reward.gift):  ## 开局恩赐、祂的低语给的恩赐：不在黄昏，[1]–[3] 和空格也给它
		if event.pressed:
			if event.keycode == KEY_SPACE:
				_reward.confirm()
			elif event.keycode >= KEY_1 and event.keycode <= KEY_3:
				_reward.pick(event.keycode - KEY_1)
		get_viewport().set_input_as_handled()
		return
	if _phase == Phase.SIGN or _settlement.is_open or _summon.is_open or _codex.is_open:
		return  ## 签约时按键都给写名字的那一栏；结算清单、唤祂的确认、图鉴自己收按键
	if _phase == Phase.DUSK:
		if event.pressed and _offering.is_open:
			if event.keycode == KEY_SPACE:
				_offering.confirm()
			elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
				_offering.toggle(event.keycode - KEY_1)
			else:
				return
			get_viewport().set_input_as_handled()
		elif event.pressed and _reward.is_open:
			if event.keycode == KEY_SPACE:
				_reward.confirm()
			elif event.keycode >= KEY_1 and event.keycode <= KEY_3:
				_reward.pick(event.keycode - KEY_1)
			else:
				return
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_SPACE and _phase == Phase.DECIDE and _reveal.is_item() and not _contract.is_open:
		if event.pressed:
			_reveal.decide("take")  ## 捞上来的东西：空格收下
	elif event.keycode == KEY_SPACE:
		if not _bench.is_open:
			_set_holding(event.pressed)
		elif event.pressed:
			_bench.craft()
	elif not event.pressed:
		return
	elif _bench.is_open:
		if not _bench_key(event.keycode):
			return
	elif event.keycode == KEY_X and _phase in [Phase.REELING, Phase.LAST_STAND]:
		_cut()
	elif event.keycode == KEY_Q:
		_toggle_auto()
	elif event.keycode == KEY_ESCAPE and _takeover != "":
		_let_go()
	elif event.keycode == KEY_E:
		_open_bench()
	elif event.keycode == KEY_TAB:
		_toggle_contract()
	elif event.keycode == KEY_F:
		_request_summon()
	elif event.keycode == KEY_C:
		_open_codex()
	elif event.keycode == KEY_ESCAPE and _contract.is_open:
		_close_contract()
	elif _contract.is_open and event.keycode >= KEY_1 and event.keycode <= KEY_3:
		_contract.act(event.keycode - KEY_1)
	elif _contract.is_open and event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		_contract.move_selection(-1 if event.keycode in [KEY_UP, KEY_LEFT] else 1)
	elif _phase == Phase.DECIDE and not _contract.is_open and event.keycode >= KEY_1 and event.keycode < KEY_1 + CatchReveal.ACTIONS.size():
		_reveal.decide(CatchReveal.ACTIONS[event.keycode - KEY_1])
	elif event.keycode >= KEY_1 and event.keycode < KEY_1 + ItemBar.ORDER.size() and _phase in [Phase.READY,
			Phase.WAITING, Phase.BITE, Phase.REELING, Phase.LAST_STAND, Phase.RESULT]:
		_use_item(event.keycode - KEY_1)
	else:
		return
	get_viewport().set_input_as_handled()


## 船舱开着、卡片等着选的时候，空格和点水面都不算数
func _set_holding(down: bool) -> void:
	var was_down := _holding
	_holding = down and not _contract.is_open and not _bench.is_open and not _codex.is_open and _phase != Phase.DECIDE
	if _holding and not was_down:
		_on_action()


func _on_action() -> void:
	if _auto and _phase in [Phase.READY, Phase.WAITING, Phase.RESULT]:
		_auto_stop("你接手了")  ## 自动开着的时候自己动手：自动就关了
	match _phase:
		Phase.READY:
			_cast()
		Phase.WAITING:
			PlayLog.event("miss", {"why": "too_early", "target": _target_id()})
			_finish("收竿太早……水面恢复了平静。饵还在。", Color("888888"), FirstPersonArms.Action.HOOK)
		Phase.BITE:
			_takeover = ""
			_hook()
		Phase.LAST_STAND:
			if not _holding_on and _decide_time > LAST_STAND_GRACE:
				_hold_on()
		Phase.RESULT:
			_enter_ready()
		Phase.DEAD:
			_death.confirm()


func _process(delta: float) -> void:
	_time += delta
	match _phase:
		Phase.WAITING:
			_process_waiting(delta)
		Phase.BITE:
			var plunge := _plunge()
			_water.bob = 16.0 * plunge + sin(_time * (30.0 + 5.0 * maxf(_gap, 0.0))) * 3.0 * plunge
			if _takeover == "":  ## 自动停下来等你接手时，提竿窗口不走
				_timer -= delta
				_qte.set_remaining(_timer / maxf(_bite_window, 0.01))
			if _timer <= 0.0:
				_qte.close(false)
				PlayLog.event("miss", {"why": "late", "target": _target_id(), "gap": _gap})
				var message := "没来得及提竿，鱼吐钩跑了。" if _gap < 1.5 else "浮漂浮了上来，那个大家伙沉回了深处。"
				if _salvage != "":
					message = "没来得及，那东西又沉了下去。"
				_finish(message, Color("888888"), FirstPersonArms.Action.SLIPPED)
		Phase.REELING:
			_process_reeling(delta)
		Phase.LAST_STAND:
			_process_last_stand(delta)
		Phase.LURED:
			_process_lured(delta)
		Phase.AUTO:
			_process_auto(delta)
		_:
			_water.bob = sin(_time * 2.0) * 1.5
	_drive_auto(delta)
	_update_strain(delta)
	_tick_night(delta)
	_update_look(delta)
	_update_mouse_mode()
	_sync_presentation()


## 钓鱼时鼠标藏起来、锁在窗口里（移动鼠标就是转头）；按住 Alt、打开界面、窗口没有焦点时放出来
func _update_mouse_mode() -> void:
	var fishing := _phase in [Phase.READY, Phase.WAITING, Phase.BITE, Phase.REELING, Phase.LAST_STAND, Phase.RESULT]
	var free := fishing and not _look_locked() and not _bench.is_open and not _contract.is_open and not _codex.is_open
	var want := Input.MOUSE_MODE_CAPTURED if capture_mouse and free and is_visible_in_tree() \
		and not Input.is_key_pressed(KEY_ALT) and get_window().has_focus() else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want


## 黄昏祂出来、签约、死的时候拉回正前方；制饵、契约书开着时 A / D 不转
func _update_look(delta: float) -> void:
	if _look_locked():
		_look_target = 0.0
	elif not _bench.is_open and not _contract.is_open and not _codex.is_open:
		var turn := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
		if turn != 0.0:
			_look_target = clampf(_look_target + turn * LOOK_KEY_SPEED * delta, -_look_max(), _look_max())
	_look_yaw = lerpf(_look_yaw, _look_target, 1.0 - exp(-LOOK_RESPONSE * delta))
	_water.yaw = _look_yaw


func _look_locked() -> bool:
	return _phase in [Phase.SIGN, Phase.DUSK, Phase.DEAD, Phase.SETTLE] or not _water.use_3d_boat


func _look_max() -> float:
	return deg_to_rad(look_range * 0.5)


## 咬钩时浮漂沉得多猛跟着等级差走：看出是大家伙，可以不提竿放它走（设计对照文档 3.2 第 11 条）
func _plunge() -> float:
	return 1.0 + 0.35 * clampf(_gap, -1.0, 3.0)


## 把钓鱼状态同步给 3D 手臂，再把竿尖位置交回 2D 画面画鱼线
func _sync_presentation() -> void:
	_arms.view = _water.view
	_arms.tension = _water.tension
	_arms.struggling = _water.struggling
	_arms.holding = (_holding and _phase == Phase.REELING) or _phase in [Phase.LURED, Phase.AUTO]
	_arms.bob = _water.bob
	_arms.water_target_screen = _water.water_point()
	_arms.lamp_screen = _water.lamp_screen_position()
	_arms.lamp_energy = _water.lamp_flicker
	_grade.material.set_shader_parameter("lamp_uv", _water.lamp_screen_position() / size)
	_grade.material.set_shader_parameter("lamp_energy", _water.lamp_flicker)
	_grade.material.set_shader_parameter("moon_uv", _water.moon_screen_uv())
	_grade.material.set_shader_parameter("time", _time)
	_grade.material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	for e in GRADE_DUSK:
		_grade.material.set_shader_parameter(e[0], e[1].lerp(e[2], _water.dusk))
	_grade.material.set_shader_parameter("shafts", GRADE_SHAFTS * (1.0 - 0.8 * _water.rain))  ## 下雨时云缝里漏不下月光
	_rain.amount = _water.rain
	_rain.sync(_water, _time)
	_sync_summon_tile()
	_sync_hunger()
	_items.refresh(GameState.contractor, _item_usable)
	_gauge.active = _phase in [Phase.REELING, Phase.LAST_STAND]
	# 罗盘指针指向浮漂/鱼所在的方向（相对视线）；空竿时指着船头
	var bearing := _water.cast_yaw + atan(_water.lateral * WaterView.LATERAL_SPREAD) if _water.view != WaterView.View.IDLE else 0.0
	_compass.heading = (bearing - _water.view_yaw()) * 2.0
	_update_hints()


## 右下角的按键提示：每条是 [键, 文字]，没有键的只写文字
func _key_hints() -> Array:
	if _contract.is_open:
		return [["Tab", "合上契约"]]
	if _bench.is_open or _codex.is_open or _phase in [Phase.SIGN, Phase.DUSK, Phase.DEAD, Phase.SETTLE]:
		return []
	match _phase:
		Phase.READY:
			if _auto:
				return [["Q", "停下自动垂钓"], ["空格", "自己来"]]
			var ready := [["空格", "抛竿"]] + _auto_hint() + [["F", "唤祂"], ["Tab", "契约"], ["E", "制饵"], ["C", "图鉴"]]
			if _selected_bait() == null:
				ready = [["E", "饵用完了：制饵"], ["F", "唤祂"], ["Tab", "契约"], ["C", "图鉴"]]
			if capture_mouse:
				ready.append(["Alt", "鼠标点格子换饵"])
			else:
				ready.append(["点格子", "换饵"])
			if _water.use_3d_boat and look_range > 0.0:
				ready.append(["鼠标 / A D", "转头"])
			return ready
		Phase.WAITING:
			if _auto:
				return [["Q", "停下自动垂钓"], ["", "自动：等它咬钩"]]
			return [["空格", "提竿"], ["", "等浮漂真正沉下去"]]
		Phase.BITE:
			if _takeover != "":
				return [["空格", "接手提竿"], ["Esc", "放它走"]]
			return [["空格", "提竿！"]]
		Phase.REELING:
			if GameState.contractor.brands > 0:
				return [["按住空格", "收线"], ["松开", "放线"], ["X", "剪线（扣一枚烙印）"]]
			return [["按住空格", "收线"], ["松开", "放线"], ["", "烙印没了，剪不了线"]]
		Phase.AUTO:
			return [["Q", "停下自动垂钓"], ["", "自动收线中"]]
		Phase.RESULT:
			if _auto:
				return [["Q", "停下自动垂钓"]]
			return [["空格", "继续"]] + _auto_hint() + [["F", "唤祂"], ["Tab", "契约"], ["E", "制饵"], ["C", "图鉴"]]
		Phase.DECIDE:
			return [["Tab", "契约"], ["C", "图鉴"]]
	return []


## 自动垂钓暂时禁用的时候（auto_fishing_enabled 是 false），按键提示里不写 Q
func _auto_hint() -> Array:
	return [["Q", "自动垂钓"]] if GameDB.balance.auto_fishing_enabled else []


## 提示变了才重建（和渔获展示、船舱里的按钮是同一种 KeyPrompt，这里只是不能点）
func _update_hints() -> void:
	var hints := _key_hints()
	if hints == _hint_list:
		return
	_hint_list = hints
	for child in _keys.get_children():
		child.queue_free()
	for h in hints:
		var prompt := KeyPrompt.make(h[0], h[1], 16, false)
		prompt.size_flags_horizontal = Control.SIZE_SHRINK_END
		_keys.add_child(prompt)


func _process_waiting(delta: float) -> void:
	if _cast_flight > 0.0:
		_cast_flight -= delta
		if _cast_flight <= 0.0:
			_water.view = WaterView.View.FLOAT
		return
	_timer -= delta
	if not _nibbles.is_empty() and _timer <= _nibbles[0]:
		_nibbles.pop_front()
		_nibble_anim = NIBBLE_TIME
		_arms.play(FirstPersonArms.Action.NIBBLE)
	_nibble_anim = maxf(0.0, _nibble_anim - delta)
	_water.bob = sin(_time * 2.0) * 1.5 + sin(_nibble_anim / NIBBLE_TIME * PI) * 7.0 * lerpf(1.0, _plunge(), 0.5)
	if _timer > 0.0:
		return
	if _event_id != "":
		_open_event()
		return
	if _salvage != "":
		_phase = Phase.BITE
		_timer = CastRoll.BITE_WINDOW_BASE
		_bite_window = _timer
		_qte.open("拉上来")
		_status.text = "浮漂沉了一下，像是挂住了什么东西。"
		_hint.text = "按空格把它拉上来"
		if _auto:
			_pause_for_takeover("挂住了一件东西")
		return
	if _target == null:
		PlayLog.event("miss", {"why": "nothing", "bait": _bait_name()})
		_finish("等了很久，什么也没有咬钩。饵还挂在钩上。", Color("888888"))
		return
	_phase = Phase.BITE
	# 真有生物咬钩才扣饵（新回合机制第 30 条）：之后没提、没来得及提竿、脱钩、剪线、落水都算用掉了
	GameState.consume_bait(_bait)
	PlayLog.event("bite", {"target": _target_id(), "level": _catch.level, "gap": _gap, "bait": _bait_name()})
	_timer = CastRoll.bite_window(_target)
	_bite_window = _timer
	_qte.open()
	if _lured:
		_status.text = "浮漂缓缓沉了下去：深处有什么被引了上来。"
		_hint.text = "引深：按空格提竿，它不会挣扎"
	elif _blood:
		_status.text = "浮漂猛地一沉：血腥把深处的东西引了过来。"
		_hint.text = "血诱：比你高一级的。按空格提竿，或者放它走"
	elif _gap >= 1.5:
		_status.text = "浮漂被一下拽进了水里！"
		_hint.text = "是个大家伙，远超你：钩上了只能剪线。不想惹它，就别动"
	elif _gap >= 0.5:
		_status.text = "浮漂猛地沉了下去！"
		_hint.text = "快按空格提竿！"
	else:
		_status.text = "咬钩了！"
		_hint.text = "快按空格提竿！"
	if _auto:
		_auto_bite()


func _process_reeling(delta: float) -> void:
	_fight_time += delta
	var result := _model.step(delta, _holding)
	_water.tension = _model.tension
	_water.struggling = _model.struggling
	_water.snap_danger = 1.0 if _model.is_straining() else 0.0
	_water.lunge = 0.3 if _model.dragged else 0.0
	_gauge.tension = _model.tension
	_gauge.straining = _model.is_straining()
	_gauge.slack_danger = _model.slack_danger()
	_gauge.distance = maxf(0.0, _model.distance)
	_gauge.line_out = _model.dragged
	_gauge.stamina = _model.stamina_ratio()
	_water.line_ratio = _model.distance / _model.max_distance
	_water.depth_ratio = clampf((_depth + 0.5) / 4.0 + sin(_time * 0.7) * 0.05, 0.0, 1.0)
	var drift := sin(_time * 0.5) * 0.25 + (sin(_time * 2.1) * 0.6 if _model.struggling else 0.0)
	_lateral = lerpf(_lateral, drift, delta * 3.0)
	_water.lateral = _lateral

	if _model.is_spent():
		_status.text = "它没力气了，收线！"
	elif _model.dragged:
		_status.text = "线放尽了，它在拽着你走！"
	elif _model.is_straining():
		_status.text = "线绷到了头，力气在往外流！"
	elif _model.struggling:
		_status.text = "它在挣扎！"
	elif _model.slack_danger() >= 1.0:
		_status.text = "线松了，它要挣脱！"
	else:
		_status.text = "收线中"

	match result:
		TensionModel.Result.CAUGHT:
			_log_fight("caught")
			GameState.record_catch(_target)
			_show_catch()
		TensionModel.Result.SLIPPED:
			_log_fight("slipped")
			_finish("线太松，它挣脱了。", Color("888888"), FirstPersonArms.Action.SLIPPED)
		TensionModel.Result.EXHAUSTED:
			_enter_last_stand()


## 一场搏斗的结局写进试玩日志：caught 钓上 / slipped 脱钩 / cut 剪线 / gamble_won 硬撑钓上 / fell 落水（设计对照文档 5.2）。
## 每场搏斗都从这里过一次：顺手按这一场耗的体力扣饱腹（新回合机制第 36 条；落水的不用算了）
func _log_fight(result: String) -> void:
	if result != "fell":
		_spend_hunger(_model.spent * GameDB.balance.hunger_per_stamina)
	PlayLog.event("fight", {"result": result, "target": _target_id(), "level": _catch.level if _catch else 0,
		"gap": _gap, "seconds": snappedf(_fight_time, 0.1), "min_stamina": snappedf(_model.min_stamina, 0.1),
		"stamina_spent": snappedf(_model.spent, 0.1), "brands": GameState.contractor.brands})


## 体力耗尽：画面放慢，屏幕正中给出剪线 / 硬撑（设计对照文档 3.1 第 5 条）。船头被拽得往下扎，手往前伸、发抖
func _enter_last_stand() -> void:
	_phase = Phase.LAST_STAND
	_decide_time = 0.0
	_holding_on = false
	_set_slow_motion(true)
	_water.tension = TensionModel.MAX_TENSION
	_water.struggling = true
	_water.snap_danger = 1.0
	_water.lunge = 1.0
	_gauge.tension = TensionModel.MAX_TENSION
	_gauge.straining = true
	_gauge.stamina = 0.0
	_captions.visible = false
	var chance := _model.gamble_chance()
	PlayLog.event("exhausted", {"target": _target_id(), "gap": _gap, "chance": snappedf(chance, 0.01),
		"brands": GameState.contractor.brands, "seconds": snappedf(_fight_time, 0.1)})
	_last_stand.open(GameState.contractor.brands, TensionModel.gamble_phrase(chance))


## 决定的时间按真实时间算（画面放慢了，倒计时不慢）；时间到了还没选，就算硬撑
func _process_last_stand(delta: float) -> void:
	_decide_time += delta / maxf(Engine.time_scale, 0.01)
	_water.bob = 0.0
	if _holding_on:
		if _decide_time >= HOLD_ON_SECONDS:
			_resolve_hold_on()
		return
	var total := GameDB.balance.last_stand_seconds
	_last_stand.set_remaining(1.0 - _decide_time / total)
	if _decide_time >= total:
		_hold_on()


func _on_last_stand_chosen(cut: bool) -> void:
	if cut:
		_cut()
	elif _phase == Phase.LAST_STAND and not _holding_on:
		_hold_on()


## 硬撑：咬牙撑一小会儿，再见分晓
func _hold_on() -> void:
	_holding_on = true
	_decide_time = 0.0
	_last_stand.close(false)
	_captions.visible = true
	_status.text = "你咬紧牙关，死死撑住……"
	_hint.text = ""


## 硬撑的结果：赢了把它钓上来，输了被拖下水
func _resolve_hold_on() -> void:
	var chance := _model.gamble_chance()
	var won := _rng.randf() < chance
	PlayLog.event("gamble", {"target": _target_id(), "gap": _gap, "chance": snappedf(chance, 0.01), "won": won})
	_set_slow_motion(false)
	if won:
		_log_fight("gamble_won")
		_log.append_text("[color=#%s]你硬是把它拖出了水面。[/color]\n" % Gothic.BONE.to_html(false))
		GameState.record_catch(_target)
		_show_catch()
	else:
		_log_fight("fell")
		_die("fall")


## 剪线：扣一枚烙印（2026-11-04 起灵魂线并进了烙印），它沉回黑暗里。搏斗中随时能剪，体力耗尽时也能剪；烙印没了剪不了
func _cut() -> void:
	if _phase == Phase.LAST_STAND and _holding_on:
		return
	if _phase not in [Phase.REELING, Phase.LAST_STAND] or not GameState.contractor.cut_line():
		return
	if _phase == Phase.LAST_STAND:
		_last_stand.close(true)
	_set_slow_motion(false)
	_log_fight("cut")
	_finish("你剪断了线，一枚烙印跟着熄了。它沉回了黑暗里。", Color("9fb0b5"), FirstPersonArms.Action.SNAPPED)


## 硬撑输了：被拖下水，当场死亡（设计对照文档 3.1 第 5 条）。HUD 收起来，水从下面漫上来
## cause："fall" 硬撑输了被拖下水（船头猛地扎下去），"offering" 供奉不够又没有烙印了，被祂吞掉
func _die(cause: String) -> void:
	_phase = Phase.DEAD
	_holding = false
	_death_cause = cause
	if cause == "fall":
		_water.lunge = 2.6
		_water.tension = TensionModel.MAX_TENSION
		_water.struggling = true
	_set_hud_visible(false)
	_captions.visible = false
	var who := GameState.contractor
	PlayLog.event("death", {"cause": cause, "number": who.number, "night": who.night, "target": _target_id(),
		"gap": _gap, "ability": who.ability, "brands": who.brands})
	_death.play(who, cause)


## 黑水里按了继续：先出这一位的结算清单
func _on_death_confirmed() -> void:
	_death.close()
	_settle(_death_cause)


## 契约结束（cause："repaid" 偿清、"fall" 落水、"offering" 被吞）：出结算清单（核心调整 G4）。
## 看完了才记进名册、换下一位（_on_settlement_closed）
func _settle(cause: String) -> void:
	_phase = Phase.SETTLE
	_holding = false
	_set_hud_visible(false)
	_captions.visible = false
	_pending_record = Settlement.record(GameState.contractor, cause)
	PlayLog.event("settlement", _pending_record)
	_settlement.open(_pending_record)


## 结算清单合上了：刚结束的那一位记进名册、换下一位，然后签约（GameState.next_contractor：除了名册和图鉴什么都不留）；
## 从名册里点开看的，合上就回到签约
func _on_settlement_closed(review: bool) -> void:
	if review:
		_signing.resume_input()
		return
	var record := _pending_record
	_pending_record = {}
	GameState.next_contractor(record)
	_water.lunge = 0.0
	_open_signing(Settlement.farewell(record))


## 签约时点了名册上的一位：盖上那一份契约的结算清单
func _on_roster_opened(entry: Dictionary) -> void:
	_signing.pause_input()
	_settlement.open(entry, true)


func _on_contractor_changed() -> void:
	GameState.contractor.changed.connect(_refresh_status)
	_night_bar.contractor = GameState.contractor
	_refresh_status()


## 画面放慢（手、海面、粒子都慢下来）；决定的倒计时、LastStand 和 DeathScreen 的动画按真实时间走
func _set_slow_motion(on: bool) -> void:
	if _slow_tween:
		_slow_tween.kill()
	_slow_tween = create_tween()
	_slow_tween.set_ignore_time_scale(true)
	_slow_tween.tween_property(Engine, "time_scale", SLOW_MOTION if on else 1.0, 0.25 if on else 0.4)


## 体力见底、生死关头时屏幕四周泛起暗红，跟着心跳一涨一缩（心跳按真实时间，画面放慢了它也不慢）
func _update_strain(delta: float) -> void:
	var target := 0.0
	if _phase == Phase.REELING:
		target = (1.0 - smoothstep(0.0, 0.35, _model.stamina_ratio())) * 0.75 + (0.2 if _model.is_straining() else 0.0)
	elif _phase == Phase.LAST_STAND:
		target = 1.0
	_strain_amount = move_toward(_strain_amount, target, delta / maxf(Engine.time_scale, 0.01) * 1.5)
	_strain.visible = _strain_amount > 0.001
	if not _strain.visible:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var rate := 8.5 if _phase == Phase.LAST_STAND else 6.5
	var beat := maxf(pow(maxf(sin(t * rate), 0.0), 6.0), 0.6 * pow(maxf(sin(t * rate - 0.9), 0.0), 6.0))
	var m := _strain.material as ShaderMaterial
	m.set_shader_parameter("amount", _strain_amount)
	m.set_shader_parameter("pulse", beat)
	m.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))


## 回到准备抛竿；夜里的时间已经到了就直接进黄昏
func _enter_ready() -> void:
	_phase = Phase.READY
	_water.view = WaterView.View.IDLE
	_water.lunge = 0.0
	_gauge.tier = -1
	_gauge.stamina = GameState.contractor.stamina_cap()
	_gauge.line_out = false
	_gauge.straining = false
	_status.text = "准备抛竿"
	_hint.text = "选好饵料和水层" if _selected_bait() else "饵用完了：按 E 处理渔获制饵，或者按 F 唤祂"
	if GameState.contractor.hunger_tier() > 0:
		_hint.text = "饿了：钓上来的生吞了能顶饿"
	_set_options_enabled(true)


## 抛竿：按挂的饵和水层抽出这一竿咬钩的是什么，个体这时就生成好。饵等真有生物咬钩时才扣（_process_waiting；新回合机制第 30 条），
## 什么也没咬、收竿太早、捞到东西都不扣；饱腹每抛一竿都扣 hunger_per_cast（第 36 条）。没有饵就不能抛
func _cast() -> void:
	var config := GameDB.balance
	_bait = _selected_bait()
	if _bait == null:
		_hint.text = "饵用完了：按 E 处理渔获制饵，或者按 F 唤祂"
		return
	_depth = _rack.depth
	var cast := CastRoll.roll(_bait, _depth, GameState.contractor, _rng, GameState.contractor.night_config())
	_target = cast.fish
	_catch = cast.catch
	_gap = cast.gap
	_salvage = cast.salvage
	_lured = cast.lured
	_blood = cast.get("blood", false)
	_event_id = cast.get("event", "")
	_phase = Phase.WAITING  ## 先换阶段：扣饱腹饿到下一档时会换"准备抛竿"的提示，抛出去以后不该换
	if _event_id == "":  ## 海上事件不算一竿：不扣饱腹（阶段 IV）；暴雨里每竿多掉一点
		_spend_hunger(GameState.contractor.cast_hunger())
	PlayLog.event("cast", {"bait": _bait_name(), "bases": _bait.bases, "additive": _bait.additive_id,
		"universal": _bait.universal, "depth": _depth, "target": _target_id(),
		"level": _catch.level if _catch else 0, "salvage": _salvage, "lured": _lured,
		"hunger": snappedf(GameState.contractor.hunger, 0.1)})
	_timer = cast.wait
	_nibbles.clear()
	for i in _rng.randi_range(0, 2):
		_nibbles.append(_rng.randf_range(0.8, _timer - 0.6))
	_nibbles.sort()
	_nibbles.reverse()
	if _event_id != "":  ## 等来的是一件事：浮漂不会动
		_nibbles.clear()

	_phase = Phase.WAITING
	_cast_flight = CastRoll.CAST_FLIGHT
	_arms.play(FirstPersonArms.Action.CAST)
	_water.line_ratio = 0.35 + _depth * 0.2
	_water.cast_yaw = _water.view_yaw()  ## 朝哪看就往哪抛
	_lateral = 0.1
	_water.lateral = _lateral
	_status.text = "等待……"
	_hint.text = "浮漂动了一下？别急，等它真正沉下去"
	if _event_id != "":
		_hint.text = "浮漂一动不动。雾里有什么靠了过来……"
	_set_options_enabled(false)


## 提竿：体力回满（设计对照文档 3.2 第 10 条），右上角给出对手的相对强弱（第 11 条）。
## 奖励卡：引深引上来的不搏斗（_hook_lured）；镇魂让下一夜的第一场按高一级算；壮魂让体力多撑两成
func _hook() -> void:
	_qte.close(true)
	if _salvage != "":
		_show_salvage()
		return
	if _lured:
		_hook_lured()
		return
	_steadied = false
	_identified = false
	var who := GameState.contractor
	var fed: bool = who.boon_marks.get("fed", false)
	var vigor := who.fight_vigor(true, _depth)
	_model = TensionModel.new(_target, _gap, CastRoll.start_distance(_depth), who.night_config(), _rng, _catch.stage, who.hunger,
		vigor)
	if fed:
		_log.append_text("[color=#%s]饱食之勇：这一场体力掉得慢。[/color]\n" % Gothic.BONE.to_html(false))
	var steady := who.use_card("steady")
	if steady:
		_model.level_gap -= 1
		_log.append_text("[color=#%s]镇魂：这一场你按高一级算。[/color]\n" % Gothic.BONE.to_html(false))
	if who.fight_steady(true) > 0:  ## 骨笛（恩赐）：拆过一条成年的
		_model.level_gap -= 1
		_log.append_text("[color=#%s]骨笛：这一场它按低一级算。[/color]\n" % Gothic.BONE.to_html(false))
	_fight_time = 0.0
	_phase = Phase.REELING
	_water.view = WaterView.View.REELING
	_arms.play(FirstPersonArms.Action.HOOK)
	_gauge.tier = _model.tier()
	_gauge.stamina = _model.stamina_ratio()
	_hint.text = "对手：%s。按住收线、松开放线，让张力停在青色区域" % TensionModel.TIER_NAMES[_model.tier()]
	PlayLog.event("hook", {"target": _target_id(), "level": _catch.level, "gap": _gap, "hunger": snappedf(who.hunger, 0.1),
		"steady_card": steady, "vigor": snappedf(vigor, 0.01), "fed": fed, "blood": _blood})


## 引深引上来的：提竿以后不搏斗，线一路收上来（LURE_SECONDS），然后和钓上来的一样展示
func _hook_lured() -> void:
	_phase = Phase.LURED
	_timer = LURE_SECONDS
	_fight_time = 0.0
	_water.view = WaterView.View.REELING
	_water.struggling = false
	_water.snap_danger = 0.0
	_water.lunge = 0.0
	_arms.play(FirstPersonArms.Action.HOOK)
	_status.text = "它没有挣扎，被你一路收了上来。"
	_hint.text = "引深：深处的东西，不用搏斗"
	PlayLog.event("hook", {"target": _target_id(), "level": _catch.level, "gap": _gap, "lured": true,
		"hunger": snappedf(GameState.contractor.hunger, 0.1)})


func _process_lured(delta: float) -> void:
	_timer -= delta
	_fight_time += delta
	var k := clampf(_timer / LURE_SECONDS, 0.0, 1.0)
	_water.tension = 0.42 + sin(_time * 3.1) * 0.04
	_water.line_ratio = 0.12 + 0.6 * k
	_water.depth_ratio = clampf((_depth + 0.5) / 4.0 * k, 0.0, 1.0)
	_lateral = lerpf(_lateral, sin(_time * 0.5) * 0.15, delta * 3.0)
	_water.lateral = _lateral
	if _timer > 0.0:
		return
	PlayLog.event("fight", {"result": "lured", "target": _target_id(), "level": _catch.level, "gap": _gap,
		"seconds": snappedf(_fight_time, 0.1), "auto": _auto})
	GameState.record_catch(_target)
	if _auto:
		_auto_land()
	else:
		_show_catch()


func _finish(message: String, color: Color, action := -1) -> void:
	if action >= 0:
		_arms.play(action)
	_phase = Phase.RESULT
	_holding = false
	_water.view = WaterView.View.IDLE
	_water.lunge = 0.0
	_captions.visible = true
	_status.text = message
	_hint.text = ""
	_log.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), message.get_slice("\n", 0)])


## 钓上来了：画面压暗，渔获放大浮在正中，选好去处才能接着钓。带着进化（奖励卡）的，先长一个时期再展示
func _show_catch() -> void:
	var note := _apply_evolve()
	_arms.play(FirstPersonArms.Action.CAUGHT)
	_phase = Phase.DECIDE
	_holding = false
	_water.view = WaterView.View.IDLE
	_water.lunge = 0.0
	_captions.visible = false
	_log.modulate.a = 0.0
	_log.append_text("[color=#%s]钓上了「%s」（%d 级，%s %s）[/color]\n" % [
		Gothic.BONE.to_html(false), _catch.display_name(), _catch.level, _catch.body_name(), _catch.body_text()])
	PlayLog.event("catch", _catch.summary())
	_reveal.show_catch(_catch, GameState.contractor, note)


## 带着进化（奖励卡）的：钓上来的这一条先长一个时期。返回写在展示上的那一句（没长是 ""）
func _apply_evolve() -> String:
	var evolved := GameState.contractor.evolve_catch(_catch, _rng)
	if evolved.is_empty():
		return ""
	var note := "进化：%s → %s" % [CatchData.STAGE_NAMES[evolved.from], CatchData.STAGE_NAMES[evolved.to]]
	_log.append_text("[color=#%s]%s，祭值 %s。[/color]\n" % [Gothic.EERIE.to_html(false), note, Gothic.grouped(_catch.tribute)])
	PlayLog.event("evolve", {"species": _catch.species_id, "from": evolved.from, "to": evolved.to, "level": _catch.level,
		"tribute": _catch.tribute})
	return note


## 捞上来的东西（道具或附加物）：和渔获一样压暗画面、浮在正中，空格收下（CatchReveal.show_item）
func _show_salvage() -> void:
	_arms.play(FirstPersonArms.Action.CAUGHT)
	_phase = Phase.DECIDE
	_holding = false
	_water.view = WaterView.View.IDLE
	_water.lunge = 0.0
	_captions.visible = false
	_log.modulate.a = 0.0
	_reveal.show_item(_salvage, GameState.contractor)


func _on_reveal_decided(action: String) -> void:
	if action == "take":
		_log.modulate.a = 1.0
		await _reveal.play_exit(action)
		_captions.visible = true
		_collect_salvage(-1)
		return
	_apply(_catch, action, "reveal")
	_catch = null
	_log.modulate.a = 1.0
	await _reveal.play_exit(action)
	_captions.visible = true
	_enter_ready()


func _on_contract_acted(c: CatchData, action: String) -> void:
	_apply(c, action, "hold")


## 一条渔获的去向：改契约者的状态，再记进左下角的日志和试玩日志
func _apply(c: CatchData, action: String, from: String) -> void:
	var who := GameState.contractor
	var text := ""
	match action:
		"keep":
			if not who.keep(c):
				return
			text = "「%s」留在了船舱里。" % c.display_name()
		"eat":
			var gain := who.eat_gain(c)
			who.eat(c)
			text = "生吞了「%s」，饱腹 +%d。" % [c.display_name(), roundi(gain.food)]
			if gain.overflow >= 1.0:
				text += "吃撑了，%d 白吃了。" % roundi(gain.overflow)
		"dismantle":
			text = "处理了「%s」，得到 %s。" % [c.display_name(), Materials.format(who.dismantle(c))]
	_log.append_text("[color=#%s]%s[/color]\n" % [Gothic.BONE_DARK.to_html(false), text])
	PlayLog.event("decide", {"action": action, "from": from, "species": c.species_id, "level": c.level,
		"ability": who.ability, "hold_load": who.hold_load(), "hunger": snappedf(who.hunger, 0.1),
		"materials": who.materials.duplicate(), "auto": from == "auto"})


## 契约书只在没下竿的时候能开（准备、看结果、选去处）；选去处时先把渔获淡下去
func _toggle_contract() -> void:
	if _contract.is_open:
		_close_contract()
	elif _phase in [Phase.READY, Phase.RESULT, Phase.DECIDE] and not _reveal.busy and not _bench.is_open:
		_holding = false
		_reveal.set_backgrounded(true)
		_set_hud_visible(false)
		_contract.open(GameState.contractor)


func _close_contract() -> void:
	_contract.close()
	_set_hud_visible(true)
	if _phase == Phase.DECIDE:
		_reveal.set_backgrounded(false)
		_reveal.refresh()


## 契约书是一整屏的界面，打开时把 HUD 收起来；选去处时顶上的状态字本来就藏着
func _set_hud_visible(on: bool) -> void:
	for c: Control in [_rack, _gauge, _compass, _log, _keys, _night_bar, _items]:
		c.visible = on
	_captions.visible = on and _phase != Phase.DECIDE


## 图鉴（C）：和契约书一样只在没下竿的时候能开（准备、看结果、选去处）；选去处时先把渔获淡下去，翻到它那一种
func _open_codex() -> void:
	if _codex.is_open or _contract.is_open or _bench.is_open or _summon.is_open or _reveal.busy:
		return
	if _phase not in [Phase.READY, Phase.RESULT, Phase.DECIDE]:
		return
	_holding = false
	var focus: FishData = null
	var stage := -1
	if _phase == Phase.DECIDE and _reveal.catch_data:
		_reveal.set_backgrounded(true)
		focus = _reveal.catch_data.species()
		stage = _reveal.catch_data.stage  ## 立绘翻到刚钓上来的那个时期
	_set_hud_visible(false)
	_codex.open(focus, false, stage)


## 签约的时候点"翻看图鉴"：名字那一栏先不收字，合上以后接着写
func _open_codex_from_signing() -> void:
	if _phase != Phase.SIGN or _codex.is_open or _settlement.is_open:
		return
	_signing.pause_input()
	_codex.open(null, true)


func _on_codex_closed() -> void:
	if _phase == Phase.SIGN:
		_signing.resume_input()
		return
	_set_hud_visible(true)
	if _phase == Phase.DECIDE:
		_reveal.set_backgrounded(false)
		_reveal.refresh()


# ---------- 契约周期：黑夜、黄昏、签约（阶段 D） ----------

## 夜里没有钟（新回合机制第 40 条）：只记这一夜钓了多久（契约书、制饵、图鉴、唤祂的确认开着，看渔获、黄昏、签约时不走），
## 天气按它放。什么时候结束一夜由玩家唤祂（_request_summon）
func _tick_night(delta: float) -> void:
	if _phase in [Phase.SIGN, Phase.DUSK, Phase.DEAD, Phase.DECIDE, Phase.SETTLE] or _contract.is_open or _bench.is_open \
			or _summon.is_open or _codex.is_open:
		return
	_night_clock += delta
	_update_weather()


## 扣饱腹（抛竿、搏斗），饿到下一档时说一句
func _spend_hunger(amount: float) -> void:
	var who := GameState.contractor
	var tier := who.hunger_tier()
	who.spend_hunger(amount)
	if who.hunger_tier() > tier:
		_note_hunger(who.hunger_tier())


## 饿到下一档：日志里说一句；正在准备抛竿的，提示也换掉
func _note_hunger(tier: int) -> void:
	var who := GameState.contractor
	_log.append_text("[color=#%s]%s[/color]\n" % [Gothic.WARN.to_html(false), HUNGER_NOTES[clampi(tier - 1, 0, HUNGER_NOTES.size() - 1)]])
	PlayLog.event("hungry", {"tier": tier, "hunger": snappedf(who.hunger, 0.1), "night": who.night})
	if _phase == Phase.READY:
		_hint.text = "饿了：钓上来的生吞了能顶饿"


## 张力计下面的饱腹；没在搏斗的时候，体力管显示饿掉以后的上限
func _sync_hunger() -> void:
	var who := GameState.contractor
	_gauge.hunger = who.hunger / maxf(who.config.hunger_max, 1.0)
	_gauge.hunger_tier = who.hunger_tier()
	if _phase in [Phase.REELING, Phase.LAST_STAND] and _model:
		_gauge.stamina_cap = _model.stamina_cap()
	else:
		_gauge.stamina_cap = who.stamina_cap()
		_gauge.stamina = _gauge.stamina_cap


## 道具栏上"唤祂"那一格：船舱里的祭值够了就泛红光
func _sync_summon_tile() -> void:
	var who := GameState.contractor
	var enough := who.hold_tribute() >= who.demand()
	_rack.summon_glow = 1.0 if enough and _phase in [Phase.READY, Phase.RESULT] else 0.0
	_rack.summon_tooltip = "唤祂（F）：结束这一夜，唤祂来收供奉\n船舱里的祭值 %s，黄昏要 %s" % [
		Gothic.grouped(who.hold_tribute()), Gothic.grouped(who.demand())]


## 按 F 或者点"唤祂"那一格（新回合机制第 37 条）：准备抛竿、看结果的时候才能唤（钓到一半、开着契约书或制饵时不行）。
## 先出确认（SummonPrompt），这时可以取消；确认了才进黄昏
func _request_summon() -> void:
	if _phase not in [Phase.READY, Phase.RESULT] or _contract.is_open or _bench.is_open or _summon.is_open:
		return
	_holding = false
	_summon.open(GameState.contractor, _bait_count(), _craftable_count())


func _on_summon_confirmed() -> void:
	var who := GameState.contractor
	PlayLog.event("summon", {"night": who.night, "baits": _bait_count(), "craftable": _craftable_count(),
		"materials": who.materials.duplicate(), "hold_tribute": who.hold_tribute(), "demand": who.demand(),
		"hunger": snappedf(who.hunger, 0.1)})
	_enter_dusk()


## 取消：什么也不发、不算供奉，接着钓
func _on_summon_cancelled() -> void:
	pass


## 饵料篓里一共还剩几份
func _bait_count() -> int:
	var n := 0
	for b in GameState.baits:
		n += b.uses
	return n


## 身上的基础材料还能做几份饵（两份一份，附加物用基础款）
func _craftable_count() -> int:
	var n := 0
	for m in Materials.ALL:
		n += GameState.contractor.materials.get(m, 0)
	return n / 2


## 黄昏（交接文档 §3.2、§9）：天转成暗红，祂从雾里浮出来，然后打开供奉
func _enter_dusk() -> void:
	if _phase == Phase.DUSK:
		return
	_auto = false  ## 黄昏一到，自动垂钓就停
	_phase = Phase.DUSK
	_holding = false
	_water.view = WaterView.View.IDLE
	_water.lunge = 0.0
	_set_options_enabled(false)
	_set_hud_visible(false)
	_captions.visible = true
	_status.text = "黄昏"
	_hint.text = "天转红了。祂从雾里浮了出来。"
	var who := GameState.contractor
	PlayLog.event("dusk", {"night": who.night, "hold": who.hold.size(), "hold_tribute": who.hold_tribute(),
		"demand": who.demand(), "hunger": snappedf(who.hunger, 0.1)})
	_restart_sky_tween()
	_sky_tween.tween_property(_water, "dusk", 1.0, 4.0).set_trans(Tween.TRANS_SINE)
	_sky_tween.parallel().tween_property(_water, "rain", 0.0, 4.0)  ## 黄昏雨就停
	_birds.dismiss()
	# 祂出来：先是四周被黑雾包起来，再亮起眼睛，最后样子从雾里显出来（GodPresence 的三步）
	_sky_tween.parallel().tween_property(_god, "presence", 1.0, 6.0).set_delay(0.5)
	_sky_tween.tween_callback(func() -> void:
		_captions.visible = false
		_offering.open(who, _rng))


func _restart_sky_tween() -> void:
	if _sky_tween and _sky_tween.is_valid():
		_sky_tween.kill()
	_sky_tween = create_tween()


## 供奉不够，祂发怒（level 1~4，见 OfferingScreen.angered）：整个世界震一下，祂的眼睛亮闪一下，越怒越狠
func _on_god_angered(level: int) -> void:
	_water.quake(ANGER_QUAKE[level - 1])
	_god.flare(ANGER_FLARE[level - 1])


## 供奉的结局：记进试玩日志，然后下一夜、死、或者契约已偿
func _on_offering_finished(result: Dictionary) -> void:
	var who := GameState.contractor
	PlayLog.event("offering", {"night": who.night, "tribute": result.tribute, "demand": result.demand, "met": result.met,
		"brand_lost": result.brand_lost, "brands": who.brands,
		"offered": result.offered, "kept": who.hold.size()})
	if result.died:
		_die("offering")
	elif result.repaid:
		_leave()
	else:
		# 供奉后的补给与奖励卡（H2）：补给照给，够了再挑一张（超额多一张候选）；收下以后才天黑
		_reward.open(who, result, RewardCards.draw(RewardCards.choice_count(result, who.config), _rng,
			RewardCards.is_over(result, who.config), who))


## 补给与奖励卡收下了：补给（下一夜的万能饵，结算了、还有下一夜就发，够没够都算）放进饵料篓；
## 挑中的卡交给契约者（饱餐、余饵马上生效，其余的到下一夜里触发），然后天黑、下一夜
func _on_reward_finished(card: RewardCard) -> void:
	var who := GameState.contractor
	if _reward.gift:  ## 祂的低语（海上事件）：献了一枚烙印，挑了一张恩赐
		if card:
			who.take_card(card)
		PlayLog.event("whisper", {"night": who.night, "choices": _reward.cards.map(func(c: RewardCard) -> String: return c.id),
			"picked": card.id if card else "", "brands": who.brands})
		_finish_event(_event_text + ("挑了「%s」（%s）。" % [card.display_name, card.duration] if card else ""))
		return
	if _reward.opening:  ## 签约以后的开局恩赐：收下，然后第一夜
		if card:
			who.take_card(card)
			_log.append_text("[color=#%s]收下了「%s」（%s）。[/color]\n" % [Gothic.EERIE.to_html(false), card.display_name, card.duration])
		PlayLog.event("opening", {"choices": _reward.cards.map(func(c: RewardCard) -> String: return c.id),
			"picked": card.id if card else ""})
		_start_first_night()
		return
	if _reward.supply > 0:
		GameState.add_bait(BaitCrafter.make_universal(_reward.supply))
		_log.append_text("[color=#%s]黄昏退去，船头多了 %d 份万能饵。[/color]\n" % [Gothic.BONE.to_html(false), _reward.supply])
		PlayLog.event("supply", {"night": who.night, "baits": _reward.supply})
	if card:
		var got := who.take_card(card)
		if got.baits > 0:
			GameState.add_bait(BaitCrafter.make_universal(got.baits))
		_log.append_text("[color=#%s]收下了「%s」（%s）。[/color]\n" % [Gothic.EERIE.to_html(false), card.display_name, card.duration])
	PlayLog.event("reward", {"night": who.night, "choices": _reward.cards.map(func(c: RewardCard) -> String: return c.id),
		"picked": card.id if card else ""})
	_begin_next_night()


## 天黑，下一夜（能力档跟着夜数走，到了下一档顶上说一句）
func _begin_next_night() -> void:
	var who := GameState.contractor
	var ev := who.begin_night(_rng)
	PlayLog.event("night", {"night": ev.night, "ability": who.ability, "ability_up": ev.ability_up,
		"brands": who.brands, "sea": who.sea, "boons": who.boons.keys()})
	_plan_weather()
	_night_falls()
	_announce_night(ev)


## 天黑时定下今夜的天气（Weather）：下不下雨、大鸟飞不飞。用单独的随机数，不碰游戏的
func _plan_weather() -> void:
	_weather = Weather.plan(_sky_rng, Weather.NOMINAL_NIGHT)
	_birds_flown = false
	_night_clock = 0.0


## 天气跟着这一夜钓了多久走：雨按今夜定好的渐大渐停；到了时候大鸟飞过（一夜一回）
func _update_weather() -> void:
	if _weather == null:
		return
	var elapsed := _night_clock
	_water.rain = 1.0 if GameState.contractor and GameState.contractor.storm else _weather.rain_at(elapsed)  ## 暴雨（海上事件）
	if not _birds_flown and _weather.birds_at >= 0.0 and elapsed >= _weather.birds_at:
		_birds_flown = true
		_birds.launch(_sky_rng)


## 天色退回黑夜，祂沉回雾里，HUD 回来，准备抛竿
func _night_falls() -> void:
	_restart_sky_tween()
	_sky_tween.tween_property(_god, "presence", 0.0, 2.5)
	_sky_tween.parallel().tween_property(_water, "dusk", 0.0, 3.0).set_trans(Tween.TRANS_SINE)
	_set_hud_visible(true)
	_enter_ready()


## 今夜的海况写成一句话（v0.23）
const SEA_LINES := {"calm": "今夜海面平静：深处的少些", "rough": "今夜海面躁动：深处的东西多了",
	"eerie": "今夜冥海异化：带异象的多了"}


## 顶上的字：第几夜、今夜的海况、能力到了下一档、带着哪张奖励卡、异象收藏长了几条
func _announce_night(ev: Dictionary) -> void:
	var who := GameState.contractor
	_status.text = "第 %d 夜" % who.night if not who.is_compensation() else "补偿之夜"
	var lines: PackedStringArray = []
	if who.night > 1 or who.is_compensation():
		lines.append(SEA_LINES.get(who.sea, ""))
	if ev.get("ability_up", false):
		lines.append("你的能力到了 %d 档" % who.ability)
	if ev.get("oddities", 0) > 0:
		lines.append("异象收藏：船舱里 %d 条异象更值钱了" % ev.oddities)
	for effect in who.card_effects:
		lines.append("带着「%s」" % who.card_effects[effect].card.display_name)
	_hint.text = "　".join(lines)


## 契约已偿：先出结算清单，再在名册上盖上封记、换下一位来签约
func _leave() -> void:
	var who := GameState.contractor
	PlayLog.event("repaid", {"number": who.number, "night": who.night})
	_settle("repaid")


## 签约：开局、死了、契约已偿以后都从这里开始
func _open_signing(farewell := "") -> void:
	_phase = Phase.SIGN
	_holding = false
	_set_hud_visible(false)
	_captions.visible = false
	_restart_sky_tween()
	_sky_tween.tween_property(_god, "presence", 0.0, 0.8)
	_sky_tween.parallel().tween_property(_water, "dusk", 0.0, 1.5)
	_sky_tween.parallel().tween_property(_water, "rain", 0.0, 1.5)
	_weather = null
	_birds.dismiss()
	_signing.open(GameState.contractor, GameState.roster, farewell)


## 签下契约：先挑一张开局恩赐（v0.23，RewardScreen.open_opening；卡池里没有永久恩赐就直接开始），再天黑、第一夜
func _on_signed(name_text: String) -> void:
	var who := GameState.contractor
	who.contractor_name = name_text
	PlayLog.event("sign", {"number": who.number, "name": name_text, "promise": who.promise})
	var choices := RewardCards.draw_opening(_rng, who)
	if choices.is_empty():
		_start_first_night()
		return
	_reward.open_opening(who, choices)


# ---------- 海上事件（阶段 IV，SeaEvents） ----------

## 这一竿等来的不是咬钩，是一件事：整屏的帷幕（EventScreen），选好了再接着钓
func _open_event() -> void:
	var who := GameState.contractor
	_phase = Phase.EVENT
	_holding = false
	_water.view = WaterView.View.IDLE
	_event = SeaEvents.start(_event_id, who, _rng)
	if _event_id == "ghost":  ## 亡魂：名册上最近死了的那一位
		for i in range(GameState.roster.size() - 1, -1, -1):
			var entry: Dictionary = GameState.roster[i]
			if entry.get("status", "") == "dead":
				_event.ghost_name = "No.%04d %s" % [int(entry.get("number", 0)), str(entry.get("name", ""))]
				break
	_set_hud_visible(false)
	_event_screen.open(_event, who, _bait_count())
	PlayLog.event("event_open", {"id": _event_id, "night": who.night, "hold": who.hold_tribute(),
		"offers": _event.offers.map(func(o: Dictionary) -> String: return "%s:%d" % [o.kind, o.price])})


## 选好了：结算（SeaEvents.resolve），花的饵、给的饵放进饵料篓；祂的低语要再挑一张恩赐
func _on_event_chosen(index: int) -> void:
	var who := GameState.contractor
	var r := SeaEvents.resolve(_event, index, who, _rng, _bait_count())
	if r.spend_bait > 0:
		var bait := _selected_bait()
		if bait == null and not GameState.baits.is_empty():
			bait = GameState.baits[0]
		if bait:
			GameState.consume_bait(bait)
	if r.baits > 0:
		GameState.add_bait(BaitCrafter.make_universal(r.baits))
	PlayLog.event("event", {"id": _event.id, "night": who.night, "choice": index, "paid": r.paid, "got": r.got,
		"brands": who.brands})
	if _event.id == "blood_moon" and index == 0:  ## 天边泛起血色（借黄昏的天色，到黄昏、天黑时自己换回去）
		_restart_sky_tween()
		_sky_tween.tween_property(_water, "dusk", 0.35, 2.5).set_trans(Tween.TRANS_SINE)
	if not r.choose_boon.is_empty():
		_event_text = r.text
		_reward.open_gift(who, r.choose_boon)
		return
	_finish_event(r.text)


func _finish_event(text: String) -> void:
	_event_id = ""
	_event = {}
	_event_text = ""
	_set_hud_visible(true)
	_finish(text, Gothic.EERIE)


## 签约后的第一夜
func _start_first_night() -> void:
	var who := GameState.contractor
	var ev := who.begin_night(_rng, true)  ## 第一夜不另记 night 事件（试玩报告从 sign 开第一夜）
	_plan_weather()
	_night_falls()
	_announce_night(ev)


## 捞上来的不是生物：一件道具或附加物（交接文档 §10.1：这一竿不扣饵）。展示完、收下以后调用（arms：手臂的动作，−1 不动）
func _collect_salvage(arms := FirstPersonArms.Action.HOOK) -> void:
	var id := _salvage
	_salvage = ""
	GameState.contractor.add_salvage(id)
	var item := GameDB.get_item(id)
	var additive := GameDB.get_additive(id)
	var name_text: String = item.display_name if item else (additive.display_name if additive else id)
	PlayLog.event("salvage", {"what": id, "depth": _depth})
	_finish("你把它拉了上来：%s。" % name_text, Gothic.BONE, arms)


# ---------- 自动垂钓（Q，2026-11-04） ----------

## Q：开 / 关自动垂钓。准备抛竿、看结果、等咬钩的时候能开；什么时候都能关（正在自动收线的那一场照样收完）。
## 暂时禁用（BalanceConfig.auto_fishing_enabled，2026-11-04）：关着的时候开不了
func _toggle_auto() -> void:
	if _auto:
		_auto_stop("你关掉了")
		return
	if not GameDB.balance.auto_fishing_enabled:
		return
	if _phase not in [Phase.READY, Phase.RESULT, Phase.WAITING] or _contract.is_open or _bench.is_open:
		return
	if _phase != Phase.WAITING and _selected_bait() == null:
		_hint.text = "饵用完了，自动垂钓开不了：按 E 制饵，或者按 F 唤祂"
		return
	_auto = true
	_auto_timer = 0.4
	_log.append_text("[color=#%s]自动垂钓开始了。[/color]\n" % Gothic.EERIE.to_html(false))
	PlayLog.event("auto", {"on": true, "night": GameState.contractor.night})


## 自动停下（why 写在提示里），交给你
func _auto_stop(why: String) -> void:
	if not _auto:
		return
	_auto = false
	_hint.text = "自动垂钓停了：%s" % why
	_log.append_text("[color=#%s]自动垂钓停了：%s。[/color]\n" % [Gothic.EERIE.to_html(false), why])
	PlayLog.event("auto", {"on": false, "why": why, "night": GameState.contractor.night})


## 每帧：自动开着、准备抛竿或者看完结果、没开着契约书 / 制饵 / 图鉴 / 唤祂的确认时，歇一会儿就抛下一竿；饵用完了就停
func _drive_auto(delta: float) -> void:
	if not _auto or _phase not in [Phase.READY, Phase.RESULT]:
		return
	if _contract.is_open or _bench.is_open or _codex.is_open or _summon.is_open or _reveal.busy:
		return
	_auto_timer -= delta
	if _auto_timer > 0.0:
		return
	_auto_timer = GameDB.balance.auto_cast_delay
	if _phase == Phase.RESULT:
		_enter_ready()
	if _selected_bait() == null:
		_auto_stop("饵用完了")
		return
	_cast()


## 自动的咬钩：引深引上来的照收；比你强的、带特殊词条的停住等你接手；其余的自动提竿收线
func _auto_bite() -> void:
	if _lured:
		_hook()
		return
	var special := _catch.affix_ids.filter(func(id: String) -> bool:
		var affix := GameDB.get_affix(id)
		return affix != null and affix.special)
	if _gap >= 0.5:
		_pause_for_takeover("上钩的比你强")
	elif not special.is_empty():
		_pause_for_takeover("上钩的带着「%s」" % "、".join(special.map(func(id: String) -> String: return GameDB.get_affix(id).display_name)))
	else:
		_auto_hook()


## 停在咬钩那一刻（提竿窗口不走），等你接手：空格提竿（转为手动）、Esc 放它走。自动这就关了
func _pause_for_takeover(why: String) -> void:
	_takeover = why
	_auto = false
	_qte.open("接手提竿")
	_qte.set_remaining(1.0)
	_status.text = "自动垂钓停下了：%s。" % why
	_hint.text = "按空格接手提竿，按 Esc 放它走（之后都是手动）"
	_log.append_text("[color=#%s]自动垂钓停下了：%s，交给你。[/color]\n" % [Gothic.EERIE.to_html(false), why])
	PlayLog.event("auto", {"on": false, "why": why, "takeover": true, "target": _target_id(), "gap": _gap,
		"salvage": _salvage})


## 接手的时候不提竿，放它走（饵已经扣了，和没来得及提竿一样）
func _let_go() -> void:
	if _takeover == "" or _phase != Phase.BITE:
		return
	_takeover = ""
	_qte.close(false)
	PlayLog.event("miss", {"why": "let_go", "target": _target_id(), "gap": _gap})
	_finish("你放它走了。" if _salvage == "" else "你没去拉那件东西，它又沉了下去。", Color("888888"),
		FirstPersonArms.Action.SLIPPED)


## 自动提竿：不演搏斗，线收上来（auto_reel_seconds），按等级差和饿不饿算钓上来的机会；镇魂（奖励卡）照样按高一级算
func _auto_hook() -> void:
	var who := GameState.contractor
	var config := GameDB.balance
	var gap := _gap - (1.0 if who.use_card("steady") else 0.0)
	_auto_p = config.auto_success(gap, who.hunger)
	_qte.close(true)
	_phase = Phase.AUTO
	_timer = config.auto_reel_seconds
	_fight_time = 0.0
	_water.view = WaterView.View.REELING
	_water.struggling = false
	_water.snap_danger = 0.0
	_water.lunge = 0.0
	_arms.play(FirstPersonArms.Action.HOOK)
	_status.text = "自动收线中……"
	_hint.text = "自动：这一条钓上来的机会 %d%%" % roundi(_auto_p * 100.0)
	PlayLog.event("hook", {"target": _target_id(), "level": _catch.level, "gap": _gap, "auto": true,
		"chance": snappedf(_auto_p, 0.01), "hunger": snappedf(who.hunger, 0.1)})


## 自动收线：线一路收上来，收完了按机会掷一下；按这一场耗的体力扣饱腹（和亲手打一样），壮魂让体力耗得少
func _process_auto(delta: float) -> void:
	var config := GameDB.balance
	_timer -= delta
	_fight_time += delta
	var k := clampf(_timer / maxf(config.auto_reel_seconds, 0.01), 0.0, 1.0)
	_water.tension = 0.5 + sin(_time * 4.3) * 0.12
	_water.struggling = sin(_time * 1.7) > 0.6
	_water.line_ratio = 0.12 + 0.6 * k
	_water.depth_ratio = clampf((_depth + 0.5) / 4.0 * k, 0.0, 1.0)
	_lateral = lerpf(_lateral, sin(_time * 0.9) * 0.3, delta * 3.0)
	_water.lateral = _lateral
	if _timer > 0.0:
		return
	var who := GameState.contractor
	var stamina := config.auto_stamina(_gap, who.hunger) / (1.0 + who.fight_vigor(true, _depth))
	_spend_hunger(stamina * config.hunger_per_stamina)
	var won := _rng.randf() < _auto_p
	PlayLog.event("fight", {"result": "caught" if won else "slipped", "target": _target_id(), "level": _catch.level,
		"gap": _gap, "auto": true, "chance": snappedf(_auto_p, 0.01), "stamina_spent": snappedf(stamina, 0.1)})
	if won:
		GameState.record_catch(_target)
		_auto_land()
	else:
		_finish("自动：它挣脱了。", Color("888888"), FirstPersonArms.Action.SLIPPED)


## 自动钓上来了：带着进化的先长一个时期；船舱放得下就留下，接着钓；放不下就停下，照常展示，交给你
func _auto_land() -> void:
	var who := GameState.contractor
	var note := _apply_evolve()
	if who.keep(_catch):
		var c := _catch
		_catch = null
		PlayLog.event("catch", c.summary())
		PlayLog.event("decide", {"action": "keep", "from": "auto", "species": c.species_id, "level": c.level,
			"ability": who.ability, "hold_load": who.hold_load(), "hunger": snappedf(who.hunger, 0.1),
			"materials": who.materials.duplicate(), "auto": true})
		_finish("自动：「%s」（%d 级，祭值 %s）留在了船舱里。" % [c.display_name(), c.level, Gothic.grouped(c.tribute)], Gothic.BONE,
			FirstPersonArms.Action.CAUGHT)
		return
	_auto_stop("船舱放不下了")
	_arms.play(FirstPersonArms.Action.CAUGHT)
	_phase = Phase.DECIDE
	_holding = false
	_water.view = WaterView.View.IDLE
	_captions.visible = false
	_log.modulate.a = 0.0
	PlayLog.event("catch", _catch.summary())
	_reveal.show_catch(_catch, who, note)


# ---------- 道具（[1]–[3]，交接文档 §10） ----------

## 这会儿能不能用：续魂丝随时能用（烙印没满的时候）；镇魂钉、窥渊之眼只在搏斗中用，一场一次
func _item_usable(id: String) -> bool:
	var item := GameDB.get_item(id)
	var who := GameState.contractor
	if item == null or _contract.is_open or _bench.is_open:
		return false
	match item.effect:
		"brand":
			return who.brands < who.config.brands and _phase not in [Phase.SIGN, Phase.DUSK, Phase.DEAD, Phase.DECIDE,
				Phase.SETTLE]
		"steady":
			return _phase == Phase.REELING and not _steadied
		"identify":
			return _phase in [Phase.REELING, Phase.LAST_STAND] and not _identified
	return false


func _use_item(index: int) -> void:
	var id: String = ItemBar.ORDER[index]
	var item := GameDB.get_item(id)
	var who := GameState.contractor
	if item == null or not _item_usable(id) or not who.use_item(id):
		return
	var text := ""
	match item.effect:
		"brand":
			who.restore_brand()
			if _phase == Phase.LAST_STAND:
				_last_stand.set_brands(who.brands)
			text = "你把续魂丝缠到线轮上，一枚烙印重新燃了起来。"
		"steady":
			_steadied = true
			_model.level_gap -= 1
			_gauge.tier = _model.tier()
			text = "你把镇魂钉钉进船舷。这一场，你按高一级算。"
		"identify":
			_identified = true
			var brief := _catch_brief()
			_hint.text = "线那头：" + brief
			text = "眼珠在掌心里碎开。线那头是" + brief + "。"
	_log.append_text("[color=#%s]%s[/color]\n" % [Gothic.BONE.to_html(false), text])
	PlayLog.event("item", {"id": id, "phase": Phase.keys()[_phase].to_lower(), "target": _target_id(),
		"gap": _model.level_gap if _model and _phase in [Phase.REELING, Phase.LAST_STAND] else 0})


## 窥渊之眼看到的：几级、什么、带什么词条
func _catch_brief() -> String:
	if _catch == null:
		return "看不清的东西"
	var affix := "「%s」" % "、".join(_catch.affix_names()) if not _catch.affix_ids.is_empty() else ""
	return "%d 级的%s%s" % [_catch.level, _catch.display_name(), affix]


func _target_id() -> String:
	return _target.id if _target else ""


func _bait_name() -> String:
	return _bait.display_name if _bait else ""


## 制饵（E）：只在没下竿的时候能开（准备、看结果）。和契约书一样整屏，HUD 收起来
func _open_bench() -> void:
	if _phase not in [Phase.READY, Phase.RESULT] or _contract.is_open or _bench.is_open:
		return
	_holding = false
	_set_hud_visible(false)
	_bench.open(GameState.contractor, _rack.depth)


func _close_bench() -> void:
	_bench.close()
	_set_hud_visible(true)


## 制饵界面开着时的按键：1–7 放材料、退格清空、←→ 换水层、E 或 Esc 回到船上（空格制作在 _input 里）。没用上的返回 false
func _bench_key(keycode: int) -> bool:
	match keycode:
		KEY_E, KEY_ESCAPE:
			_close_bench()
		KEY_BACKSPACE:
			_bench.clear()
		KEY_LEFT, KEY_RIGHT:
			_bench.move_depth(-1 if keycode == KEY_LEFT else 1)
		_:
			if keycode < KEY_1 or keycode > KEY_9:
				return false
			_bench.pick_key(keycode - KEY_1)
	return true


func _selected_bait() -> Bait:
	return _rack.selected_bait()


func _refresh_bait_list() -> void:
	_baits = GameState.baits.duplicate()
	_rack.set_baits(_baits)
	if _phase == Phase.READY:
		_enter_ready()


func _set_options_enabled(enabled: bool) -> void:
	_rack.enabled = enabled


## 道具栏上的能力档和船舱载荷
func _refresh_status() -> void:
	var who := GameState.contractor
	_rack.ability = who.ability
	_rack.ability_tooltip = "能力 %d 档：体力、收线这些本事\n现在跟着夜数走（第 3 夜起 2 档、第 5 夜起 3 档）" % who.ability
	_rack.hold_label = "%d/%d" % [who.hold_load(), who.hold_capacity()]
	var lines: PackedStringArray = ["船舱　载荷 %d/%d（点一下打开契约书）" % [who.hold_load(), who.hold_capacity()]]
	for c in who.hold:
		lines.append("%s　%d 级" % [c.display_name(), c.level])
	lines.append(Materials.format(who.materials))
	_rack.hold_tooltip = "\n".join(lines)
	_gauge.brands = who.brands
	_gauge.brands_max = who.config.brands



# ---------- UI 搭建 ----------

## 第一人称画面铺满全屏，选项和日志做成左上角半透明的 HUD
func _build_ui() -> void:
	_water = WaterView.new()
	_water.boat_screen_top = boat_screen_top
	_water.boat_width_ratio = boat_width_ratio
	_water.use_3d_boat = boat_3d
	_water.boat_seat_z = boat_seat_z
	_water.set_anchors_preset(Control.PRESET_FULL_RECT)
	_water.clip_contents = true
	_water.press_changed.connect(_set_holding)
	add_child(_water)
	# 黄昏时祂从雾里浮出来：在海面之上、手和鱼竿之下
	_god = GodPresence.new()
	_water.add_god(_god)  ## 天和海之上、浮漂和船之下
	# 夜里偶尔从远处天上飞过的大鸟：天之上、祂之下
	_birds = SkyBirds.new()
	_water.add_birds(_birds)

	# 3D 手臂渲染到透明 SubViewport，叠在 2D 画面上（三渲二）
	var arms_container := SubViewportContainer.new()
	arms_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	arms_container.stretch = true
	arms_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(arms_container)
	var arms_viewport := SubViewport.new()
	arms_viewport.transparent_bg = true
	arms_viewport.own_world_3d = true
	arms_viewport.msaa_3d = Viewport.MSAA_4X
	arms_container.add_child(arms_viewport)
	_arms = FirstPersonArms.new()
	arms_viewport.add_child(_arms)
	_water.rod_tip_source = _arms.rod_tip_screen_position

	# 雨丝：在手和鱼竿之上、后期之下（雨也过一遍调色和泛光）
	_rain = RainLayer.new()
	add_child(_rain)

	# 后期：泛光、灯晕、雾气、调色（手、船、海面一起调，HUD 不受影响）
	_grade = ColorRect.new()
	_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grade_material := ShaderMaterial.new()
	grade_material.shader = preload("res://shaders/grade.gdshader")
	_grade.material = grade_material
	add_child(_grade)

	# 钓上东西时把画面压暗褪色（CatchReveal 控制），平时关着；在后期之上、HUD 之下
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim_material := ShaderMaterial.new()
	dim_material.shader = preload("res://shaders/catch_dim.gdshader")
	_dim.material = dim_material
	_dim.visible = false
	add_child(_dim)

	# 体力见底、生死关头时四周泛起的暗红；同样在后期之上、HUD 之下
	_strain = ColorRect.new()
	_strain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_strain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strain_material := ShaderMaterial.new()
	strain_material.shader = preload("res://shaders/strain_vignette.gdshader")
	_strain.material = strain_material
	_strain.visible = false
	add_child(_strain)

	# —— 哥特风 HUD ——
	var ui_theme := Theme.new()
	ui_theme.default_font = Gothic.font()
	ui_theme.default_font_size = 15
	theme = ui_theme

	# 左上：骨架道具栏
	_rack = BoneRack.new()
	_rack.position = Vector2(10, 8)
	_rack.depth_names = GameDB.DEPTH_NAMES
	_rack.depth = 0
	_rack.hold_requested.connect(_toggle_contract)
	_rack.summon_requested.connect(_request_summon)
	add_child(_rack)

	# 左下：渔获日志
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.fit_content = false
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_log.offset_left = 140
	_log.offset_right = 440
	_log.offset_top = -92
	_log.offset_bottom = -14
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_log.add_theme_constant_override("outline_size", 4)
	add_child(_log)

	# 右上：张力计
	_gauge = TensionGauge.new()
	_gauge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_gauge.offset_left = -376
	_gauge.offset_right = -16
	_gauge.offset_top = 10
	_gauge.offset_bottom = 10 + _gauge.custom_minimum_size.y
	_gauge.red_tension = GameDB.balance.red_tension
	_gauge.hunger_marks = PackedFloat32Array(Array(GameDB.balance.hungry_at).map(
		func(x: float) -> float: return x / maxf(GameDB.balance.hunger_max, 1.0)))
	# 张力计下面一排道具
	_items = ItemBar.new()
	_items.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_items.offset_left = -560
	_items.offset_right = -16
	_items.offset_top = _gauge.offset_bottom + 4
	_items.offset_bottom = _gauge.offset_bottom + 30
	_items.used.connect(_use_item)
	add_child(_items)
	add_child(_gauge)

	# 右下：罗盘 + 按键提示
	_compass = Compass.new()
	_compass.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_compass.offset_left = -16 - _compass.custom_minimum_size.x
	_compass.offset_right = -16
	_compass.offset_top = -10 - _compass.custom_minimum_size.y
	_compass.offset_bottom = -10
	add_child(_compass)
	_keys = VBoxContainer.new()
	_keys.alignment = BoxContainer.ALIGNMENT_END
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_keys.offset_left = -340
	_keys.offset_right = -24
	_keys.offset_top = -271
	_keys.offset_bottom = -146
	_keys.grow_vertical = Control.GROW_DIRECTION_BEGIN  ## 提示多了往上长，不压到罗盘
	_keys.add_theme_constant_override("separation", 0)
	add_child(_keys)

	# 顶部：状态 + 铁艺分隔线 + 提示
	_captions = VBoxContainer.new()
	_captions.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_captions.offset_left = -300
	_captions.offset_right = 300
	_captions.offset_top = 70
	_captions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_captions.add_theme_constant_override("separation", 0)
	add_child(_captions)
	# 顶上：三枚烙印，下面一行写第几夜、黄昏要多少、祂想要什么
	_night_bar = NightBar.new()
	_night_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_night_bar.offset_left = -320
	_night_bar.offset_right = 320
	_night_bar.offset_top = 2
	_night_bar.offset_bottom = 66
	_night_bar.contractor = GameState.contractor
	add_child(_night_bar)
	_status = _overlay_label(27)
	_hint = _overlay_label(15)
	_hint.add_theme_color_override("font_color", Gothic.BONE_DARK)
	var divider := TextureRect.new()
	divider.texture = Gothic.tex("divider")
	divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	divider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	divider.custom_minimum_size = Vector2(0, 26)
	divider.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_captions.add_child(_status)
	_captions.add_child(divider)
	_captions.add_child(_hint)

	# 中间：渔获展示（压暗的画面上，渔获放大浮在正中）、契约书，平时藏着
	_reveal = CatchReveal.new()
	_reveal.dim = _dim
	_reveal.decided.connect(_on_reveal_decided)
	add_child(_reveal)
	_contract = ContractScreen.new()
	_contract.dim = _dim
	_contract.acted.connect(_on_contract_acted)
	_contract.close_requested.connect(_close_contract)
	add_child(_contract)
	# 体力耗尽时的剪线 / 硬撑；落水之后的黑水（叠在最上面，落水时 HUD 先收起来）
	_last_stand = LastStand.new()
	_last_stand.chosen.connect(_on_last_stand_chosen)
	add_child(_last_stand)
	# 咬钩那一下的 QTE：[空格] 提竿！和一道收拢的细线（点它也算提竿）
	_qte = BiteQte.new()
	_qte.pressed.connect(func() -> void:
		if _phase == Phase.BITE:
			_hook())
	add_child(_qte)
	_death = DeathScreen.new()
	_death.confirmed.connect(_on_death_confirmed)
	add_child(_death)
	# 制饵（E）
	_bench = BaitBench.new()
	_bench.dim = _dim
	_bench.close_requested.connect(_close_bench)
	add_child(_bench)
	# 唤祂之前的确认（F）
	_summon = SummonPrompt.new()
	_summon.confirmed.connect(_on_summon_confirmed)
	_summon.cancelled.connect(_on_summon_cancelled)
	add_child(_summon)
	# 黄昏供奉、签约（签约盖在最上面）
	_offering = OfferingScreen.new()
	_offering.finished.connect(_on_offering_finished)
	_offering.angered.connect(_on_god_angered)
	add_child(_offering)
	_event_screen = EventScreen.new()
	_event_screen.chosen.connect(_on_event_chosen)
	add_child(_event_screen)
	_reward = RewardScreen.new()
	_reward.finished.connect(_on_reward_finished)
	add_child(_reward)
	_signing = SigningScreen.new()
	_signing.signed.connect(_on_signed)
	_signing.roster_opened.connect(_on_roster_opened)
	_signing.codex_requested.connect(_open_codex_from_signing)
	add_child(_signing)
	# 契约结算清单：盖在签约上面（名册里点开看的也是它）
	_settlement = SettlementScreen.new()
	_settlement.closed.connect(_on_settlement_closed)
	add_child(_settlement)
	# 图鉴（C；签约时点"翻看图鉴"）：盖在最上面
	_codex = CodexScreen.new()
	_codex.closed.connect(_on_codex_closed)
	add_child(_codex)


## 叠在画面上的描边文字，深浅背景上都能看清
func _overlay_label(font_size: int) -> Label:
	var l := UiKit.label("", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Gothic.BONE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	l.add_theme_constant_override("outline_size", 7)
	return l
