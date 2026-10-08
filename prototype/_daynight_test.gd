extends SceneTree

## W6 昼夜循环数值验证：太阳高度角、日照因子、晨昏因子、时刻回绕。
## 用法: godot --headless --path . --script res://prototype/_daynight_test.gd


func _init() -> void:
	var dn := DayNightCycle.new()

	dn.hour = 12.0
	print("正午: elev=%.2f（应≈1） day=%.2f（应=1） dusk=%.2f（应=0）"
		% [dn.sun_elevation(), dn.day_factor(), dn.dusk_factor()])

	dn.hour = 0.0
	print("子夜: elev=%.2f（应≈-1） day=%.2f（应=0）" % [dn.sun_elevation(), dn.day_factor()])

	dn.hour = 6.0
	print("日出: elev=%.2f（应≈0） dusk=%.2f（应≈1） 时钟=%s" % [dn.sun_elevation(), dn.dusk_factor(), dn.clock_string()])

	dn.hour = 18.0
	print("日落: elev=%.2f（应≈0） dusk=%.2f（应≈1） 时钟=%s" % [dn.sun_elevation(), dn.dusk_factor(), dn.clock_string()])

	# 太阳西升东落方向性：日出时指向东（-x），日落时指向西（+x）
	dn.hour = 7.0
	var morning := dn.dir_to_sun()
	dn.hour = 17.0
	var evening := dn.dir_to_sun()
	print("日出方位 x=%.2f（应<0，东） | 日落方位 x=%.2f（应>0，西）" % [morning.x, evening.x])

	# 时间推进与回绕
	dn.hour = 23.9
	dn.day_length = 24.0 # 1 真实秒 = 1 游戏小时，便于测试
	dn.update(0.5)
	print("回绕: 23.9h +0.5h = %.2fh（应≈0.4）" % dn.hour)

	quit()
