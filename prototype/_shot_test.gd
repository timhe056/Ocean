extends SceneTree

## 临时调试脚本：海面截图工具。
## 用法: godot --path . --script res://prototype/_shot_test.gd
## 流程：依次切平静/中等/风暴，各等过渡完成后截俯视 + 掠射角。

var scene: Node3D
var cam: Camera3D
var provider: WaveProvider
var weather: WeatherSystem
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
			scene.set_process_unhandled_input(false) # 测试期间不吃键盘输入
			var rig: Node3D = scene.get_node("CameraRig")
			cam = rig.get_node("SpringArm3D/Camera3D")
			rig.get_node("SpringArm3D").remove_child(cam)
			scene.add_child(cam)
			cam.current = true
			t0 = Time.get_ticks_msec()
			_pose(Vector3(0, 16, 10), -58.0, 0.0)
		return false
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	# 每档：等 5.5s 过渡完成 → 俯视截图 → 掠射角截图 → 切下一档
	var stage := int(elapsed / 6.5)
	var sub := fmod(elapsed, 6.5)
	match stage:
		0:
			if phase == 0:
				weather.manual_set(2.5) # 轻风（锁定自动天气）
				print("set CALM @", snappedf(elapsed, 0.1))
				phase = 1
		1:
			if phase == 1 and sub > 5.5:
				_shot("sea_calm.png")
				weather.manual_set(5.0) # 和风
				print("set MEDIUM @", snappedf(elapsed, 0.1))
				phase = 2
		2:
			if phase == 2 and sub > 5.5:
				_shot("sea_medium.png")
				weather.manual_set(8.0) # 大风
				print("set STORM @", snappedf(elapsed, 0.1))
				phase = 3
		3:
			if phase == 3 and sub > 5.5:
				_shot("sea_storm.png")
				weather.manual_set(11.0) # 飓风：非凡巨浪
				print("set HURRICANE @", snappedf(elapsed, 0.1))
				phase = 4
		4:
			if phase == 4 and sub > 5.0:
				_shot("sea_hurricane.png")
				_pose(Vector3(0, 6.0, 0), -8.0, 100.0)
				phase = 5
			elif phase == 5 and sub > 5.8:
				_shot("sea_hurricane_grazing.png")
				return true
		_:
			print("STUCK stage=", stage, " phase=", phase, " elapsed=", snappedf(elapsed, 0.1))
			return true
	return false


func _pose(pos: Vector3, pitch_deg: float, yaw_deg: float) -> void:
	cam.global_position = pos
	cam.global_rotation = Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0)


func _shot(filename: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("E:/codes/game/gd/ocean/" + filename)
	print("saved: ", filename, " | 风力=", snappedf(provider.get_wind_level(), 0.1),
		" | elapsed=", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1))
