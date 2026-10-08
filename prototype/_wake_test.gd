extends SceneTree

## 临时验证：船尾迹截图。满油门直线航行 13s 后抓拍俯视与尾随视角。
## 用法: godot --path . --script res://prototype/_wake_test.gd
## 注意：运行期间会弹出游戏窗口，不要关闭或按键。

var scene: Node3D
var cam: Camera3D
var boat: RigidBody3D
var t0 := 0
var phase := 0


func _init() -> void:
	scene = load("res://prototype/main.tscn").instantiate()
	root.add_child.call_deferred(scene)


func _process(_dt: float) -> bool:
	if boat == null:
		if scene.is_node_ready():
			scene.set_process_unhandled_input(false)
			boat = scene.get_node("Boat")
			boat.set_process(false) # 停掉键盘油门读取
			boat.throttle = 1.0
			var rig: Node3D = scene.get_node("CameraRig")
			cam = rig.get_node("SpringArm3D/Camera3D")
			rig.get_node("SpringArm3D").remove_child(cam)
			scene.add_child(cam)
			cam.current = true
			t0 = Time.get_ticks_msec()
		return false
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	# 相机尾随船后上方
	var fwd := -boat.global_transform.basis.z
	cam.global_position = boat.global_position - fwd * 14.0 + Vector3(0, 7.0, 0)
	cam.look_at(boat.global_position + fwd * 10.0)
	match phase:
		0:
			if elapsed > 13.0:
				_shot("wake_chase.png")
				phase = 1
		1:
			# 俯视
			cam.global_position = boat.global_position + Vector3(0, 22.0, 0)
			cam.look_at(boat.global_position)
			if elapsed > 14.0:
				_shot("wake_top.png")
				return true
	return false


func _shot(filename: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("E:/codes/game/gd/ocean/" + filename)
	print("saved: ", filename, " | speed=",
		snappedf(boat.linear_velocity.length() * 1.944, 0.1), " kn")
