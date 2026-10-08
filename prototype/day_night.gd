class_name DayNightCycle
extends RefCounted

## 昼夜循环（W6）：唯一的时间数据源。昼夜调制太阳高度角与光照，
## 天气轴调制云/雨/雾——天空控制权分工：本模块输出太阳/月亮方位与日照强度，
## sky.gdshader 据此叠在天气着色之上。
## 6:00 日出，18:00 日落；夜晚由月亮接管平行光（与太阳严格对冲，简化模型）。

var hour := 10.0 ## 当前时刻 0..24
var day_length := 600.0 ## 一昼夜的真实秒数（10 分钟）
var time_scale := 1.0 ## 时间倍率（T 键切换 1 ↔ 30，便于观察昼夜过渡）


func update(delta: float) -> void:
	hour = fmod(hour + delta * time_scale / day_length * 24.0, 24.0)


func toggle_time_scale() -> void:
	time_scale = 30.0 if time_scale == 1.0 else 1.0


## 太阳高度角正弦：>0 白天，<0 夜晚。θ: 6:00=0（地平线）→ 12:00=π/2（天顶附近）
func sun_elevation() -> float:
	return sin((hour - 6.0) / 12.0 * PI)


## 指向太阳的单位向量：东（-x）升西（+x）落，略偏南（+z 倾斜）
func dir_to_sun() -> Vector3:
	var theta := (hour - 6.0) / 12.0 * PI
	return Vector3(-cos(theta), sin(theta), 0.35).normalized()


## 指向月亮：与太阳对冲（日落后月出，简化）
func dir_to_moon() -> Vector3:
	return -dir_to_sun()


## 日照因子 0 深夜 → 1 白天；晨昏蒙影平滑过渡（太阳贴近地平线的一段）
func day_factor() -> float:
	var e := sun_elevation()
	var t := clampf((e + 0.08) / 0.2, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 晨昏暖色调强度：太阳在地平线附近（|仰角| 小）时最强
func dusk_factor() -> float:
	return clampf(1.0 - absf(sun_elevation()) / 0.22, 0.0, 1.0)


## 当前主光源（太阳或月亮）的指向与强度权重
func active_light_dir() -> Vector3:
	return dir_to_sun() if sun_elevation() > 0.0 else dir_to_moon()


func clock_string() -> String:
	var h := int(hour)
	var m := int(fmod(hour, 1.0) * 60.0)
	return "%02d:%02d" % [h, m]
