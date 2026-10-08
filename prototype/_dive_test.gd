extends SceneTree

## 临时验证：潜水模式截图（水下看海面背面 / 水下平视 / 水面回归）。
## 用法: godot --path . --script res://prototype/_dive_test.gd
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
			scene._toggle_dive()
			cam = scene.get("dive_cam")
			cam._blend = 0.0 # 跳过过渡动画
			t0 = Time.get_ticks_msec()
		return false
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	match phase:
		0:
			# 水下 3m 抬头看海面背面（太阳方向）
			cam.global_position = Vector3(0, -3, 0)
			cam.yaw = 2.8
			cam.pitch = 0.9
			if elapsed > 2.0:
				_shot("dive_lookup.png")
				phase = 1
		1:
			# 水下平视（雾色）
			cam.yaw = 1.2
			cam.pitch = 0.0
			if elapsed > 3.0:
				_shot("dive_level.png")
				phase = 2
		2:
			# 海床特写：相机贴到海床上方 8m 俯视
			var terrain: Node3D = scene.get("terrain")
			var h: float = terrain.get_height(0.0, 0.0)
			cam.global_position = Vector3(0, h + 8.0, 0)
			cam.yaw = 0.6
			cam.pitch = -1.0
			if elapsed > 6.5: # 等区块生成
				_shot("dive_seabed.png")
				phase = 3
		3:
			# 鱼群特写：找到最近一群鱼，2.5m 距离对着拍
			var schools: Array = scene.get("fish").get("_schools")
			if schools.size() > 0:
				var anchor: Vector3 = schools[0].get("anchor")
				cam.global_position = anchor + Vector3(2.5, 0.3, 0.0)
				var dir := (anchor - cam.global_position).normalized()
				cam.yaw = atan2(-dir.x, -dir.z)
				cam.pitch = asin(clampf(dir.y, -1.0, 1.0))
			if elapsed > 11.0:
				var terrain: Node3D = scene.get("terrain")
				print("chunks=", terrain.get("_chunks").size(), " pending=", terrain.get("_pending").size(),
					" cam=", cam.global_position)
				_shot("dive_fish.png")
				phase = 4
		4:
			# 回到船上视角回归检查
			cam.global_position = Vector3(0, 5, 0)
			cam.yaw = 1.8
			cam.pitch = -0.2
			if elapsed > 12.5:
				_shot("dive_surface.png")
				return true
	return false


func _shot(filename: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("E:/codes/game/gd/ocean/" + filename)
	print("saved: ", filename, " | uw=", snappedf(scene.get("underwater"), 0.01))
