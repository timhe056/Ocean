extends Node3D

## 原型入口：创建共享的 WaveProvider，注入海面与船只，更新 HUD。
## 模式：船上驾驶 / 自由潜水（C 键切换）。

@onready var hud_label: Label = $HUD/Label
@onready var boat: RigidBody3D = $Boat
@onready var boat_cam: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var env: Environment = $WorldEnvironment.environment

var provider: WaveProvider
var weather: WeatherSystem
var day_night: DayNightCycle
var sky_mat: ShaderMaterial
var dive_cam: Camera3D # dive_camera.gd
var terrain: Node3D # terrain.gd 海床
var fish: Node3D # fish_manager.gd 鱼群
var rain: GPUParticles3D # rain.gd 雨幕
var lightning: Node # lightning.gd 雷电
var ambience: Node # ambience.gd 风声雨声
var rays: MultiMeshInstance3D # god_rays.gd 水下光柱
var diving := false
var underwater := 0.0 # 0..1 水下过渡因子（0.3s 平滑）
var base_fog_color: Color


func _ready() -> void:
	provider = WaveProvider.new()
	weather = WeatherSystem.new(provider)
	day_night = DayNightCycle.new()
	$Ocean.setup(provider)
	boat.wave_provider = provider
	$CameraRig.target = boat
	var sun_dir: Vector3 = -$DirectionalLight3D.global_transform.basis.z
	$Ocean.set_sun_direction(sun_dir)
	# 天气联动天空：自定义 sky shader 替换 PhysicalSky
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = preload("res://prototype/sky.gdshader")
	sky_mat.set_shader_parameter("sun_direction", sun_dir.normalized())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	sky_mat.set_shader_parameter("cloud_noise", _make_cloud_noise())
	base_fog_color = env.fog_light_color
	# 潜水相机（脚本挂 Camera3D，初始非活动）
	dive_cam = preload("res://prototype/dive_camera.gd").new()
	add_child(dive_cam)
	# 海床
	terrain = preload("res://prototype/terrain.gd").new()
	add_child(terrain)
	terrain.setup(provider)
	# 鱼群
	fish = preload("res://prototype/fish_manager.gd").new()
	add_child(fish)
	fish.setup(terrain, provider)
	# 雨幕
	rain = preload("res://prototype/rain.gd").new()
	add_child(rain)
	# 雷电
	lightning = preload("res://prototype/lightning.gd").new()
	add_child(lightning)
	# 环境音效（风 + 雨）
	ambience = preload("res://prototype/ambience.gd").new()
	add_child(ambience)
	# 水下体积光柱
	rays = preload("res://prototype/god_rays.gd").new()
	add_child(rays)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 云噪声纹理：Simplex 各向同性（无格点矩形感）+ 无缝平铺 + mipmap，
## 与海面白沫同一方案——硬件过滤根除晶格，远处由 mipmap 自动抗混叠。
func _make_cloud_noise() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	return tex


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				weather.manual_set(2.5) # 轻风
			KEY_2:
				weather.manual_set(5.0) # 和风
			KEY_3:
				weather.manual_set(8.0) # 大风
			KEY_4:
				weather.force_event("rain_front") # 锋面降雨
			KEY_5:
				weather.force_event("thunder_squall") # 雷暴飑线
			KEY_6:
				weather.force_event("sea_fog") # 海雾
			KEY_7:
				weather.force_event("swell_surge") # 涌浪预警
			KEY_0:
				weather.clear_event() # 恢复晴好
			KEY_T:
				day_night.toggle_time_scale() # 时间加速 ×30
			KEY_C:
				_toggle_dive()
			KEY_BRACKETLEFT:
				day_night.hour = fmod(day_night.hour + 23.5, 24.0) # -0.5h
			KEY_BRACKETRIGHT:
				day_night.hour = fmod(day_night.hour + 0.5, 24.0) # +0.5h


func _toggle_dive() -> void:
	diving = not diving
	if diving:
		boat.set_process(false) # 停掉油门/舵的输入读取
		boat.throttle = 0.0
		dive_cam.activate_from(boat_cam)
	else:
		dive_cam.current = false
		boat_cam.current = true
		boat.set_process(true)


func _process(delta: float) -> void:
	if boat.wave_provider == null:
		return
	weather.update(delta)
	day_night.update(delta)
	# 雷电：雷暴事件窗口内随机闪电
	var is_thunder := weather.event_label() == "雷暴飑线" and 0.15 < weather.event_t01() and weather.event_t01() < 0.9
	lightning.update_storm(delta, is_thunder)
	sky_mat.set_shader_parameter("flash", lightning.flash)
	sky_mat.set_shader_parameter("flash_dir", lightning.flash_dir)
	sky_mat.set_shader_parameter("flash_seed", lightning.flash_seed)
	# 昼夜：太阳/月亮方位、日照强度、晨昏暖调
	var day_f := day_night.day_factor()
	var dusk_f := day_night.dusk_factor()
	var dir_to_sun := day_night.dir_to_sun()
	var sun_elev := day_night.sun_elevation()
	sky_mat.set_shader_parameter("sun_direction", -dir_to_sun) # 光线传播方向
	sky_mat.set_shader_parameter("moon_direction", day_night.dir_to_moon())
	sky_mat.set_shader_parameter("day_factor", day_f)
	sky_mat.set_shader_parameter("dusk", dusk_f)
	# 平行光：白天是太阳（晨昏染橙），夜晚月亮接管（冷色微光）
	var sun: DirectionalLight3D = $DirectionalLight3D
	var light_from := day_night.active_light_dir() # 指向光源
	var up := Vector3.FORWARD if absf(light_from.y) > 0.95 else Vector3.UP
	sun.global_transform.basis = Basis.looking_at(-light_from, up) # -Z = 光线传播方向
	var sun_up := clampf(sun_elev * 3.0, 0.0, 1.0)
	var moon_up := clampf(-sun_elev * 3.0, 0.0, 1.0)
	# 天气强度联动：天空、阳光、雾、海面反射色（随波浪混合天然同步）
	var intensity := provider.current_intensity()
	# 天空阴霾度：风与降水取大者——雷暴时即使风还没到峰值，也已乌云密布
	var gloom := maxf(intensity, weather.precip)
	sun.light_energy = lerpf(1.2, 0.35, gloom) * sun_up + 0.16 * moon_up + lightning.flash * 2.0
	if sun_elev > 0.0: # 日光：正午白 → 晨昏橙
		sun.light_color = Color(1.0, 0.55, 0.28).lerp(Color(1.0, 0.98, 0.94), 1.0 - dusk_f)
	else: # 月光：冷色微光
		sun.light_color = Color(0.55, 0.65, 0.9)
	sky_mat.set_shader_parameter("severity", gloom)
	# 云量：天气决定基调，云量偏置随机游走制造“有时碧空”；风暴时偏置锁回 1（必然满天）
	sky_mat.set_shader_parameter("coverage", clampf(lerpf(0.25, 0.95, gloom)
		* lerpf(weather.sky_cover_bias, 1.0, gloom), 0.0, 1.0))
	# 云形性格：平时随机游走（散云↔云堤），风暴必然是大片低云
	sky_mat.set_shader_parameter("cloud_character", maxf(weather.cloud_character, gloom))
	sky_mat.set_shader_parameter("time", provider.time)
	var day_bright := lerpf(0.12, 1.0, day_f)
	$Ocean.set_sun_direction(-light_from)
	$Ocean.set_sky_tint(Color(0.5, 0.68, 0.82).lerp(Color(0.38, 0.40, 0.44), gloom) * day_bright)
	$Ocean.set_boat_state(boat.global_position, -boat.global_transform.basis.z, boat.linear_velocity.length())
	$Ocean.mat.set_shader_parameter("precip", weather.precip)
	# 浑浊度：风浪搅沙 + 暴雨冲刷，浅滩透视度随之下降
	$Ocean.mat.set_shader_parameter("turbidity", 1.0 + intensity * 1.2 + weather.precip * 1.5)

	# 水下过渡：活动相机低于波面 → 水下环境（雾变浓变青、环境光压暗）
	var cam := get_viewport().get_camera_3d()
	var cam_pos: Vector3 = cam.global_position if cam else boat.global_position
	rain.update_rain(weather.precip, cam_pos,
		provider.get_wind_dir(), provider.get_wind_level(), underwater)
	var surf_h := provider.get_height(cam_pos.x, cam_pos.z)
	var uw_target := 1.0 if cam_pos.y < surf_h else 0.0
	underwater = move_toward(underwater, uw_target, delta / 0.3)
	# 海雾叠加在天气雾之上（水下另行过渡）；雨幕也有轻微霾化；夜晚雾色随天色压暗
	env.fog_density = lerpf(lerpf(0.0018, 0.005, intensity) + weather.fog01 * 0.035 + weather.precip * 0.010, 0.09, underwater)
	env.fog_light_color = (base_fog_color * lerpf(1.0, 0.45, gloom) * day_bright).lerp(Color(0.10, 0.26, 0.31) * day_bright, underwater) # 与 sky.gdshader 的 water_bg 地平线色一致；风暴时雾色变深灰
	env.fog_sky_affect = lerpf(0.5, 0.0, underwater)
	env.ambient_light_energy = lerpf(lerpf(0.3, 1.0, day_f), 0.45 * day_bright, underwater)
	# 水下背景由 sky shader 的 underwater uniform 负责（天空不吃雾，直接换背景会露馅）
	sky_mat.set_shader_parameter("underwater", underwater)
	# 环境音效：风 + 雨（水下闷化）
	ambience.update_ambience(provider.get_wind_level(), weather.precip, underwater, delta)
	# 水下光柱：水下 × 白天 × 太阳高度 × 清澈度（浑浊/风暴时几乎消失）
	var turb := 1.0 + intensity * 1.2 + weather.precip * 1.5
	var ray_strength := underwater * day_f * clampf(sun_elev * 1.5, 0.0, 1.0) * (1.0 - gloom * 0.7) * 0.30 / turb
	var sun_axis := -dir_to_sun / maxf(dir_to_sun.y, 0.25) # 单位深度传播向量
	rays.update_rays(cam_pos, ray_strength, sun_axis)

	if diving:
		var depth := maxf(0.0, surf_h - cam_pos.y)
		hud_label.text = (
			"潜水中 | 深度: %.1f m | 海床: %.0f m | 生态区: %s | 时刻: %s\nWASD 移动  Space/Ctrl 升降  Shift 加速  C 回船  Esc 释放鼠标"
			% [depth, -terrain.get_height(cam_pos.x, cam_pos.z),
				terrain.get_biome_name(cam_pos.x, cam_pos.z), day_night.clock_string()]
		)
	else:
		var speed_kn: float = boat.linear_velocity.length() * 1.944
		var wave_h: float = provider.get_height(boat.global_position.x, boat.global_position.z)
		var wind := provider.get_wind_level()
		var mode := "自动" if weather.is_auto() else "手动"
		hud_label.text = (
			"速度: %.1f 节 | 油门: %d%% | 浪高: %+.1f m\n风力: %.1f 级（%.0f 节） | 事件: %s | 能见度: %.0f m | 天气: %s | 时刻: %s\nW/S 油门  A/D 舵  1/2/3 手动设风  [/] 调时间  C 潜水  鼠标环顾  Esc 释放鼠标"
			% [speed_kn, roundi(boat.throttle * 100.0), wave_h,
				wind, WaveProvider.beaufort_to_kn(wind), weather.event_label(),
				weather.visibility_m(1.0 - day_f), mode, day_night.clock_string()]
		)
