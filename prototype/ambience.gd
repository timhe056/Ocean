extends Node

## 环境音效（W5）：程序合成风声 + 雨声，无音频资源文件。
## 风声：布朗噪声（低频呼啸），音量/亮度随蒲福风级分级，带缓慢阵风起伏；
## 雨声：白噪声嘶声，密度随 weather.precip；入水后整体低通闷化 + 音量衰减。
## 每帧填充 AudioStreamGenerator 的空闲缓冲，合成开销可忽略（~368 样本/帧）。

const MIX_RATE := 22050

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _brown := 0.0 ## 风声布朗噪声状态
var _lp := 0.0 ## 一阶低通状态（水下闷化）
var _gust_phase := 0.0 ## 阵风缓慢起伏相位
var _rumble := 0.0 ## 水下低频涌动状态
var _bub_left := 0.0 ## 气泡音剩余时长
var _bub_freq := 800.0
var _bub_phase := 0.0

## 平滑后的输入（避免轴值抖动直接打进音频）
var _wind := 0.0
var _rain := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.5
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()


func _exit_tree() -> void:
	_player.stop()
	_playback = null # 释放强引用，避免退出时 ObjectDB 泄漏警告


## 每帧调用：wind_level 蒲福级，precip 0..1，underwater 0..1
func update_ambience(wind_level: float, precip: float, underwater: float, delta: float) -> void:
	if _playback == null:
		return
	_wind = lerpf(_wind, wind_level / 11.5, minf(delta * 2.0, 1.0))
	_rain = lerpf(_rain, precip, minf(delta * 2.0, 1.0))
	_gust_phase += delta

	var frames: int = mini(_playback.get_frames_available(), 2048)
	if frames <= 0:
		return

	# 阵风起伏：两个慢正弦叠加，风越大起伏越明显
	var lfo := 0.8 + 0.2 * sin(_gust_phase * 0.9) * sin(_gust_phase * 0.23 + 1.7)
	var wind_gain := pow(_wind, 1.6) * 0.55 * lfo
	var rain_gain := _rain * 0.22
	# 水下：音量压到 1/4，低通截止大幅压低（闷）
	var master := lerpf(1.0, 0.25, underwater)
	var lp_coef := lerpf(1.0, 0.06, underwater) # 一阶低通系数
	# 水下气泡：随机触发短促上扫 chirp
	if underwater > 0.3 and _bub_left <= 0.0 and randf() < delta * 1.5:
		_bub_left = randf_range(0.03, 0.09)
		_bub_freq = randf_range(500.0, 1400.0)

	for i in frames:
		# 风：布朗噪声（低频为主），风级越高允许的高频越多
		_brown = clampf((_brown + randf_range(-1.0, 1.0) * (0.02 + _wind * 0.10)) * 0.985, -1.0, 1.0)
		# 雨：白噪声
		var s := _brown * wind_gain + randf_range(-1.0, 1.0) * rain_gain
		_lp += (s - _lp) * lp_coef
		s = _lp * master
		if underwater > 0.01:
			# 水下：低频涌动（极慢布朗噪声）
			_rumble = clampf((_rumble + randf_range(-1.0, 1.0) * 0.004) * 0.995, -1.0, 1.0)
			s += _rumble * 0.35 * underwater
			# 气泡 chirp：频率缓升的正弦短音
			if _bub_left > 0.0:
				_bub_phase += TAU * _bub_freq / MIX_RATE
				_bub_freq *= 1.0016
				s += sin(_bub_phase) * 0.10 * clampf(_bub_left / 0.09, 0.0, 1.0)
				_bub_left -= 1.0 / MIX_RATE
		_playback.push_frame(Vector2(s, s))
