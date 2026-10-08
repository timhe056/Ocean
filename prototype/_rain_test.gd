extends SceneTree

## 临时验证：天气事件截图。默认锋面降雨，可传 --event=sea_fog 等。
## 用法: godot --path . --script res://prototype/_rain_test.gd -- --event=sea_fog
## 用法: godot --path . --script res://prototype/_rain_test.gd
## 注意：运行期间会弹出游戏窗口，不要关闭或按键。

var scene: Node3D
var cam: Camera3D
var t0 := 0
var phase := 0


func _init() -> void:
	scene = load("res://prototype/main.tscn").instantiate()
	root.add_child.call_deferred(scene)


func _process(_dt: float) -> bool:
	if cam == null:
		if scene.is_node_ready():
			scene.set_process_unhandled_input(false)
			var rig: Node3D = scene.get_node("CameraRig")
			cam = rig.get_node("SpringArm3D/Camera3D")
			rig.get_node("SpringArm3D").remove_child(cam)
			scene.add_child(cam)
			cam.current = true
			cam.global_position = Vector3(0, 5, 0)
			cam.global_rotation = Vector3(-0.12, 1.0, 0.0)
			var ev := "rain_front"
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--event="):
					ev = arg.trim_prefix("--event=")
			scene.get("weather").debug_force_event(ev)
			t0 = Time.get_ticks_msec()
		return false
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	match phase:
		0:
			if elapsed > 10.0: # 事件峰值附近
				_shot("event_peak.png")
				phase = 1
		1:
			if elapsed > 17.0: # 减弱
				_shot("event_fade.png")
				return true
	return false


func _shot(filename: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("E:/codes/game/gd/ocean/" + filename)
	print("saved: ", filename, " | precip=", snappedf(scene.get("weather").precip, 0.01),
		" | fog=", snappedf(scene.get("weather").fog01, 0.01))
