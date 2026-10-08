extends Camera3D

## 自由潜水相机：C 键与船上跟随相机互换，出生点在船侧水面下。
## 操作：鼠标视角、WASD 沿视线平面移动、Space/Ctrl 升降、Shift 加速。

@export var speed := 5.0
@export var boost_mul := 3.0
@export var mouse_sens := 0.0028

var yaw := 0.0
var pitch := 0.0

var _blend := 0.0 ## 1→0 过渡进度（0.8s）
var _from_pos := Vector3.ZERO
var _from_yaw := 0.0
var _from_pitch := 0.0
var _to_pos := Vector3.ZERO
var _to_yaw := 0.0
var _to_pitch := 0.0


## 从船相机位置平滑过渡过来（0.8s），出生点在船侧 3m、海面下 1m
func activate_from(cam: Camera3D) -> void:
	_from_pos = cam.global_position
	_from_yaw = cam.global_rotation.y
	_from_pitch = cam.global_rotation.x
	_to_pos = cam.global_position + cam.global_transform.basis.x * 3.0
	_to_pos.y = -1.0
	_to_yaw = _from_yaw
	_to_pitch = _from_pitch
	_blend = 1.0
	current = true


func _unhandled_input(event: InputEvent) -> void:
	if not current or _blend > 0.0:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sens
		pitch = clampf(pitch - event.relative.y * mouse_sens, -1.45, 1.45)


func _process(delta: float) -> void:
	if not current:
		return
	if _blend > 0.0:
		_blend = maxf(0.0, _blend - delta / 0.8)
		var t := 1.0 - _blend
		t = t * t * (3.0 - 2.0 * t) # smoothstep
		global_position = _from_pos.lerp(_to_pos, t)
		yaw = lerp_angle(_from_yaw, _to_yaw, t)
		pitch = lerpf(_from_pitch, _to_pitch, t)
		rotation = Vector3(pitch, yaw, 0.0)
		return
	rotation = Vector3(pitch, yaw, 0.0)
	var dir := Vector3(
		Input.get_axis("boat_left", "boat_right"),
		0.0,
		Input.get_axis("boat_forward", "boat_back")
	)
	dir = dir.normalized() if dir.length() > 1.0 else dir
	var move := global_transform.basis * dir
	if Input.is_key_pressed(KEY_SPACE):
		move.y += 1.0
	if Input.is_key_pressed(KEY_CTRL):
		move.y -= 1.0
	var sp := speed * (boost_mul if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	global_position += move * sp * delta
