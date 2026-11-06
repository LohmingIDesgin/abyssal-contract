class_name ItemData
extends Resource
## 道具（交接文档 §10）：垂钓时偶尔捞上来，或者超额供奉以后的奖励卡里挑到（2026-11-04 起祂不再赐道具）。在 data/items/ 下新建 .tres 即可添加。
## 第一版三种（设计对照文档第 4 节）：补一枚烙印（原来补灵魂线，2026-11-04 灵魂线并进了烙印）、这一场搏斗按高一级算、看清上钩的是什么。

@export var id: String
@export var display_name: String
@export_multiline var description: String
## 图标（小静物）；还没有的时候界面上只写名字
@export var icon: Texture2D
## 用了有什么用：brand 补回一枚烙印（随时能用）、steady 这一场搏斗按高一级算、identify 看清上钩的个体（搏斗中用）
@export_enum("brand", "steady", "identify") var effect := "brand"


## 搏斗中才能用的
func fight_only() -> bool:
	return effect != "brand"
