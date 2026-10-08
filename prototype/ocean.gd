extends MeshInstance3D

## 海面网格：跟随相机移动，位移在世界空间按顶点求值，因此移动不会产生跳变。
## 逐像素法线让超出网格分辨率的小浪也能被光照表现出来。

const OCEAN_SIZE := 3000.0
const OCEAN_SUBDIV := 512

var provider: WaveProvider
var mat: ShaderMaterial


func setup(p_provider: WaveProvider) -> void:
	provider = p_provider

	var plane := PlaneMesh.new()
	plane.size = Vector2(OCEAN_SIZE, OCEAN_SIZE)
	plane.subdivide_width = OCEAN_SUBDIV
	plane.subdivide_depth = OCEAN_SUBDIV
	mesh = plane

	mat = ShaderMaterial.new()
	mat.shader = preload("res://prototype/ocean.gdshader")
	mat.render_priority = -1 # 透明通道里先画水面，雨幕粒子后画
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # 海面不挡阳光，水下才能被照亮
	var params := provider.get_shader_params()
	mat.set_shader_parameter("wave_a", params.wave_a)
	mat.set_shader_parameter("wave_b", params.wave_b)
	mat.set_shader_parameter("displace_count", params.displace_count)
	mat.set_shader_parameter("foam_noise", _make_foam_noise())
	set_surface_override_material(0, mat)


## 白沫噪声纹理：无缝平铺 + mipmap。纹理采样走硬件过滤，
## 没有程序化格点噪声的晶格接缝/瓦片感，远距离由 mipmap 自动抗混叠。
func _make_foam_noise() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.04
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	return tex


func set_sun_direction(dir: Vector3) -> void:
	if mat:
		mat.set_shader_parameter("sun_direction", dir.normalized())


## 海面菲涅尔反射的天空色，随天气强度联动（风暴时天空灰暗）
func set_sky_tint(c: Color) -> void:
	if mat:
		mat.set_shader_parameter("sky_color", Vector3(c.r, c.g, c.b))


## 船尾迹所需的船体状态（由 main.gd 每帧注入）
func set_boat_state(pos: Vector3, forward: Vector3, speed: float) -> void:
	if mat:
		mat.set_shader_parameter("boat_pos", Vector2(pos.x, pos.z))
		var dir := Vector2(forward.x, forward.z)
		mat.set_shader_parameter("boat_dir", dir.normalized() if dir.length() > 0.01 else Vector2(0, -1))
		mat.set_shader_parameter("boat_speed", speed)


func _process(_delta: float) -> void:
	if provider == null:
		return
	mat.set_shader_parameter("time", provider.time)
	# 海况切换期间波形参数逐帧混合，直接每帧推送（8 个 vec4，开销可忽略）
	var params := provider.get_shader_params()
	mat.set_shader_parameter("wave_a", params.wave_a)
	mat.set_shader_parameter("wave_b", params.wave_b)
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z)
		mat.set_shader_parameter("camera_pos", cam.global_position)
