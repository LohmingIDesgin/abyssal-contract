extends Node
## 自动垂钓的成功率表（2026-11-04）：自动只打和契约者相当或更弱的（等级差 ≤ 0），打法是整局模拟器的"普通的手"（ContractSim.SKILLS），
## 体力耗尽就算它跑了（自动不剪线、不硬撑，不碰烙印）。按等级差 −3 / −2 / −1 / 0、饿的三档各打几百场，打出：钓上来的几成、平均耗多少体力、
## 平均打多久。BalanceConfig 的 auto_stamina 照它填（普通的手亲手打耗 13–38）；普通的手相当和更弱的都是 100% 钓上来，
## auto_success（相当 85%、每弱一级 +7%）是故意打的折扣：自动省事，换来少一点把握。搏斗的数值改了，跑一遍再看。命令行：
##   Godot_v4.6.3-stable_win64.exe --headless --path . res://tests/auto_probe.tscn -- fights=400

const GAPS: Array[float] = [-3.0, -2.0, -1.0, 0.0]
const HUNGERS: Array[float] = [100.0, 45.0, 15.0]  ## 不饿、饿了、饿得发慌
const DT := 1.0 / 30.0


func _ready() -> void:
	var fights := 400
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("fights="):
			fights = int(arg.substr(7))
	var config := GameDB.balance
	var skill: Dictionary = ContractSim.SKILLS["普通"]
	var fish_list: Array = GameDB.sorted_values(GameDB.fish)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	print("自动垂钓：普通的手，体力耗尽算跑了；每格 %d 场（七种生物轮着来）" % fights)
	print("等级差 | 不饿 / 饿了 / 饿得发慌：钓上来 · 耗的体力 · 秒")
	for gap in GAPS:
		var cells: PackedStringArray = []
		for hunger in HUNGERS:
			var won := 0
			var spent := 0.0
			var seconds := 0.0
			for i in fights:
				var fish: FishData = fish_list[i % fish_list.size()]
				var model := TensionModel.new(fish, gap, CastRoll.start_distance(0), config, rng, CatchData.Stage.GROWING, hunger)
				var timer := 0.0
				var reel := false
				var t := 0.0
				while t < 120.0:
					timer -= DT
					if timer <= 0.0:
						timer = skill.react
						reel = model.tension < skill.greed
					var result := model.step(DT, reel)
					t += DT
					if result == TensionModel.Result.CAUGHT:
						won += 1
						break
					if result != TensionModel.Result.ONGOING:
						break
				spent += model.spent
				seconds += t
			cells.append("%4.1f%% · %4.1f · %4.1f" % [won * 100.0 / fights, spent / fights, seconds / fights])
		print("%5.0f | %s" % [gap, " | ".join(cells)])
	get_tree().quit()
