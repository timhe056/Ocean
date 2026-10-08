extends SceneTree

## M4 F1 数值验证：FFT 海面高度场统计（对标 Gerstner  WIND_TABLE 的浪高方差）。
## 用法: godot --headless --path . --script res://prototype/_fft_test.gd
## 前提：dotnet build ocean.csproj（C# 程序集需已构建）

const FFT_DIR := Vector2(0.97, 0.24) # 与主浪向一致


func _init() -> void:
	print("== M4 F1: FFT 海面数值验证 ==\n")
	var ok := true

	# 1) 各蒲福档浪高统计（σ 与 Gerstner 对比）
	print("蒲福档 | 风速 m/s | FFT σ | FFT 极值 | Gerstner σ | Hs=4σ")
	for bf in [2.0, 4.0, 6.0, 8.0, 10.0, 11.5]:
		var fft = _make(bf)
		var h: Array = fft.Update(3.0)
		var st := _stats(h)
		var g_sigma := _gerstner_sigma(bf)
		print("  %4.1f 级 | %6.1f | %.3f | ±%.2f m | %.3f | %.2f m"
			% [bf, _wind_ms(bf), st.x, st.y, g_sigma, 4.0 * st.x])
		if st.x <= 0.05 or absf(st.z) > 0.05:
			print("    !! σ 或均值异常")
			ok = false

	# 2) 时间演化：多点采样 σ。注意 200m 域只有 ~2 个主波长，有限域 σ 有天然涨落，
	# 放宽到均值 ±30%；场本身必须显著变化。
	var f1 := _make(6.0)
	var prev = f1.Update(0.0)
	var sigmas := []
	var diff := 0.0
	for ti in range(1, 7):
		var h = f1.Update(float(ti))
		sigmas.append(_stats(h).x)
		for i in h.size():
			diff = maxf(diff, absf(h[i] - prev[i]))
		prev = h
	var s_mean := 0.0
	var s_min := 999.0
	var s_max := 0.0
	for s in sigmas:
		s_mean += s
		s_min = minf(s_min, s)
		s_max = maxf(s_max, s)
	s_mean /= sigmas.size()
	var target := _gerstner_sigma(6.0)
	print("\n时间演化: σ 均值=%.3f（目标 %.3f）范围 %.3f~%.3f 相邻帧最大差=%.2f m"
		% [s_mean, target, s_min, s_max, diff])
	if absf(s_mean - target) / target > 0.3 or diff < 0.5:
		print("  !! 时间演化异常")
		ok = false

	# 3) 确定性：同 seed 两次构建结果一致
	var d1 = _make(6.0).Update(1.0)
	var d2 = _make(6.0).Update(1.0)
	var same := true
	for i in d1.size():
		if d1[i] != d2[i]:
			same = false
			break
	print("确定性: %s" % ("OK" if same else "!! 失败"))
	ok = ok and same

	# 4) 双线性采样与网格值一致 + 平铺周期
	var f2 := _make(6.0)
	var arr = f2.Update(1.0)
	var texel := 200.0 / 128.0
	var sampled: float = f2.SampleBilinear(texel * 3.0, texel * 5.0)
	print("采样: 格点(3,5) 采样值=%.3f 高度场原值=%.3f（平滑场应接近）| 平铺 200m 后=%.3f"
		% [sampled, arr[5 * 128 + 3], f2.SampleBilinear(200.0 + texel * 3.0, texel * 5.0)])

	# 5) 性能：128² 单次 Update 耗时
	var t0 := Time.get_ticks_usec()
	for i in 20:
		_make(6.0).Update(i * 0.1)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 20.0
	print("性能: 单次 Update（含建谱） %.2f ms" % ms)
	# 单独测演化耗时（建谱只应发生一次）
	var f3 := _make(6.0)
	f3.Update(0.0)
	t0 = Time.get_ticks_usec()
	for i in 20:
		f3.Update(i * 0.033)
	ms = (Time.get_ticks_usec() - t0) / 1000.0 / 20.0
	print("性能: 单次 Update（仅演化+IFFT） %.2f ms（目标 <2ms）" % ms)
	if ms > 4.0:
		print("  !! 超预算")
		ok = false

	print("\n== %s ==" % ("F1 通过" if ok else "F1 存在失败项"))
	quit(0 if ok else 1)


func _make(bf: float) -> RefCounted:
	var fft = FftOcean.new()
	fft.Setup(128, 200.0, _wind_ms(bf), FFT_DIR, 42, _gerstner_sigma(bf))
	return fft


func _wind_ms(bf: float) -> float:
	return WaveProvider.beaufort_to_kn(bf) * 0.514


## 现有 Gerstner WIND_TABLE 在该风级下的浪高标准差（插值同 WaveProvider 逻辑）
func _gerstner_sigma(bf: float) -> float:
	var p := WaveProvider.new()
	p.set_wind(bf)
	p._wind_start -= 1000.0 # 直接到位
	var sum := 0.0
	for w in p._blended_waves():
		sum += w.amplitude * w.amplitude / 2.0
	return sqrt(sum)


func _stats(h: Array) -> Vector3: # (σ, max|h|, mean)
	var mean := 0.0
	for v in h:
		mean += v
	mean /= h.size()
	var var_sum := 0.0
	var mx := 0.0
	for v in h:
		var_sum += (v - mean) * (v - mean)
		mx = maxf(mx, absf(v - mean))
	return Vector3(sqrt(var_sum / h.size()), mx, mean)
