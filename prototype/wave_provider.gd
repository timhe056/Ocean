class_name WaveProvider
extends RefCounted

## 波形参数的唯一数据源，CPU（浮力物理）与 GPU（海面 shader）共享同一套参数，
## 保证"看到的浪"和"托住船的浪"完全一致。
## 蒲福风级连续化：set_wind() 设定目标风级，风力按固定速率渐变，
## 波参数在 WIND_TABLE 相邻档位间连续插值。想调海况，只改 WIND_TABLE。

const GRAVITY := 9.8
## 风力渐变速度（蒲福级/秒）：9 级巨浪需要在 ~10s 内长起来
const WIND_RATE := 0.5


class Wave:
	var dir: Vector2 # 传播方向（已归一化）
	var amplitude: float # 振幅 (m)
	var steepness: float # 陡峭度 Q，控制波峰水平位移
	var wavelength: float # 波长 λ (m)
	var k: float # 波数 2π/λ
	var omega: float # 角频率 sqrt(g·k)，深水色散关系

	func _init(p_dir: Vector2, p_amplitude: float, p_steepness: float, p_wavelength: float) -> void:
		dir = p_dir.normalized()
		amplitude = p_amplitude
		steepness = p_steepness
		wavelength = p_wavelength
		k = TAU / p_wavelength
		omega = sqrt(GRAVITY * k)


## 蒲福风级 → 波参数关键帧表（4 个波分量，波长从大到小）。
## sum(steepness * amplitude * k) 应远小于 1，否则波峰会打卷穿模。
const WIND_TABLE: Array[Dictionary] = [
	{"level": 2.0, "waves": [ # 轻风：涟漪
		[Vector2(1.0, 0.25), 0.15, 0.12, 40.0],
		[Vector2(0.85, -0.45), 0.08, 0.14, 20.0],
		[Vector2(0.4, 0.9), 0.04, 0.15, 11.0],
		[Vector2(0.95, 0.6), 0.02, 0.18, 6.0],
	]},
	{"level": 4.0, "waves": [ # 和风：小浪
		[Vector2(1.0, 0.25), 0.55, 0.15, 50.0],
		[Vector2(0.85, -0.45), 0.30, 0.16, 26.0],
		[Vector2(0.4, 0.9), 0.14, 0.18, 14.0],
		[Vector2(0.95, 0.6), 0.07, 0.20, 8.0],
	]},
	{"level": 6.0, "waves": [ # 强风：中浪，白沫常见
		[Vector2(1.0, 0.25), 1.2, 0.16, 60.0],
		[Vector2(0.85, -0.45), 0.65, 0.18, 32.0],
		[Vector2(0.4, 0.9), 0.35, 0.20, 18.0],
		[Vector2(0.95, 0.6), 0.17, 0.22, 9.5],
	]},
	{"level": 8.0, "waves": [ # 大风：大浪，白沫成带
		[Vector2(1.0, 0.25), 2.3, 0.16, 80.0],
		[Vector2(0.85, -0.45), 1.35, 0.18, 45.0],
		[Vector2(0.4, 0.9), 0.80, 0.20, 24.0],
		[Vector2(0.95, 0.6), 0.45, 0.24, 12.0],
	]},
	{"level": 10.0, "waves": [ # 狂风：狂浪，飞沫
		[Vector2(1.0, 0.25), 3.4, 0.16, 100.0],
		[Vector2(0.85, -0.45), 2.0, 0.18, 55.0],
		[Vector2(0.4, 0.9), 1.15, 0.20, 30.0],
		[Vector2(0.95, 0.6), 0.65, 0.24, 14.0],
	]},
	{"level": 11.5, "waves": [ # 飓风：非凡巨浪
		[Vector2(1.0, 0.25), 4.8, 0.16, 120.0],
		[Vector2(0.85, -0.45), 2.8, 0.18, 65.0],
		[Vector2(0.4, 0.9), 1.6, 0.20, 34.0],
		[Vector2(0.95, 0.6), 0.9, 0.24, 16.0],
	]},
]

## 参与位移/浮力的大波个数：海面网格 ~5.9m/格，波长 < ~12m 会混叠出方形图案，
## 因此最小的波只做 shader 逐像素法线细节，CPU 与顶点位移都只取前 3 个大波。
var displace_count := 3

## 涌浪通道（0..1）：远处风暴的长周期涌浪先到，与本地风脱节。
## 作用于最大波分量：波长拉长、波幅抬升、坡度放缓（涌浪是平滑长滚浪）。
const SWELL_WAVELENGTH := 200.0 ## 涌浪目标波长（周期 ~11.3s）
const SWELL_AMPLITUDE := 1.6 ## 满涌浪时主波最小波幅（m）
var _swell := 0.0

var _wind_from := 4.5
var _wind_target := 4.5
var _wind_start := -100.0


## 全局统一时钟（引擎启动以来的秒数），渲染与物理都用它，天然同步。
var time: float:
	get:
		return Time.get_ticks_msec() * 0.001


## 设定目标风力（蒲福级，连续值），按 WIND_RATE 渐变。
func set_wind(level: float) -> void:
	level = clampf(level, 1.5, 11.5)
	if absf(level - _wind_target) < 0.01:
		return
	_wind_from = get_wind_level()
	_wind_target = level
	_wind_start = time


## 当前实际风力（渐变中）
func get_wind_level() -> float:
	var moved := (time - _wind_start) * WIND_RATE
	return move_toward(_wind_from, _wind_target, moved)


## 天气强度 0(2 级) ~ 1(11.5 级)：天空/光照/雾据此联动。
func current_intensity() -> float:
	return clampf((get_wind_level() - 2.0) / 9.5, 0.0, 1.0)


## 设定涌浪强度（0..1，weather 每帧驱动），立即生效（weather 的轴曲线本身平滑）。
func set_swell(amount: float) -> void:
	_swell = clampf(amount, 0.0, 1.0)


func get_swell() -> float:
	return _swell


## 当前风力下的波参数：WIND_TABLE 相邻关键帧逐分量插值。
func _blended_waves() -> Array:
	var w := get_wind_level()
	var lo := WIND_TABLE[0]
	var hi := WIND_TABLE[WIND_TABLE.size() - 1]
	for i in WIND_TABLE.size() - 1:
		if WIND_TABLE[i].level <= w and w <= WIND_TABLE[i + 1].level:
			lo = WIND_TABLE[i]
			hi = WIND_TABLE[i + 1]
			break
	var t := 0.0
	if hi.level > lo.level:
		t = (w - lo.level) / (hi.level - lo.level)
	var out: Array = []
	for i in 4:
		var a: Array = lo.waves[i]
		var b: Array = hi.waves[i]
		out.append(Wave.new(
			(a[0] as Vector2).lerp(b[0], t),
			lerpf(a[1], b[1], t),
			lerpf(a[2], b[2], t),
			lerpf(a[3], b[3], t)
		))
	# 涌浪：改写最大波分量（方向不变——远处风暴与本地风浪同象限）
	if _swell > 0.001:
		var w0: Wave = out[0]
		out[0] = Wave.new(
			w0.dir,
			lerpf(w0.amplitude, maxf(w0.amplitude, SWELL_AMPLITUDE), _swell),
			lerpf(w0.steepness, minf(w0.steepness, 0.10), _swell),
			lerpf(w0.wavelength, SWELL_WAVELENGTH, _swell)
		)
	return out


## 主浪向（近似风向），用于风压差等
func get_wind_dir() -> Vector2:
	return (_blended_waves()[0] as Wave).dir


## 蔢福级 → 风速（节）
static func beaufort_to_kn(b: float) -> float:
	return 1.625 * pow(b, 1.5)


## 世界坐标 (x, z) 处在 t 时刻的浪面高度。t < 0 时使用当前时间。
## 必须与 ocean.gdshader 中 gerstner() 的 y 分量保持一致。
func get_height(x: float, z: float, t: float = -1.0) -> float:
	if t < 0.0:
		t = time
	var h := 0.0
	var waves := _blended_waves()
	for i in displace_count:
		var w: Wave = waves[i]
		h += w.amplitude * sin(w.k * (w.dir.x * x + w.dir.y * z) - w.omega * t)
	return h


## 打包成 shader uniform 数组：wave_a = (dir.x, dir.y, k, omega)，wave_b = (amp, steepness, 0, 0)
func get_shader_params() -> Dictionary:
	var wave_a := PackedVector4Array()
	var wave_b := PackedVector4Array()
	for w in _blended_waves():
		wave_a.append(Vector4(w.dir.x, w.dir.y, w.k, w.omega))
		wave_b.append(Vector4(w.amplitude, w.steepness, 0.0, 0.0))
	return {"wave_a": wave_a, "wave_b": wave_b, "displace_count": displace_count}
