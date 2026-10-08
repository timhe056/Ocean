extends Node3D

## 鱼群管理器：按相机所在生态区维持 2~3 群观赏鱼，离开 150m 回收。
## 生态区配置表见 CONFIGS（数据驱动）；鱼群深度夹在 海面下 2m ~ 海床上 1.5m。

const CONFIGS := {
	0: {"count": 140, "len": 0.25, "color": Color(0.78, 0.82, 0.84), "radius": 10.0}, # 浅滩：银色小鱼大群
	1: {"count": 90, "len": 0.35, "color": Color(0.35, 0.55, 0.30), "radius": 8.0}, # 藻场：绿鱼
	2: {"count": 60, "len": 0.50, "color": Color(0.85, 0.45, 0.20), "radius": 7.0}, # 岩礁：彩色中鱼
	3: {"count": 12, "len": 1.30, "color": Color(0.35, 0.42, 0.48), "radius": 16.0}, # 深海：稀少大鱼
}
const SPAWN_R := 50.0
const DESPAWN_R := 150.0
const TARGET_SCHOOLS := 3

var terrain: Node3D
var provider: WaveProvider

var _schools: Array = [] # fish_school 实例（脚本类型，绕过静态类型检查）
var _spawn_cd := 0.0
var _school_script := preload("res://prototype/fish_school.gd")


func setup(p_terrain: Node3D, p_provider: WaveProvider) -> void:
	terrain = p_terrain
	provider = p_provider


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or terrain == null:
		return
	var cam_pos := cam.global_position
	# 游动 + 回收
	for s in _schools.duplicate():
		if s.anchor.distance_to(cam_pos) > DESPAWN_R:
			_schools.erase(s)
			s.queue_free()
		else:
			s.swim(delta, cam_pos, provider.time)
	# 生成
	_spawn_cd -= delta
	if _schools.size() < TARGET_SCHOOLS and _spawn_cd <= 0.0:
		_spawn_cd = 1.5
		_try_spawn(cam_pos)


func _try_spawn(cam_pos: Vector3) -> void:
	var ang := randf() * TAU
	var r := randf_range(15.0, SPAWN_R)
	var x := cam_pos.x + cos(ang) * r
	var z := cam_pos.z + sin(ang) * r
	var bottom: float = terrain.get_height(x, z) + 1.5
	var top := -2.0
	if top - bottom < 1.0:
		return # 水太浅
	var biome: int = terrain.get_biome(x, z)
	var cfg: Dictionary = CONFIGS[biome]
	# 生态区过渡带混游：锚点周围 ±12m 采样，若混入其他生态区，
	# 群中 30% 的鱼用次生态区的颜色/体型
	var others := {}
	for off in [Vector2(12, 0), Vector2(-12, 0), Vector2(0, 12), Vector2(0, -12)]:
		var b: int = terrain.get_biome(x + off.x, z + off.y)
		if b != biome:
			others[b] = others.get(b, 0) + 1
	var color2 := Color.TRANSPARENT
	var len2 := 0.0
	var mix_frac := 0.0
	if not others.is_empty():
		var b2: int = others.keys()[0]
		for b in others:
			if others[b] > others[b2]:
				b2 = b
		var cfg2: Dictionary = CONFIGS[b2]
		color2 = cfg2.color
		len2 = cfg2.len
		mix_frac = 0.3
	var school = _school_script.new()
	add_child(school)
	# 锚点定在水层中部（不是跟随相机深度）
	var anchor := Vector3(x, lerpf(bottom, top, randf_range(0.25, 0.7)), z)
	school.setup(anchor, cfg.count, cfg.len, cfg.color, cfg.radius, Vector2(bottom, top),
		color2, len2, mix_frac)
	_schools.append(school)
