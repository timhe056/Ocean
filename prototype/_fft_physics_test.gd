extends SceneTree

## FFT 后端物理一致性排查：船体高度 vs 浪面高度 vs 纹理数据。
## 用法: godot --headless --path . --script res://prototype/_fft_physics_test.gd

var scene: Node3D
var provider: WaveProvider
var frames := 0


func _init() -> void:
	scene = load("res://prototype/main.tscn").instantiate()
	root.add_child.call_deferred(scene)


func _process(_dt: float) -> bool:
	if provider == null:
		if scene.is_node_ready():
			provider = scene.get("provider")
			scene.get("weather").manual_set(6.0)
			provider.toggle_backend() # FFT
			print("backend=", provider.backend)
		return false
	frames += 1
	if frames > 600:
		var boat: RigidBody3D = scene.get_node("Boat")
		var bp := boat.global_position
		var h_fft: float = provider.get_height(bp.x, bp.z)
		# 直接读 C# 数组对照
		var fft = provider.get("_fft")
		var h_raw: float = fft.SampleBilinear(bp.x, bp.z) if fft else -999.0
		print("t=%.1f 船 y=%.2f | get_height=%.2f | SampleBilinear=%.2f | 浪程=%.2f"
			% [provider.time, bp.y, h_fft, h_raw, h_fft - bp.y])
		return frames > 900
	return false
