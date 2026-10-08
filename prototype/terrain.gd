extends Node3D

## 海床区块管理器 + 地形/生态区函数（唯一数据源）。
## 高度与生态区由固定 seed 的噪声确定，地形生成、鱼群分布、HUD 都从这里取数。
## 以活动相机为中心维护 3×3 区块，每帧最多生成 1 块。

const CHUNK_SIZE := 128.0
const CHUNK_RES := 64 # 每边四边形数（顶点 65×65）
const RADIUS := 1 # 3×3 区块

# 生态区 id（顺序即顶点色 r 通道 0→1 的分段）
const BIOME_NAMES: Array[String] = ["浅滩沙地", "藻场", "岩礁", "深海平原"]

var provider: WaveProvider
var mat: ShaderMaterial

var _shelf := FastNoiseLite.new() # 大陆架大尺度
var _detail := FastNoiseLite.new() # 细节起伏
var _biome := FastNoiseLite.new() # 生态区划分
var _reef := FastNoiseLite.new() # 岩礁隆起

var _chunks := {} # Vector2i -> MeshInstance3D
var _pending: Array[Vector2i] = []


func setup(p_provider: WaveProvider) -> void:
	provider = p_provider
	_shelf.seed = 1001
	_shelf.frequency = 0.0011
	_detail.seed = 1002
	_detail.frequency = 0.028
	_detail.fractal_octaves = 3
	_biome.seed = 2001
	_biome.frequency = 0.0016
	_biome.fractal_octaves = 2
	_reef.seed = 3001
	_reef.frequency = 0.045
	_reef.fractal_octaves = 3

	mat = ShaderMaterial.new()
	mat.shader = preload("res://prototype/seabed.gdshader")
	mat.set_shader_parameter("caustic_noise", _make_caustic_noise())


func _make_caustic_noise() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.08
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	return tex


## 生态区 id（0 浅滩沙地 / 1 藻场 / 2 岩礁 / 3 深海平原），世界坐标确定。
func get_biome(x: float, z: float) -> int:
	var b := _biome.get_noise_2d(x, z) # -1..1
	if b < -0.3:
		return 3
	if b < 0.05:
		return 0
	if b < 0.4:
		return 1
	return 2


func get_biome_name(x: float, z: float) -> String:
	return BIOME_NAMES[get_biome(x, z)]


## 海床高度（世界坐标，y 值，始终在水面下）。
func get_height(x: float, z: float) -> float:
	var shelf := _shelf.get_noise_2d(x, z) * 0.5 + 0.5 # 0..1
	var base := lerpf(-9.0, -42.0, shelf)
	var detail := _detail.get_noise_2d(x, z) * 2.0
	var h := base + detail
	match get_biome(x, z):
		0: # 浅滩沙地：抬升到浅水
			h = maxf(base * 0.5, -15.0) + detail * 0.6
		1: # 藻场：中等深度缓坡
			h = base * 0.7 + detail
		2: # 岩礁：尖锐隆起
			var r := _reef.get_noise_2d(x, z)
			h = base * 0.55 + maxf(r, 0.0) * 14.0 + detail
		3: # 深海平原：压平加深
			h = base - 8.0 + detail * 0.4
	return minf(h, -3.0) # 不露出水面（留浪高余量）


## 高度场的解析法线（中心差分），供光照与坡度着色
func get_normal(x: float, z: float, e: float = 1.0) -> Vector3:
	var dx := get_height(x - e, z) - get_height(x + e, z)
	var dz := get_height(x, z - e) - get_height(x, z + e)
	return Vector3(dx, 2.0 * e, dz).normalized()


func _process(_delta: float) -> void:
	if provider == null:
		return
	mat.set_shader_parameter("time", provider.time)
	# 焦散强度：风暴时水下变暗
	mat.set_shader_parameter("light_fade", 1.0 - provider.current_intensity() * 0.75)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var center := Vector2i(floori(cam.global_position.x / CHUNK_SIZE), floori(cam.global_position.z / CHUNK_SIZE))
	# 回收远处区块
	for coord in _chunks.keys():
		if abs(coord.x - center.x) > RADIUS + 1 or abs(coord.y - center.y) > RADIUS + 1:
			_chunks[coord].queue_free()
			_chunks.erase(coord)
	# 排队缺失区块，每帧最多生成 1 块
	if _pending.is_empty():
		for dx in range(-RADIUS, RADIUS + 1):
			for dz in range(-RADIUS, RADIUS + 1):
				var c := center + Vector2i(dx, dz)
				if not _chunks.has(c):
					_pending.append(c)
	if not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		if not _chunks.has(c):
			_generate_chunk(c)


func _generate_chunk(coord: Vector2i) -> void:
	var origin := Vector2(coord) * CHUNK_SIZE
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var step := CHUNK_SIZE / CHUNK_RES
	for iz in CHUNK_RES + 1:
		for ix in CHUNK_RES + 1:
			var wx := origin.x + ix * step
			var wz := origin.y + iz * step
			verts.append(Vector3(wx, get_height(wx, wz), wz))
			normals.append(get_normal(wx, wz))
			var b := float(get_biome(wx, wz)) / 3.0
			colors.append(Color(b, 0, 0))
	for iz in CHUNK_RES:
		for ix in CHUNK_RES:
			var a := iz * (CHUNK_RES + 1) + ix
			var b2 := a + 1
			var c2 := a + CHUNK_RES + 1
			var d := c2 + 1
			indices.append_array([a, b2, c2, b2, d, c2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_chunks[coord] = mi
