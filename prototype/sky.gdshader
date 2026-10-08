shader_type sky;

// 天气联动天空：晴空渐变 + 太阳 + fbm 云层。
// severity（0 平静→1 风暴）由 main.gd 按 WaveProvider 实际浪高每帧驱动，
// 云量、天色、太阳强度随之连续变化；云随风漂移。

uniform vec3 zenith_clear : source_color = vec3(0.18, 0.40, 0.70);
uniform vec3 horizon_clear : source_color = vec3(0.62, 0.72, 0.84);
uniform vec3 zenith_storm : source_color = vec3(0.10, 0.12, 0.15);
uniform vec3 horizon_storm : source_color = vec3(0.32, 0.35, 0.39);
uniform float severity = 0.0; // 0 平静 → 1 风暴
uniform float underwater = 0.0; // 0 水上 → 1 水下（背景整体变为水色）
uniform float flash = 0.0; // 闪电强度（lightning.gd 注入）
uniform vec2 flash_dir = vec2(1.0, 0.0); // 闪电方位
uniform float flash_seed = 0.0; // 每次闪电的随机种子（锯齿光柱形状）
// 云噪声纹理（main.gd 生成，Simplex fbm 无缝 + mipmap）：取代程序化格点噪声——
// value-noise 的正方形晶格被阈值切割后会显出矩形云块，纹理采样无此问题。
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float coverage = 0.3; // 云量 0..1
uniform float cloud_character = 0.3; // 云形性格：0 中小积云为主 ↔ 1 大片云堤
uniform vec3 sun_direction = vec3(0.0, -1.0, 0.0); // 光线传播方向
uniform float time = 0.0;
uniform vec2 wind_dir = vec2(0.97, 0.24); // 与主浪向一致
// W6 昼夜：day_factor 0 深夜→1 白天；dusk 晨昏暖调强度；moon_direction 指向月亮
uniform float day_factor = 1.0;
uniform float dusk = 0.0;
uniform vec3 moon_direction = vec3(0.0, 1.0, 0.0);

// fbm 值噪声：天空云不经过硬阈值切割，格点噪声的常规用法，无瓦片问题
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.13 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v; // ~[0, 1]
}

// 云形：双尺度反向漂移采样无缝纹理。大尺度定云团分布，小尺度打碎边缘。

void sky() {
	vec3 dir = EYEDIR;
	float y = max(dir.y, 0.0);
	float night = 1.0 - day_factor;

	// 天色：随强度从晴蓝渐变到铅灰；晨昏时地平线染暖色；夜晚压暗成深蓝黑
	vec3 zen = mix(zenith_clear, zenith_storm, severity);
	vec3 hor = mix(horizon_clear, horizon_storm, severity);
	hor = mix(hor, vec3(0.92, 0.45, 0.22), dusk * 0.65 * (1.0 - severity * 0.6));
	zen = mix(zen, vec3(0.008, 0.012, 0.030), night);
	hor = mix(hor, vec3(0.025, 0.035, 0.065), night);
	vec3 col = mix(hor, zen, pow(y, 0.55));

	// 太阳：盘 + 光晕，风暴时大幅衰减（被云遮蔽）；晨昏时染橙红，入夜消失
	float sun_d = max(dot(dir, -sun_direction), 0.0);
	float sun_vis = (1.0 - severity * 0.9) * day_factor;
	vec3 sun_tint = mix(vec3(1.0, 0.9, 0.72), vec3(1.0, 0.45, 0.18), dusk);
	col += sun_tint * pow(sun_d, 900.0) * 4.0 * sun_vis;
	col += mix(vec3(1.0, 0.95, 0.85), vec3(1.0, 0.55, 0.25), dusk) * pow(sun_d, 10.0) * 0.14 * sun_vis;

	// 月亮：小而亮的盘 + 微弱光晕，仅夜间可见
	if (night > 0.01) {
		float moon_d = max(dot(dir, moon_direction), 0.0);
		col += vec3(0.92, 0.95, 1.0) * pow(moon_d, 3500.0) * 3.0 * night;
		col += vec3(0.60, 0.68, 0.85) * pow(moon_d, 60.0) * 0.05 * night;
	}

	// 星星：方向量化哈希格点，夜越深越亮，风暴云层遮蔽
	if (night > 0.01 && dir.y > 0.01) {
		vec3 cell = floor(dir * 220.0);
		float h = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float star = smoothstep(0.997, 1.0, h);
		// 星光闪烁
		star *= 0.7 + 0.3 * sin(time * 3.0 + h * 100.0);
		col += vec3(0.9, 0.93, 1.0) * star * night * (1.0 - severity * 0.8) * smoothstep(0.01, 0.15, dir.y);
	}

	// 云：三尺度云形（云堤/积云/碎边）+ 超大尺度密度场（分布成团、有密有疏），
	// 沿风向压缩采样形成云街；风暴时云底压暗
	if (dir.y > 0.015) {
		vec2 cuv = dir.xz / (dir.y + 0.18);
		// 风向基：沿风向压缩 → 云被拉长成云街
		vec2 wd = normalize(wind_dir);
		vec2 wuv = vec2(dot(cuv, wd) * 0.6, dot(cuv, vec2(-wd.y, wd.x)));
		vec2 drift = wind_dir * time * (0.004 + severity * 0.022); // 风越大云跑得越快
		// 密度场：超大尺度缓慢起伏，决定哪里有云、哪里留白（分布不均匀的关键）
		float density = texture(cloud_noise, wuv * 0.02 + drift * 0.25 + vec2(0.13, 0.57)).r;
		// 均值≈1：密区云量可达 ~1.9×，疏区近乎留白
		float local_cov = clamp(coverage * (density * 2.6 - 0.3), 0.0, 1.0);
		// 云形三尺度：bank 大云堤 / mid 中积云 / det 碎边小云，性格控制大小配比
		float bank = texture(cloud_noise, wuv * 0.045 + drift * 0.6).r;
		float mid = texture(cloud_noise, wuv * 0.14 + drift).r;
		float det = texture(cloud_noise, wuv * 0.45 - drift * 1.5 + vec2(0.71, 0.23)).r;
		float shape = mix(mid * 0.70 + det * 0.30, bank * 0.60 + mid * 0.30 + det * 0.10,
			cloud_character);
		float cl = smoothstep(1.0 - local_cov, 1.0 - local_cov + 0.45, shape);
		cl *= smoothstep(0.015, 0.12, dir.y); // 贴近地平线处溶入天色
		vec3 cloud_bright = mix(vec3(0.95, 0.96, 0.98), vec3(0.34, 0.36, 0.40), severity);
		vec3 cloud_dark = mix(vec3(0.78, 0.82, 0.88), vec3(0.11, 0.12, 0.15), severity);
		// 云的受光面朝向太阳；晨昏染暖；夜晚云只剩微光剪影
		float lit = 0.5 + 0.5 * sun_d;
		vec3 cloud_col = mix(cloud_dark, cloud_bright, lit);
		cloud_col = mix(cloud_col, cloud_col * vec3(1.05, 0.62, 0.42), dusk * 0.7);
		cloud_col *= mix(1.0, 0.06, night);
		col = mix(col, cloud_col, cl);
	}

	// 地平线以下：给反射一个合理的深色
	if (dir.y < 0.0) {
		col = mix(col, hor * 0.55, smoothstep(0.0, -0.2, dir.y));
	}

	// 闪电：方位性天空增亮，云层被照亮；沿闪电方位画锯齿状光柱（远端雷击）
	if (flash > 0.01) {
		float az = max(dot(normalize(dir.xz + vec2(1e-4)), flash_dir) * 0.5 + 0.5, 0.0);
		col += vec3(0.9, 0.95, 1.0) * flash * (0.25 + 0.75 * az) * max(dir.y + 0.15, 0.0) * 1.4;
		// 闪电光柱：云底劈向地平线的锯齿亮带，每次闪电形状不同（flash_seed）
		if (dir.y > 0.01) {
			vec2 azv = normalize(dir.xz + vec2(1e-6));
			float fwd = dot(azv, flash_dir);
			float side = dot(azv, vec2(-flash_dir.y, flash_dir.x)); // 垂直于闪电方位的角偏差
			if (fwd > 0.3) {
				// 锯齿路径：横向偏移随高度抖动，越低摆动越大
				float jag = (vnoise(vec2(dir.y * 22.0 + flash_seed, flash_seed * 1.7)) - 0.5)
					* 0.10 * (1.2 - dir.y);
				float d = abs(side - jag) / max(fwd, 0.4);
				float vert = smoothstep(0.55, 0.42, dir.y) * smoothstep(0.008, 0.03, dir.y);
				float core = exp(-d * d * 220000.0); // 细亮芯
				float halo = exp(-d * d * 3000.0) * 0.25; // 外围电离光晕
				col += vec3(0.85, 0.9, 1.0) * (core + halo) * vert * flash * 3.0;
			}
		}
	}

	// 水下：背景整体变为水色（上明下暗），天空/云/太阳全部淹没
	vec3 water_bg = mix(vec3(0.02, 0.08, 0.11), vec3(0.12, 0.33, 0.38), dir.y * 0.5 + 0.5);
	col = mix(col, water_bg, underwater);

	COLOR = col;
}
