extends SceneTree

## 临时验证：雷暴事件——捕捉闪电瞬间截图。
## 用法: godot --path . --script res://prototype/_lightning_test.gd
## 注意：运行期间会弹出游戏窗口，不要关闭或按键。

var scene: Node3D
var cam: Camera3D
var lightning: Node
var t0 := 0
var captured := 0
var pending_shot := false


func _init() -> void:
	scene = load("res://prototype/main.tscn").instantiate()
	root.add_child.call_deferred(scene)


func _process(_dt: float) -> bool:
	if cam == null:
		if scene.is_node_ready():
			scene.set_process_unhandled_input(false)
			lightning = scene.get("lightning")
			var rig: Node3D = scene.get_node("CameraRig")
			cam = rig.get_node("SpringArm3D/Camera3D")
			rig.get_node("SpringArm3D").remove_child(cam)
			scene.add_child(cam)
			cam.current = true
			cam.global_position = Vector3(35, 6, 35) # 离船远点，避免桅杆挡镜头
			cam.global_rotation = Vector3(-0.1, 1.0, 0.0)
			scene.get("weather").debug_force_event("thunder_squall")
			t0 = Time.get_ticks_msec()
		return false
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	# 事件中期（t01≈0.6）：先拍一张乌云密布全景
	if captured == 0 and elapsed > 12.0:
		var img0 := root.get_texture().get_image()
		img0.save_png("E:/codes/game/gd/ocean/lightning_clouds.png")
		print("saved: lightning_clouds | elapsed=", snappedf(elapsed, 0.1))
		captured = 1
		return false
	# 闪电窗口 t01 0.15~0.9，事件 20s → 3s 后开始有闪
	if pending_shot:
		# 已转向闪电方位，闪光仍在（衰减 5/s，一帧后仍亮）
		var img := root.get_texture().get_image()
		img.save_png("E:/codes/game/gd/ocean/lightning_%d.png" % captured)
		print("saved: lightning_", captured, " | flash=", snappedf(lightning.get("flash"), 0.01))
		captured += 1
		pending_shot = false
		if captured >= 3:
			return true
	elif captured >= 1 and lightning.get("flash") > 0.9:
		# 检测到闪电：先转向闪电方位，下一帧再截
		var f: Vector2 = lightning.get("flash_dir")
		cam.global_rotation = Vector3(-0.02, atan2(-f.x, -f.y), 0.0)
		pending_shot = true
	if elapsed > 19.0:
		return true
	return false
