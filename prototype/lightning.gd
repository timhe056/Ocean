extends Node

## 雷电：雷暴事件期间随机闪电（天空闪光 + 平行光脉冲）+ 程序合成雷声。
## 雷声延迟 = 距离 / 340m/s，音量随距离衰减——远雷闷闷、近雷炸响。

var flash := 0.0 ## 闪光强度 0..1.4（衰减快）
var flash_dir := Vector2(1, 0) ## 闪电方位
var flash_seed := 0.0 ## 每次闪电的随机种子（驱动天空 shader 的锯齿光柱形状）

var _next_strike := 5.0
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _thunder_delay := -1.0
var _thunder_left := 0.0
var _thunder_vol := 0.0
var _brown := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 5.0
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()


func _exit_tree() -> void:
	_player.stop()
	_playback = null # 释放强引用，避免退出时 ObjectDB 泄漏警告


## 每帧调用：is_thunder = 当前处于雷暴事件的闪电窗口
func update_storm(delta: float, is_thunder: bool) -> void:
	if is_thunder:
		_next_strike -= delta
		if _next_strike <= 0.0:
			_next_strike = randf_range(2.5, 9.0)
			_strike()
	flash = maxf(0.0, flash - delta * 5.0)

	if _thunder_delay > 0.0:
		_thunder_delay -= delta
		if _thunder_delay <= 0.0:
			_thunder_left = randf_range(1.5, 3.0)

	if _thunder_left > 0.0:
		_push_thunder()


func _strike() -> void:
	flash = 1.4 if randf() < 0.25 else 1.0 # 25% 双连闪更亮
	flash_dir = Vector2.RIGHT.rotated(randf() * TAU)
	flash_seed = randf() * 100.0
	var dist := randf_range(300.0, 2500.0)
	_thunder_delay = dist / 340.0
	_thunder_vol = clampf(1.3 - dist / 2500.0, 0.25, 1.0)


## 布朗噪声爆发 + 指数衰减包络 = 雷声
func _push_thunder() -> void:
	var frames := mini(_playback.get_frames_available(), 2048)
	for i in frames:
		_brown = clampf((_brown + randf_range(-1.0, 1.0) * 0.09) * 0.985, -1.0, 1.0)
		var env := clampf(_thunder_left / 2.0, 0.0, 1.0)
		var s := _brown * env * env * _thunder_vol * 0.9
		_playback.push_frame(Vector2(s, s))
		_thunder_left -= 1.0 / 22050.0
		if _thunder_left <= 0.0:
			break
