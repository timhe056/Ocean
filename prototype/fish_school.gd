extends MultiMeshInstance3D

## 单群观赏鱼：MultiMesh + 锚点伪群游（无近邻搜索，O(n)）。
## 每条鱼绕群锚点椭圆巡游 + 个体噪声摆动；相机靠近时四散，远离后回归。

var count := 120
var fish_len := 0.3
var base_color := Color(0.75, 0.8, 0.82)
var radius := 12.0
var anchor := Vector3.ZERO
var depth_min := -20.0 # 活动深度上限（较浅）
var depth_max := -3.0

var _fish: Array[Dictionary] = [] # {phase, speed, r, h, wob, size, prev_pos}
var _flee := 0.0


func setup(p_anchor: Vector3, p_count: int, p_len: float, p_color: Color, p_radius: float, p_depth: Vector2,
		p_color2 := Color.TRANSPARENT, p_len2 := 0.0, p_mix := 0.0) -> void:
	anchor = p_anchor
	count = p_count
	fish_len = p_len
	base_color = p_color
	radius = p_radius
	depth_min = p_depth.x
	depth_max = p_depth.y

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true # (摆尾相位, 摆尾频率)
	multimesh.mesh = _make_fish_mesh()
	multimesh.instance_count = count
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://prototype/fish.gdshader")
	mat.set_shader_parameter("fish_len", fish_len)
	multimesh.mesh.surface_set_material(0, mat)

	for i in count:
		_fish.append({
			"phase": randf() * TAU,
			"speed": randf_range(0.25, 0.6) * (1.0 if randf() > 0.2 else -1.0), # 大多数同向
			"r": randf_range(0.3, 1.0) * radius,
			"h": randf_range(-1.0, 1.0),
			"wob": randf() * TAU,
			"size": randf_range(0.8, 1.25),
			"prev": anchor,
		})
		# 生态区过渡带混游：一定比例的鱼取第二生态区的颜色/体型
		var c := base_color
		var size_k := 1.0
		if p_mix > 0.0 and randf() < p_mix:
			c = p_color2
			size_k = p_len2 / fish_len
		var tint := c.lerp(c.darkened(0.35), randf())
		multimesh.set_instance_color(i, tint)
		_fish[i].size *= size_k
		multimesh.set_instance_custom_data(i, Color(randf() * TAU, randf_range(7.0, 13.0), 0.0))


func _make_fish_mesh() -> ArrayMesh:
	# 程序化三角片小鱼：菱形身体 + 尾鳍，前向 -Z
	var L := fish_len
	var verts := PackedVector3Array([
		Vector3(0, 0, -0.5 * L), # 0 吻
		Vector3(-0.14 * L, 0, 0.1 * L), # 1 左
		Vector3(0.14 * L, 0, 0.1 * L), # 2 右
		Vector3(0, 0.10 * L, 0.05 * L), # 3 背
		Vector3(0, -0.10 * L, 0.05 * L), # 4 腹
		Vector3(0, 0, 0.42 * L), # 5 尾根
		Vector3(0, 0.14 * L, 0.62 * L), # 6 尾上
		Vector3(0, -0.14 * L, 0.62 * L), # 7 尾下
	])
	var indices := PackedInt32Array([
		0, 1, 3, 0, 3, 2, 0, 4, 1, 0, 2, 4, # 身体
		1, 5, 3, 3, 5, 2, 1, 4, 5, 5, 4, 2,
		5, 6, 7, # 尾鳍
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func swim(delta: float, cam_pos: Vector3, t: float) -> void:
	# 锚点缓慢游走
	anchor.x += sin(t * 0.05 + anchor.z * 0.01) * delta * 0.8
	anchor.z += cos(t * 0.04 + anchor.x * 0.01) * delta * 0.8
	anchor.y = clampf(anchor.y + sin(t * 0.1) * delta * 0.3, depth_min, depth_max)

	# 相机靠近 → 四散强度
	var cam_d: float = anchor.distance_to(cam_pos)
	var target_flee := 1.0 if cam_d < 8.0 else 0.0
	_flee = move_toward(_flee, target_flee, delta * (2.0 if target_flee > 0.0 else 0.25))

	for i in _fish.size():
		var f := _fish[i]
		f.phase += f.speed * delta * (1.0 + _flee * 2.5)
		var spread := 1.0 + _flee * 1.6 # 散开时轨道膨胀
		var pos := anchor + Vector3(
			cos(f.phase) * f.r * spread,
			f.h * 2.0 + sin(t * 1.3 + f.wob) * 0.4,
			sin(f.phase) * f.r * spread
		)
		if _flee > 0.01:
			var away := pos - cam_pos
			var d := away.length()
			if d < 10.0:
				pos += away / maxf(d, 0.1) * _flee * (10.0 - d) * 0.6
		pos.y = clampf(pos.y, depth_min, depth_max)
		var vel: Vector3 = pos - f.prev
		f.prev = pos
		if vel.length_squared() < 1e-6:
			continue
		# 用 Basis.looking_at（方向而非目标点）：远处 pos 量级大时 pos+vel 会被
		# float32 精度舍掉导致 origin==target 报错；vel 与 UP 共线时换参考轴
		var up := Vector3.FORWARD if absf(vel.normalized().y) > 0.99 else Vector3.UP
		var xf := Transform3D(Basis.looking_at(vel, up), pos)
		multimesh.set_instance_transform(i, xf.scaled_local(Vector3.ONE * f.size))
	# 受惊四散时摆尾加快
	(multimesh.mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter(
		"wag_boost", 1.0 + _flee * 1.8)
