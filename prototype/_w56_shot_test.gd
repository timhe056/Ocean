extends SceneTree

## W5/W6 截图验证：涌浪长滚浪 + 昼夜四时刻（清晨/正午/黄昏/夜晚）。
## 用法: godot --path . --script res://prototype/_w56_shot_test.gd
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
			t0 = Time.get_ticks_msec()
			# 阶段 0：涌浪预警（低机位掠射角看长滚浪）
			weather.debug_force_event("swell_surge")
			day_night.hour = 10.0
			_pose(Vector3(0, 4.0, 0), -5.0, 90.0)
			print("force SWELL @t0")
		return false
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	match phase:
		0:
			if elapsed > 11.0: # 涌浪事件 t01≈0.55 峰值
				_shot("w56_swell.png")
				print("swell=%.2f 浪高=%.2f" % [provider.get_swell(),
					provider.get_height(0.0, 0.0)])
				weather.manual_set(3.5) # 锁定平静背景拍昼夜
				day_night.hour = 12.0
				_pose(Vector3(0, 16, 10), -58.0, 0.0)
				phase = 1
		1:
			if elapsed > 14.5:
				_shot("w56_noon.png")
				day_night.hour = 6.6 # 清晨：朝东（-x）看日出
				_pose(Vector3(0, 8, 0), -8.0, 90.0)
				phase = 2
		2:
			if elapsed > 17.0:
				_shot("w56_dawn.png")
				day_night.hour = 17.6 # 黄昏：太阳仍在地平线上，朝西（+x）
				_pose(Vector3(0, 8, 0), -8.0, -90.0)
				phase = 3
		3:
			if elapsed > 19.5:
				_shot("w56_dusk.png")
				day_night.hour = 0.0 # 子夜：抬高视线看星空与月亮
				_pose(Vector3(0, 8, 0), 15.0, 0.0)
				phase = 4
		4:
			if elapsed > 22.0:
				_shot("w56_night.png")
				return true
		_:
			return true
	return false


func _pose(pos: Vector3, pitch_deg: float, yaw_deg: float) -> void:
	cam.global_position = pos
	cam.global_rotation = Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0)


func _shot(filename: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("E:/codes/game/gd/ocean/" + filename)
	print("saved: ", filename, " | 时刻=", day_night.clock_string(),
		" | elapsed=", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1))
