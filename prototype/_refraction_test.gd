extends SceneTree

## 浅滩透视海底验证：折射 + 深度衰减 + 浑浊度联动。
## 用法: godot --path . --script res://prototype/_refraction_test.gd
## 运行期间不要关闭窗口或按键。

var scene: Node3D
var cam: Camera3D
var weather: WeatherSystem
var terrain: Node3D
var t0 := 0
var phase := 0
var shallow := Vector2.ZERO


func _init() -> void:
	scene = load("res://prototype/main.tscn").instantiate()
	root.add_child.call_deferred(scene)


func _process(_dt: float) -> bool:
	if cam == null:
		if scene.is_node_ready():
			weather = scene.get("weather")
			terrain = scene.get("terrain")
			scene.set_process_unhandled_input(false)
			var rig: Node3D = scene.get_node("CameraRig")
			cam = rig.get_node("SpringArm3D/Camera3D")
			rig.get_node("SpringArm3D").remove_child(cam)
			scene.add_child(cam)
			cam.current = true
			# 找一块浅滩沙地（尽量浅，水深深于 ~8m 透视效果就不明显了）
			var found := false
			var best := Vector2.ZERO
			var best_h := -999.0
			for x in range(-800, 800, 16):
				for z in range(-800, 800, 16):
					if terrain.get_biome(x, z) == 0:
						var h: float = terrain.get_height(x, z)
						if h > best_h:
							best_h = h
							best = Vector2(x, z)
							found = true
			shallow = best
			print("最浅沙地点: ", shallow, " 海床高度: ", best_h,
				" 生态区: ", terrain.get_biome_name(shallow.x, shallow.y), " found=", found)
			weather.manual_set(2.5) # 平静
			scene.get("day_night").hour = 11.0
			_pose(Vector3(shallow.x, 12.0, shallow.y + 8.0), -62.0, 0.0)
			t0 = Time.get_ticks_msec()
		return false
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	match phase:
		0:
			if elapsed > 5.5:
				_shot("refr_shallow_top.png") # 俯视浅滩：应见沙地
				# 水深调试图
				var mat: ShaderMaterial = scene.get_node("Ocean").mat
				mat.set_shader_parameter("debug_view", 2)
				phase = 99
				return false
		99:
			if elapsed > 6.0:
				_shot("refr_debug_depth.png")
				var mat2: ShaderMaterial = scene.get_node("Ocean").mat
				mat2.set_shader_parameter("debug_view", 0)
				_pose(Vector3(shallow.x, 3.0, shallow.y + 20.0), -10.0, 0.0) # 掠射角
				phase = 1
				return false
		1:
			if elapsed > 8.0:
				_shot("refr_grazing.png") # 掠射：菲涅尔反射占优，应看不到海底
				weather._hold_left = 0.0
				weather.debug_force_event("thunder_squall") # 风暴搅浑
				_pose(Vector3(shallow.x, 12.0, shallow.y + 8.0), -62.0, 0.0)
				phase = 2
		2:
			if elapsed > 8.0 + 13.0:
				_shot("refr_storm.png") # 风暴俯视：浑浊，海底应基本消失
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
	print("saved: ", filename, " | elapsed=", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1))
