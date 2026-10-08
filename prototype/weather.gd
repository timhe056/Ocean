class_name WeatherSystem
extends RefCounted

## 天气系统 v2：三轴（wind 蒲福级 / precip 降水 / fog 海雾）+ gust 阵风尖峰通道。
## 天气以"事件"为单位编舞（每个事件是各轴的一段剧本），事件间马尔可夫链，
## 转移概率与轴状态耦合（大风不起雾、雷暴有冷却）。
## 手动 1/2/3 键设定风力并锁定一段时间，之后恢复自动。

## 背景风基线的随机游走范围（蒲福级）
const BASE_MIN := 2.5
const BASE_MAX := 5.5
## 雷暴冷却（秒）：决策"雷暴是罕见惊喜"
const THUNDER_COOLDOWN := 1200.0

## 事件剧本。每轴：[起始值, 峰值, 进入时刻 t01, 到达峰值 t01, 退出时刻 t01]。
## t01 为事件内归一化时间；退出后轴值线性回归背景。
const EVENTS: Dictionary = {
	"rain_front": {
		"label": "锋面降雨",
		"dur": [150.0, 300.0],
		"wind": [0.0, 1.8, 0.1, 0.5], # 相对背景风的增量
		"precip": [0.0, 0.75, 0.15, 0.5],
		"fog": [0.0, 0.1, 0.2, 0.6],
		"gust": 0.0,
		"swell": [0.0, 0.0, 0.0, 1.0],
	},
	"thunder_squall": {
		"label": "雷暴飑线",
		"dur": [180.0, 360.0],
		"wind": [0.0, 3.0, 0.25, 0.6],
		"precip": [0.0, 1.0, 0.35, 0.65],
		"fog": [0.0, 0.15, 0.3, 0.7],
		"gust": 2.8, # 阵风锋尖峰（t01 0.3 处）
		"swell": [0.0, 0.0, 0.0, 1.0],
	},
	"sea_fog": {
		"label": "海雾",
		"dur": [120.0, 360.0],
		"wind": [0.0, -0.5, 0.2, 0.6], # 雾里风更弱
		"precip": [0.0, 0.0, 0.0, 1.0],
		"fog": [0.0, 0.95, 0.2, 0.7],
		"gust": 0.0,
		"swell": [0.0, 0.0, 0.0, 1.0],
	},
	# 涌浪预警：远处风暴的长周期涌浪先到（浪变高变长但风不变），
	# 预示后续风暴——事件结束后强制跟随一个降雨/雷暴事件。
	"swell_surge": {
		"label": "涌浪预警",
		"dur": [60.0, 180.0],
		"wind": [0.0, 0.3, 0.2, 0.6], # 几乎不起风
		"precip": [0.0, 0.0, 0.0, 1.0],
		"fog": [0.0, 0.0, 0.0, 1.0],
		"gust": 0.0,
		"swell": [0.0, 1.0, 0.15, 0.55],
	},
}

var provider: WaveProvider
var manual_hold := 120.0 ## 手动切换后的锁定时长（秒）

## 三轴当前值（事件输出）
var precip := 0.0
var fog01 := 0.0
var swell := 0.0 ## 涌浪强度 0..1（WaveProvider.set_swell 的输入）
var cloud_character := 0.3 ## 云形性格 0=中小积云为主 ↔ 1=大片云堤（缓慢随机游走）
var sky_cover_bias := 1.0 ## 云量偏置 0.45~1.5（缓慢随机游走，偶有碧空）

var _wind_base := 4.5 ## 背景风（随机游走）
var _hold_left := 0.0
var _event: Dictionary = {} # 空 = 晴好期
var _event_t := 0.0
var _event_dur := 0.0
var _dwell_left := 60.0
var _thunder_cd := THUNDER_COOLDOWN * 0.5 # 开局不久即可遇到首次雷暴
var _gust_left := 0.0
var _pending_storm := false ## 涌浪预警过后，强制跟随一场风暴


func _init(p_provider: WaveProvider) -> void:
	provider = p_provider
	provider.set_wind(_wind_base)
	_dwell_left = randf_range(180.0, 420.0) # 晴好期 3~7 分钟


func update(delta: float) -> void:
	if _hold_left > 0.0:
		_hold_left -= delta
		return
	# 背景风随机游走（约 ±0.3 级/分钟）
	_wind_base = clampf(_wind_base + (randf() - 0.5) * delta * 0.01, BASE_MIN, BASE_MAX)
	_thunder_cd -= delta
	# 云性格/云量偏置的缓慢随机游走：同一片海，天空隔几分钟就换一副面孔
	cloud_character = clampf(cloud_character + (randf() - 0.5) * delta * 0.016, 0.0, 1.0)
	sky_cover_bias = clampf(sky_cover_bias + (randf() - 0.5) * delta * 0.008, 0.45, 1.5)

	if _event.is_empty():
		_dwell_left -= delta
		if _dwell_left <= 0.0:
			_start_event()
	else:
		_event_t += delta
		if _event_t >= _event_dur:
			# 涌浪事件结束 → 标记风暴跟随，且很快到来
			var was_swell: bool = _event.get("label", "") == "涌浪预警"
			_event = {}
			_dwell_left = randf_range(30.0, 90.0) if was_swell else randf_range(120.0, 300.0)
			if was_swell:
				_pending_storm = true

	_apply(delta)


func _start_event() -> void:
	var wind_now: float = provider.get_wind_level()
	# 候选与条件概率：大风不起雾；雷暴有冷却；连续同事件降权
	var candidates: Array[String] = []
	if _pending_storm:
		# 涌浪过后必有风暴：强降雨为主，冷却允许时可能升级为雷暴
		candidates.append_array(["rain_front", "rain_front", "rain_front"])
		if _thunder_cd <= 0.0:
			candidates.append("thunder_squall")
		_pending_storm = false
	else:
		if wind_now < 4.5:
			candidates.append_array(["sea_fog", "sea_fog"]) # 小风时雾更常见
		candidates.append_array(["rain_front", "rain_front"])
		if wind_now < 6.0:
			candidates.append("swell_surge") # 涌浪只在尚未起风时有意义
		if _thunder_cd <= 0.0:
			candidates.append("thunder_squall")
	var pick: String = candidates[randi() % candidates.size()]
	_event = EVENTS[pick]
	_event_t = 0.0
	_event_dur = randf_range(_event.dur[0], _event.dur[1])
	if pick == "thunder_squall":
		_thunder_cd = THUNDER_COOLDOWN


## 单轴剧本求值：t01 归一化时间内 进入→峰值→回归
func _axis_curve(spec: Array, t01: float) -> float:
	if spec[1] == 0.0:
		return 0.0
	var v: float = spec[1]
	if t01 < spec[2]: # 尚未开始
		return 0.0
	if t01 < spec[3]: # 爬升
		return v * smoothstepf(spec[2], spec[3], t01)
	# 峰值后线性回归到 0（事件结束时归零）
	return v * (1.0 - smoothstepf(spec[3], 1.0, t01))


func _apply(delta: float) -> void:
	var wind := _wind_base
	precip = 0.0
	fog01 = 0.0
	swell = 0.0
	if not _event.is_empty():
		var t01: float = clampf(_event_t / _event_dur, 0.0, 1.0)
		wind += _axis_curve(_event.wind, t01)
		precip = _axis_curve(_event.precip, t01)
		fog01 = _axis_curve(_event.fog, t01)
		swell = _axis_curve(_event.swell, t01)
		# 阵风锋：尖峰后指数衰减
		if _event.gust > 0.0 and _gust_left <= 0.0 and t01 >= 0.3:
			_gust_left = 25.0
	if _gust_left > 0.0:
		_gust_left -= delta
		var age := 25.0 - _gust_left
		# 阵风锋：3s 急升 + 18s 衰减
		wind += 2.5 * minf(age / 3.0, 1.0) * clampf(_gust_left / 18.0, 0.0, 1.0)
	provider.set_wind(wind)
	provider.set_swell(swell)


## 手动设定风力（1/2/3 键），锁定 manual_hold 秒不自动演变。
func manual_set(level: float) -> void:
	provider.set_wind(level)
	_hold_left = manual_hold
	# 手动期间清空事件，避免剧本继续推进
	_event = {}
	precip = 0.0
	fog01 = 0.0
	swell = 0.0
	provider.set_swell(0.0)
	_gust_left = 0.0
	_pending_storm = false


## 测试用：强制触发指定事件（20s 加速版）
func debug_force_event(event_name: String) -> void:
	if EVENTS.has(event_name):
		_event = EVENTS[event_name]
		_event_t = 0.0
		_event_dur = 20.0


## 手动触发事件（4/5/6/7 键）：使用真实时长，解除手动风锁定
func force_event(event_name: String) -> void:
	if EVENTS.has(event_name):
		_hold_left = 0.0
		_pending_storm = false
		_event = EVENTS[event_name]
		_event_t = 0.0
		_event_dur = randf_range(_event.dur[0], _event.dur[1])
		if event_name == "thunder_squall":
			_thunder_cd = THUNDER_COOLDOWN


## 清除当前事件恢复晴好（0 键），解除手动风锁定
func clear_event() -> void:
	_event = {}
	_hold_left = 0.0
	_pending_storm = false
	_gust_left = 0.0
	_dwell_left = randf_range(120.0, 300.0)
	provider.set_swell(0.0)
	swell = 0.0


func is_auto() -> bool:
	return _hold_left <= 0.0


func event_label() -> String:
	if not _event.is_empty():
		return _event.label
	return "晴好"


## 当前事件归一化进度（无事件为 0）
func event_t01() -> float:
	if _event.is_empty():
		return 0.0
	return clampf(_event_t / _event_dur, 0.0, 1.0)


## 能见度（米）：雾与降水的合成；夜晚再打折扣（月光下物标更难辨认）
func visibility_m(night01: float = 0.0) -> float:
	var vis := 3000.0
	vis = lerpf(vis, 120.0, fog01)
	vis = lerpf(vis, 400.0, precip * 0.8)
	return vis * lerpf(1.0, 0.55, clampf(night01, 0.0, 1.0))


static func smoothstepf(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
