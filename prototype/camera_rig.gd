extends Node3D

## 跟随相机：平滑跟随船的位置和航向，鼠标可环顾，松开后缓慢回正。

@export var target: Node3D
@export var follow_speed := 6.0
@export var turn_speed := 2.5
@export var arm_length := 11.0

var orbit_yaw := 0.0
var pitch := -0.38


func _ready() -> void:
	$SpringArm3D.spring_length = arm_length


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		orbit_yaw = clampf(orbit_yaw - event.relative.x * 0.0028, -2.2, 2.2)
		pitch = clampf(pitch - event.relative.y * 0.0028, -1.1, 0.25)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var target_pos := target.global_position + Vector3(0.0, 2.2, 0.0)
	global_position = global_position.lerp(target_pos, 1.0 - exp(-follow_speed * delta))
	# 缓慢回正到船尾方向
	orbit_yaw = lerpf(orbit_yaw, 0.0, 1.0 - exp(-0.4 * delta))
	var desired_yaw: float = target.global_rotation.y + orbit_yaw
	rotation.y = lerp_angle(rotation.y, desired_yaw, 1.0 - exp(-turn_speed * delta))
	rotation.x = pitch
