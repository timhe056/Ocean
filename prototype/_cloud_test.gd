extends SceneTree

## 云形截图验证：晴天少云 / 多云 / 雷暴乌云，机位抬高观察云的形状。
## 用法: godot --path . --script res://prototype/_cloud_test.gd
## 运行期间不要关闭窗口或按键。

var scene: Node3D
var cam: Camera3D
var provider: WaveProvider
var weather: WeatherSystem
var day_night: DayNightCycle
var t0 := 0
var phase := 0


func _init() -> void:
	scene = load("res://prototype/main.tscn").instantiate()
	root.add_child.call_deferred(scene)


func _process(_dt: float) -> bool:
	if provider == null:
		if scene.is_node_ready():
			provider = scene.get("provider")
			weather = scene.get("weather")
			day_night = scene.get("day_night")
			scene.set_process_unhandled_input(false)
			var rig: Node3D = scene.get_node("CameraRig")
			cam = rig.get_node("SpringArm3D/Camera3D")
			rig.get_node("SpringArm3D").remove_child(cam)
			scene.add_child(cam)
			cam.current = true
			cam.global_position = Vector3(0, 5, 0)
			cam.global_rotation = Vector3(deg_to_rad(15.0), 0.6, 0.0) # 仰视 15°
			day_night.hour = 11.0
			weather.manual_set(3.5)
			weather.cloud_character = 0.1 # 碧空散云
			weather.sky_cover_bias = 0.55
			t0 = Time.get_ticks_msec()
		return false
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	match phase:
		0:
			if elapsed > 5.5:
				_shot("cloud_scattered.png")
				weather.cloud_character = 0.5 # 大小云混合
				weather.sky_cover_bias = 1.05
				phase = 1
		1:
			if elapsed > 8.5:
				_shot("cloud_mixed.png")
				weather.cloud_character = 1.0 # 大片云堤
				weather.sky_cover_bias = 1.3
				phase = 2
		2:
			if elapsed > 11.5:
				_shot("cloud_bank.png")
				weather._hold_left = 0.0 # 解除手动风锁定，否则事件不推进
				weather.debug_force_event("thunder_squall") # 20s 加速版雷暴
				phase = 3
		3:
			if elapsed > 11.5 + 13.0: # t01≈0.65 暴雨峰值，乌云最盛
				_shot("cloud_storm.png")
				return true
		_:
			return true
	return false


func _shot(filename: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("E:/codes/game/gd/ocean/" + filename)
	print("saved: ", filename, " | 风力=", snappedf(provider.get_wind_level(), 0.1),
		" | elapsed=", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1))
