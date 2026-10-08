extends MultiMeshInstance3D

## 水下体积光柱（god rays）：一圈随机分布的圆柱广告牌四边形，
## 跟随相机（xz），强度由 main.gd 按 水下因子×太阳高度×清澈度 驱动。

const RAY_COUNT := 18
const RAY_H := 25.0

var mat: ShaderMaterial


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(6.0, RAY_H)
	quad.center_offset = Vector3(0, -RAY_H * 0.5, 0) # 顶部在水面，向下延伸
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = RAY_COUNT
	mat = ShaderMaterial.new()
	mat.shader = preload("res://prototype/god_rays.gdshader")
	mat.set_shader_parameter("ray_noise", _make_noise())
	quad.material = mat
	for i in RAY_COUNT:
		var off := Vector3(randf_range(-40.0, 40.0), 0, randf_range(-40.0, 40.0))
		var sc := randf_range(0.7, 2.0)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(sc, 1, 1)), off))
	visible = false


## 每帧：跟随相机，按 水下/日照/浑浊 调强度
func update_rays(cam_pos: Vector3, strength: float, sun_axis: Vector3) -> void:
	global_position = Vector3(cam_pos.x, 0.5, cam_pos.z)
	visible = strength > 0.01
	if visible:
		mat.set_shader_parameter("intensity", strength)
		mat.set_shader_parameter("sun_axis", sun_axis)


func _make_noise() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	return tex
