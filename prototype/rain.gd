extends GPUParticles3D

## 雨幕：跟随相机的 GPUParticles，密度由 weather.precip 驱动。
## 细长条粒子沿速度方向对齐，带风漂移；相机入水时隐藏。

var _intensity := 0.0


func _ready() -> void:
	amount = 4000
	lifetime = 1.1
	explosiveness = 0.0
	visibility_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 30))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(25, 8, 25)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 0.0
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 24.0
	pm.gravity = Vector3(0, -2, 0)
	pm.particle_flag_align_y = true
	pm.damping_min = 0.0
	pm.damping_max = 0.0
	process_material = pm

	# 细长条雨丝
	var streak := BoxMesh.new()
	streak.size = Vector3(0.015, 0.55, 0.015)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.82, 0.88, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	streak.material = mat
	draw_pass_1 = streak

	amount_ratio = 0.0


## 每帧：跟随相机，按降水轴调节密度；风速影响雨丝倾斜。
func update_rain(precip: float, cam_pos: Vector3, wind_dir: Vector2, wind_level: float, underwater: float) -> void:
	global_position = cam_pos + Vector3(0, 6, 0)
	# 密度平滑跟随降水轴
	_intensity = lerpf(_intensity, precip, 0.1)
	amount_ratio = _intensity
	visible = _intensity > 0.02 and underwater < 0.5
	# 雨丝随风倾斜
	var pm := process_material as ParticleProcessMaterial
	if pm:
		var tilt := wind_dir.normalized() * wind_level * 0.35
		pm.gravity = Vector3(tilt.x, -2.0, tilt.y)
