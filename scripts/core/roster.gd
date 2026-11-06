class_name Roster
extends RefCounted
## 名册的读写（交接文档 §2.3）：走了的契约者一条一条记在 JSON 里，关了游戏还在。
## 每条是那一位的结算清单（Settlement.record）；G4 以前的只有 {number, name, night, status（"dead" / "repaid"）, cause}。
## 纯函数，测试可以换一个路径。

## JSON 读回来数字都是小数：这几项改回整数
const INT_KEYS: Array[String] = ["number", "night", "tribute", "demand", "brands_lost", "wishes", "cuts", "soul_level", "ability", "casts"]
const BEST_INT_KEYS: Array[String] = ["stage", "level", "tribute"]


static func load_from(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return result
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if not data is Array:
		push_warning("Roster: %s 读不出来，当成空的" % path)
		return result
	for entry in data:
		if entry is Dictionary and entry.has("number"):
			entry.night = entry.get("night", 1)
			for key in INT_KEYS:
				if entry.has(key):
					entry[key] = int(entry[key])
			var best = entry.get("best")
			if best is Dictionary:
				for key in BEST_INT_KEYS:
					if best.has(key):
						best[key] = int(best[key])
			result.append(entry)
	return result


static func save_to(path: String, entries: Array[Dictionary]) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Roster: 写不进 %s（%s）" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(entries, "\t"))
	return true


## 下一位的编号：名册里最大的编号 + 1
static func next_number(entries: Array[Dictionary]) -> int:
	var top := 0
	for e in entries:
		top = maxi(top, int(e.get("number", 0)))
	return top + 1
