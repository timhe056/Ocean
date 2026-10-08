extends SceneTree

## 临时验证：蒲福连续化——不同风级的浪高统计。
## 用法: godot --headless --path . --script res://prototype/_sea_state_test.gd

var p: WaveProvider
var f := 0
var targets := [2.5, 6.0, 8.0, 11.0]
var stage := 0


func _init() -> void:
	p = WaveProvider.new()


func _process(_dt: float) -> bool:
	f += 1
	if f % 60 != 0:
		return false
	if stage < targets.size():
		# 风力渐变 0.5 级/s：直接设目标后等 20s 真实时间太久，
		# 测试里通过内部字段快进
		p.set_wind(targets[stage])
		p._wind_start = -1000.0 # 快进过渡
		var mn := 1e9
		var mx := -1e9
		for i in 300:
			var h := p.get_height(randf() * 400.0 - 200.0, randf() * 400.0 - 200.0, 50.0 + i * 0.05)
			mn = minf(mn, h)
			mx = maxf(mx, h)
		print("蒲福 %.1f 级 | 浪高范围 [%.2f, %.2f] | 强度 %.2f" % [
			targets[stage], mn, mx, p.current_intensity()])
		stage += 1
		return false
	return true
