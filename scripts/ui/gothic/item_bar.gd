class_name ItemBar
extends HBoxContainer
## 右上张力计下面一排道具（交接文档 §10）：每样一个小图标 + "[1] 续魂丝 ×1"。
## 键位按道具种类固定（ORDER），身上没有的不显示；这会儿用不了的发灰（镇魂钉、窥渊之眼只在搏斗中用）。点一下也能用。
## 图标是 GPT 画的（assets/icons/，ItemData.icon）。

signal used(index: int)

## 道具的顺序就是键位：[1] 续魂丝、[2] 镇魂钉、[3] 窥渊之眼
const ORDER: Array[String] = ["soul_thread", "soul_nail", "abyss_eye"]

const ICON_SIZE := Vector2(26, 26)

var _slots: Array[HBoxContainer] = []
var _icons: Array[TextureRect] = []
var _prompts: Array[KeyPrompt] = []
var _state: Array = []  ## 上次显示的 [个数, 能不能用]，变了才重排


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 14)
	for i in ORDER.size():
		var item := GameDB.get_item(ORDER[i])
		var slot := HBoxContainer.new()
		slot.add_theme_constant_override("separation", 2)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.visible = false
		var icon := TextureRect.new()
		icon.texture = item.icon if item else null
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = ICON_SIZE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		var p := KeyPrompt.make(str(i + 1), item.display_name if item else ORDER[i], 15)
		p.tooltip_text = item.description if item else ""
		p.pressed.connect(func() -> void: used.emit(i))
		slot.add_child(p)
		add_child(slot)
		_slots.append(slot)
		_icons.append(icon)
		_prompts.append(p)
		_state.append([-1, false])


## who：当前的契约者；usable：道具 id → 这会儿能不能用
func refresh(who: Contractor, usable: Callable) -> void:
	for i in ORDER.size():
		var id := ORDER[i]
		var count: int = who.items.get(id, 0)
		var ok: bool = count > 0 and usable.call(id)
		if _state[i][0] == count and _state[i][1] == ok:
			continue
		_state[i] = [count, ok]
		var item := GameDB.get_item(id)
		_slots[i].visible = count > 0
		_prompts[i].label = "%s ×%d" % [item.display_name if item else id, count]
		_prompts[i].disabled = not ok
		_icons[i].modulate = Color.WHITE if ok else Color(0.55, 0.53, 0.5, 0.75)
