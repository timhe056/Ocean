extends RigidBody3D

## 原型船只：多点浮力 + 推进 + 舵 + 龙骨侧向阻力。
## 浮力采样的是与渲染完全相同的波面高度，因此船的起伏与视觉一致。

@export var thrust_force := 3800.0 ## 发动机推力 (N)
@export var reverse_ratio := 0.4 ## 倒车推力比例
@export var rudder_torque := 1800.0 ## 舵扭矩
@export var buoyancy_factor := 7.0 ## 浮力系数（× mass × 浸没深度）
@export var point_drag := 90.0 ## 每个浮力点的速度阻尼
@export var keel_grip := 2.5 ## 龙骨侧向水阻（× mass）
@export var max_submersion := 1.2 ## 单点最大计入浸没深度

var wave_provider: WaveProvider
var throttle := 0.0
var rudder := 0.0


@onready var buoyancy_points: Array[Node3D] = []


func _ready() -> void:
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.55, 0.0)
	linear_damp = 0.7
	angular_damp = 3.0
	can_sleep = false
	for child in $BuoyancyPoints.get_children():
		if child is Node3D:
			buoyancy_points.append(child)


func _process(delta: float) -> void:
	throttle = move_toward(throttle, Input.get_axis("boat_back", "boat_forward"), delta * 0.6)
	rudder = move_toward(rudder, Input.get_axis("boat_right", "boat_left"), delta * 1.8)


func _physics_process(_delta: float) -> void:
	if wave_provider == null:
		return
	var t := wave_provider.time
	var origin := global_position

	# --- 浮力：每个采样点独立施力，自然产生纵摇/横摇 ---
	for p in buoyancy_points:
		var gp := p.global_position
		var depth: float = wave_provider.get_height(gp.x, gp.z, t) - gp.y
		if depth <= 0.0:
			continue
		depth = minf(depth, max_submersion)
		var point_vel := linear_velocity + angular_velocity.cross(gp - origin)
		var force := Vector3.UP * depth * buoyancy_factor * mass - point_vel * point_drag
		apply_force(force, gp - origin)

	# --- 推进 ---
	var basis_w := global_transform.basis
	var forward := -basis_w.z
	var thrust := throttle * thrust_force
	if thrust < 0.0:
		thrust *= reverse_ratio
	apply_central_force(forward * thrust)

	# --- 舵：效率随航速变化 ---
	var fwd_speed := linear_velocity.dot(forward)
	var steer_efficiency := clampf(fwd_speed / 4.0, -0.5, 1.0)
	apply_torque(Vector3.UP * rudder * steer_efficiency * rudder_torque)

	# --- 龙骨侧向阻力，避免船像冰面一样侧滑 ---
	var right := basis_w.x
	var side_speed := linear_velocity.dot(right)
	apply_central_force(-right * side_speed * keel_grip * mass)

	# --- 风压差：5 级以上风开始推船漂移，狂风时显著影响操控 ---
	var wl := wave_provider.get_wind_level()
	if wl > 5.0:
		var wd := wave_provider.get_wind_dir()
		apply_central_force(Vector3(wd.x, 0.0, wd.y) * pow(wl - 5.0, 1.8) * 15.0)
