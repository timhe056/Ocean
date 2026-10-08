extends SceneTree

## M4 F2 A/B 对比：同海况、同机位（船上跟随视角，复现 shot_3 的角度），
## Gerstner vs FFT 后端各拍 4.5 级 / 8 级两张。
## 用法: godot --path . --script res://prototype/_fft_visual_test.gd
## 运行期间不要关闭窗口或按键。

var scene: Node3D
var provider: WaveProvider
var weather: WeatherSystem
var t0 := 0
var phase := 0


func _init() -> void:
	scene = load("res://prototype/main.tscn").instantiate()
	root.add_child.call_deferred(scene)


func _process(_dt: float) -> bool:
	if provider == null:
		if scene.is_node_ready():
			provider = scene.get("provider")
			weather = scene.get("weather")
			scene.set_process_unhandled_input(false)
			weather.manual_set(4.5) # 与 shot_3 同海况
			scene.get("day_night").hour = 11.0
			t0 = Time.get_ticks_msec()
		return false
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	match phase:
		0:
			if elapsed > 6.5:
				_shot("ab_gerstner_45.png")
				provider.toggle_backend() # → FFT
				phase = 1
		1:
			if elapsed > 9.5:
				_shot("ab_fft_45.png")
				var mat: ShaderMaterial = scene.get_node("Ocean").mat
				mat.set_shader_parameter("debug_view", 1) # 白沫 mask
				phase = 11
		11:
			if elapsed > 10.2:
				_shot("ab_fft_45_foam.png")
				var mat2: ShaderMaterial = scene.get_node("Ocean").mat
				mat2.set_shader_parameter("debug_view", 0)
				provider.toggle_backend() # → Gerstner
				weather.manual_set(8.0)
				phase = 2
		2:
			if elapsed > 18.5: # 8 级浪长起来
				_shot("ab_gerstner_8.png")
				provider.toggle_backend() # → FFT
				phase = 3
		3:
			if elapsed > 21.5:
				_shot("ab_fft_8.png")
				return true
		_:
			return true
	return false


func _shot(filename: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("E:/codes/game/gd/ocean/" + filename)
	print("saved: ", filename, " | backend=", provider.backend,
		" | 浪高=", snappedf(provider.get_height(0.0, 0.0), 0.1))
