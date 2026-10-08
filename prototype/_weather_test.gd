extends SceneTree

## 临时验证：天气系统 v2——事件编舞、轴范围、雷暴冷却、手动锁定。
## 用法: godot --headless --path . --script res://prototype/_weather_test.gd


func _init() -> void:
	var p := WaveProvider.new()
	var w := WeatherSystem.new(p)
	# 快进：缩短驻留与时长（事件逻辑不变）
	w._dwell_left = 5.0

	var log: Array[String] = []
	var max_wind := 0.0
	var max_precip := 0.0
	var max_fog := 0.0
	var thunder_count := 0
	var fog_at_high_wind := false
	var last_event := ""

	# 模拟 2000s（含两次雷暴冷却）
	for i in 2000:
		w.update(1.0)
		p._wind_start -= 1.0 # 测试时间加速：让风力混合跟上模拟时钟
		var wind := p.get_wind_level()
		max_wind = maxf(max_wind, wind)
		max_precip = maxf(max_precip, w.precip)
		max_fog = maxf(max_fog, w.fog01)
		var ev := w.event_label()
		if ev != last_event:
			log.append("t=%ds 事件: %s (风力 %.1f)" % [i, ev, wind])
			if ev == "雷暴飑线":
				thunder_count += 1
			last_event = ev
		if w.fog01 > 0.5 and wind > 5.0:
			fog_at_high_wind = true

	print("事件日志:\n  " + "\n  ".join(log))
	print("最大风力: %.1f 级（应 ≤ 11.5+gust）" % max_wind)
	print("最大降水: %.2f / 最大海雾: %.2f" % [max_precip, max_fog])
	print("雷暴次数: %d（2000s 内应 1~2 次）" % thunder_count)
	print("大风起雾（不应发生）: ", "发生了!" if fog_at_high_wind else "无 OK")

	# 手动锁定
	w.manual_set(8.0)
	for i in 5:
		w.update(1.0)
		p._wind_start -= 1.0
	print("手动设风 8 级后 5s: 风力 %.1f（应保持高位）is_auto=%s" % [p.get_wind_level(), w.is_auto()])

	# W5 涌浪预警：风不变但浪变高变长；事件结束后强制跟随风暴
	var w2 := WeatherSystem.new(p)
	p.set_wind(4.0)
	p._wind_start -= 100.0 # 让风力立即到位
	w2._hold_left = 0.0
	w2.debug_force_event("swell_surge")
	var h_before := 0.0
	for x in range(-100, 100, 4):
		h_before = maxf(h_before, absf(p.get_height(x, 0.0, 1.0)))
	var wind_before := p.get_wind_level()
	var max_swell := 0.0
	var h_peak := 0.0
	for i in 5: # 推进到事件中段（涌浪峰值 t01≈0.55）
		w2.update(2.0)
		max_swell = maxf(max_swell, w2.swell)
	for x in range(-100, 100, 4):
		h_peak = maxf(h_peak, absf(p.get_height(x, 0.0, 1.0)))
	var wind_during := p.get_wind_level()
	print("涌浪峰值: %.2f | 浪高 %.2fm → %.2fm（应变高）| 风力 %.1f → %.1f（应基本不变）"
		% [max_swell, h_before, h_peak, wind_before, wind_during])
	for i in 25: # 跑完事件 + 驻留（30~90s）
		w2.update(10.0)
		p._wind_start -= 10.0
	print("涌浪结束后下一事件: %s（应为 锋面降雨/雷暴飑线）" % w2.event_label())

	# 手动触发/清除事件（快捷键 4/5/6/7/0 背后的接口）
	w2.force_event("thunder_squall")
	w2.update(1.0)
	print("force 雷暴: 事件=%s（应为雷暴飑线，真实时长 %.0fs）" % [w2.event_label(), w2._event_dur])
	w2.force_event("swell_surge")
	for i in 30: # 涌浪爬升段 t01 0.15 之后才起浪
		w2.update(1.0)
	print("force 涌浪 30s 后: swell=%.2f（应>0）" % w2.swell)
	w2.clear_event()
	w2.update(1.0)
	print("clear 后: 事件=%s（应为晴好） swell=%.2f（应=0）" % [w2.event_label(), w2.swell])
	quit()
