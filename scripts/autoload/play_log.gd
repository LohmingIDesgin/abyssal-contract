extends Node
## 试玩日志（Autoload: PlayLog）。每次启动游戏写一个文件 user://playlogs/年月日_时分秒.jsonl，一行一个事件，
## 用来测每夜能钓多少、怎么分配渔获（设计对照文档 5.2）。
## Windows 上 user:// 在 %APPDATA%\Godot\app_userdata\<项目名>\；旁边的 logs\ 是 Godot 自己的运行日志，不是这个。
## 只有界面层调用；纯逻辑（Contractor、CatchGenerator 等）不写日志，所以自动测试不会留下文件。

const ENABLED := true

var _file: FileAccess
var _failed := false
var _start_ms := 0


## kind：事件名；data：附带的字段（会被写成同一行 JSON 的其余键）
func event(kind: String, data := {}) -> void:
	if not ENABLED or _failed:
		return
	if _file == null and not _open():
		_failed = true
		return
	var entry := {"t": snappedf((Time.get_ticks_msec() - _start_ms) / 1000.0, 0.01), "kind": kind}
	entry.merge(data)
	_file.store_line(JSON.stringify(entry))
	_file.flush()


func _open() -> bool:
	DirAccess.make_dir_recursive_absolute("user://playlogs")
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	_file = FileAccess.open("user://playlogs/%s.jsonl" % stamp, FileAccess.WRITE)
	if _file == null:
		push_warning("PlayLog: 打不开日志文件（%s）" % error_string(FileAccess.get_open_error()))
		return false
	_start_ms = Time.get_ticks_msec()
	return true
