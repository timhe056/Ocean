shader_type spatial;
// blend_mix + depth_draw_opaque：强制进入透明通道渲染（深度/屏幕纹理拷贝之后），
// 否则读 DEPTH_TEXTURE 会读到自己 → 水深为 0 → 全屏透视发白。
// ALPHA 恒为 1，视觉与不透明一致；render_priority=-1 保证画在雨幕粒子之前。
render_mode cull_disabled, blend_mix, depth_draw_opaque; // 双面渲染：水下抬头能看到海面背面

// Gerstner 波浪海面。波形参数由 WaveProvider 在运行时注入，
// 顶点位移（几何）与逐像素解析法线（光照细节）使用同一公式。

uniform vec4 wave_a[4]; // dir.x, dir.y, k, omega
uniform vec4 wave_b[4]; // amplitude, steepness, -, -
uniform float time;
// 只有前 displace_count 个波参与顶点位移：网格分辨率 ~5.9m，
// 波长 < ~12m 的波欠采样会混叠成方形网格图案；小波只进逐像素法线。
uniform int displace_count = 3;
// 相机位置（由 ocean.gd 每帧注入），用于顶点位移距离淡出
uniform vec3 camera_pos = vec3(0.0);

uniform vec3 deep_color : source_color = vec3(0.012, 0.08, 0.13);
uniform vec3 shallow_color : source_color = vec3(0.04, 0.28, 0.33);
uniform vec3 sky_color : source_color = vec3(0.5, 0.68, 0.82);
uniform vec3 foam_color : source_color = vec3(0.92, 0.94, 0.95);
uniform vec3 sun_direction = vec3(0.0, -1.0, 0.0); // 光线传播方向
uniform int debug_view = 0; // 0=正常 1=白沫 mask 灰度图（排查用）
// 白沫噪声纹理（ocean.gd 生成，无缝 + mipmap）：硬件过滤无晶格接缝，
// 远距离自动抗混叠——这是取代程序化格点噪声的原因。
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;

// 船尾迹（由 main.gd 每帧注入）：船体接触白沫 + 航速驱动的 V 形尾流
uniform vec2 boat_pos = vec2(0.0);
uniform vec2 boat_dir = vec2(0.0, -1.0); // 船头朝向
uniform float boat_speed = 0.0; // m/s
uniform float precip = 0.0; // 降水强度 0..1（weather 注入）
uniform float spray = 0.0; // 飞沫强度 0..1：8.5 级风以上浪峰被风撕成水雾（main.gd 注入）
uniform float camera_underwater = 0.0; // 相机在水下才走背面透光渲染（否则浪尖背面会露青色）
// M4 FFT 后端：高度场纹理（R 通道=浪高米，200m 域平铺），use_fft=1 时替代 Gerstner
uniform int use_fft = 0;
uniform sampler2D fft_height : filter_linear_mipmap, repeat_enable;
uniform float fft_domain = 200.0;
uniform float turbidity = 1.0; // 浑浊度：1 清澈，风浪/降水搅起泥沙时升高（main.gd 注入）
uniform float refraction_strength = 0.06; // 折射扭曲强度
// 屏幕空间折射：浅滩透出海底（屏幕色 + 深度衰减），深海/浑浊时退回纯水体色
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

varying vec3 world_pos; // 位移后的世界坐标
varying vec2 grid_xz; // 位移前的网格坐标（用于逐像素精确求法线/浪高）

vec3 gerstner(vec2 xz, float t) {
	vec3 disp = vec3(0.0);
	if (use_fft == 1) {
		// FFT 后端：顶点位移用 lod2（≈CPU 侧 5×5 平滑场，抑制 <6m 短波防混叠）
		disp.y = textureLod(fft_height, xz / fft_domain, 2.0).r;
		return disp;
	}
	for (int i = 0; i < displace_count; i++) {
		vec2 d = wave_a[i].xy;
		float k = wave_a[i].z;
		float om = wave_a[i].w;
		float amp = wave_b[i].x;
		float q = wave_b[i].y;
		float ph = k * dot(d, xz) - om * t;
		disp.y += amp * sin(ph);
		disp.xz += q * amp * d * cos(ph);
	}
	return disp;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	grid_xz = wp.xz;
	vec3 disp = gerstner(wp.xz, time);
	// 掠射角下远处三角形被压成亚像素，顶点位移会产生网格摩尔纹；
	// 几何随距离淡出变平，细节由逐像素法线（平滑，无网格纹）接管。
	float cam_dist = length(wp.xz - camera_pos.xz);
	disp *= 1.0 - smoothstep(150.0, 700.0, cam_dist);
	VERTEX += disp; // 海面网格只有平移，局部位移 == 世界位移
	world_pos = wp + disp;
}

// 解析法线（GPU Gems 1 第 12 式近似），逐像素计算，小浪也清晰。
// detail_fade：17m/9m 小波在远处缩到像素尺度会混叠成规则点阵，随距离淡出，
// 只留 60m/31m 大涌（远处仍远大于像素，不会混叠）。
vec3 wave_normal(vec2 xz, float t, float detail_fade) {
	if (use_fft == 1) {
		// 高度场差分法线（双线性过滤+mipmap，远距自动平滑，无混叠淡出需求）
		float st = 1.0 / 128.0;
		vec2 uv = xz / fft_domain;
		float hL = texture(fft_height, uv - vec2(st, 0.0)).r;
		float hR = texture(fft_height, uv + vec2(st, 0.0)).r;
		float hD = texture(fft_height, uv - vec2(0.0, st)).r;
		float hU = texture(fft_height, uv + vec2(0.0, st)).r;
		float texel = fft_domain / 128.0;
		return normalize(vec3(hL - hR, 2.0 * texel, hD - hU));
	}
	vec3 n = vec3(0.0, 1.0, 0.0);
	for (int i = 0; i < 4; i++) {
		vec2 d = wave_a[i].xy;
		float k = wave_a[i].z;
		float om = wave_a[i].w;
		float amp = wave_b[i].x * (i < 2 ? 1.0 : detail_fade);
		float q = wave_b[i].y;
		float ph = k * dot(d, xz) - om * t;
		n.x -= d.x * k * amp * cos(ph);
		n.z -= d.y * k * amp * cos(ph);
		n.y -= q * k * amp * sin(ph);
	}
	return normalize(n);
}

// 逐像素浪面高度（仅 y 分量，含全部 4 个波）。白沫/透光必须用它而不是
// 顶点 varying——插值场在三角形边界梯度突变，阈值切割后会显出网格纹。
float wave_height_at(vec2 xz, float t, float detail_fade) {
	if (use_fft == 1) {
		// 用 lod1 平滑场：全分辨率场含大量短波，直接把 SSS/波峰混色打成噪斑
		return textureLod(fft_height, xz / fft_domain, 1.0).r;
	}
	float h = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 d = wave_a[i].xy;
		float k = wave_a[i].z;
		float om = wave_a[i].w;
		float amp = wave_b[i].x * (i < 2 ? 1.0 : detail_fade);
		h += amp * sin(k * dot(d, xz) - om * t);
	}
	return h;
}

void fragment() {
	vec3 to_point = world_pos - CAMERA_POSITION_WORLD;
	float dist = length(to_point);
	// 小尺度细节统一的距离淡出（17m/9m 波 + 白沫噪声）
	float detail_fade = 1.0 - smoothstep(150.0, 500.0, dist);
	vec3 n = wave_normal(grid_xz, time, detail_fade);
	float wave_height = wave_height_at(grid_xz, time, detail_fade);
	vec3 view_dir = normalize(to_point);
	vec3 v = -view_dir;

	// 水下看海面背面：深青暗色 + 朝太阳方向的透光亮斑（白沫/尾迹不适用）。
	// 仅当相机真的在水下时才这么画——水上掠射角看大浪背面（浪尖轮廓）仍走正面着色，
	// 否则浪尖会出现青色描边。
	if (!FRONT_FACING && camera_underwater > 0.5) {
		float sun_glow = pow(max(dot(view_dir, -sun_direction), 0.0), 3.0);
		vec3 under = mix(vec3(0.10, 0.28, 0.32), vec3(0.60, 0.75, 0.70), sun_glow);
		under += shallow_color * clamp(wave_height * 0.4, 0.0, 0.6); // 浪峰透光
		under += vec3(0.10, 0.16, 0.17) * max(view_dir.y, 0.0); // 仰视更亮：光从上方来
		ALBEDO = vec3(0.02, 0.08, 0.10);
		EMISSION = under; // 水面从下方看是逆光的，用自发光建模，不受水下暗环境影响
		ALPHA = 1.0;
		ROUGHNESS = 0.35;
		SPECULAR = 0.3;
		METALLIC = 0.0;
		NORMAL = normalize((VIEW_MATRIX * vec4(-n, 0.0)).xyz);
	} else {
	vec3 fn = FRONT_FACING ? n : -n; // 水上看到的背面（浪尖远坡）翻转法线

	// 雨滴涟漪：高频噪声扰动法线，雨越大海面越"毛"
	if (precip > 0.01) {
		float r1 = texture(foam_noise, grid_xz * 0.9 + vec2(time * 0.90, time * 0.71)).r;
		float r2 = texture(foam_noise, grid_xz * 0.9 + vec2(0.37, 0.71) - vec2(time * 0.83, time * 0.94)).r;
		fn.xz += (vec2(r1, r2) - 0.5) * precip * 0.35;
		fn = normalize(fn);
	}

	// 菲涅尔：掠射角反射天空
	float ndv = max(dot(fn, v), 0.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

	// 水体颜色：波峰偏浅
	float h_mix = clamp(wave_height * 0.45 + 0.5, 0.0, 1.0);
	vec3 water = mix(deep_color, shallow_color, h_mix);

	// 逆光次表面散射：浪峰迎着太阳透光，是"真实大海"的标志性效果
	float backlit = max(dot(view_dir, -sun_direction) * 0.5 + 0.5, 0.0);
	float sss = pow(backlit, 3.0) * clamp(wave_height * 0.5, 0.0, 1.0);
	water += shallow_color * sss * 0.7;

	vec3 col = mix(water, sky_color, fresnel);

	// --- 透视海底：折射采样屏幕色，按水深衰减（浅滩清亮可见，深海/浑浊不可见）---
	float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw); // Godot4 反向 Z：z 直接用原值
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float water_depth = max(-view_pos.z - (-VERTEX.z), 0.0);
	// 波面法线扭曲折射采样点，浪一动海底就跟着晃；深度越大扭曲越明显
	vec2 ref_off = n.xz * refraction_strength * clamp(water_depth * 0.15, 0.0, 1.0);
	vec2 ref_uv = clamp(SCREEN_UV - ref_off, vec2(0.001), vec2(0.999));
	// 折射点若落到比水面更近的物体上（船/天空），退回原采样点避免错位
	float depth_ref = texture(DEPTH_TEXTURE, ref_uv).r;
	vec4 view_ref = INV_PROJECTION_MATRIX * vec4(vec3(ref_uv * 2.0 - 1.0, depth_ref), 1.0);
	view_ref.xyz /= view_ref.w;
	if (-view_ref.z < -VERTEX.z + 0.05) {
		ref_uv = SCREEN_UV;
	}
	vec3 bottom = texture(SCREEN_TEXTURE, ref_uv).rgb;
	// 水体吸收：红光先被吸收（海水偏青），浑浊度加速衰减
	vec3 absorb = exp(-water_depth * turbidity * vec3(0.42, 0.16, 0.10));
	float bottom_vis = exp(-water_depth * 0.14 * turbidity);
	vec3 through = bottom * absorb * 1.3;
	col = mix(col, through, bottom_vis * (1.0 - fresnel * 0.9));

	// 白沫：坡度判据为主（物理上白沫产生在波面过陡即将破碎处，与绝对浪高解耦，
	// 各海况档位覆盖率自动合理：平静几乎无、中等浪峰偶现、风暴多但呈条状）；
	// 浪高项只是让泡沫偏向浪峰的小修正。噪声纹理破碎 + 距离淡出。
	// FFT 后端：白沫坡度用 lod1 平滑场法线（全分辨率法线的小波能量会把坡度打满）
	float steep;
	float foam_wh = wave_height; // 白沫用浪高（FFT 下取平滑场）
	if (use_fft == 1) {
		float st1 = 1.0 / 128.0;
		vec2 uv1 = grid_xz / fft_domain;
		float fL = textureLod(fft_height, uv1 - vec2(st1, 0.0), 1.0).r;
		float fR = textureLod(fft_height, uv1 + vec2(st1, 0.0), 1.0).r;
		float fD = textureLod(fft_height, uv1 - vec2(0.0, st1), 1.0).r;
		float fU = textureLod(fft_height, uv1 + vec2(0.0, st1), 1.0).r;
		float texel1 = fft_domain / 64.0;
		vec3 nf = normalize(vec3(fL - fR, 2.0 * texel1, fD - fU));
		steep = 1.0 - nf.y;
		foam_wh = textureLod(fft_height, uv1, 1.0).r;
	} else {
		steep = 1.0 - fn.y;
	}
	float n1 = texture(foam_noise, grid_xz * 0.045 + vec2(time * 0.020, time * 0.013)).r;
	vec2 ruv = vec2(grid_xz.x * 0.6 - grid_xz.y * 0.8, grid_xz.x * 0.8 + grid_xz.y * 0.6) * 0.11;
	float n2 = texture(foam_noise, ruv - vec2(time * 0.028, time * 0.017)).r;
	float noise_v = n1 * 0.65 + n2 * 0.35;
	float breaker = steep + foam_wh * 0.02 + (noise_v - 0.5) * 0.10 * detail_fade;
	float foam = smoothstep(0.075, 0.15, breaker);
	foam *= exp(-dist * 0.012); // 远处淡出白沫

	// --- 飞沫（spindrift）：8.5 级以上大风把浪峰撕成水雾——
	// 沿主风向拉伸的高速滚动条纹，只出现在高而陡的浪峰上 ---
	if (spray > 0.01) {
		vec2 wdir = normalize(wave_a[0].xy); // 主浪向
		vec2 suv = vec2(dot(grid_xz, wdir), dot(grid_xz, vec2(-wdir.y, wdir.x)));
		float sp = texture(foam_noise, suv * vec2(0.025, 0.18) + vec2(time * 0.30, time * 0.02)).r;
		float crest = smoothstep(0.4, 1.4, wave_height) * smoothstep(0.05, 0.12, steep);
		float sp_amt = smoothstep(0.45, 0.8, sp) * crest * spray * detail_fade;
		foam = max(foam, sp_amt * 0.5);
	}

	// --- 船尾迹：船体接触白沫（低速也在，解决船海交接生硬）+ V 形尾流（随航速）---
	vec2 rel = grid_xz - boat_pos;
	float fwd = dot(rel, boat_dir); // >0 船头方向
	float side = dot(rel, vec2(-boat_dir.y, boat_dir.x));
	float spd_f = clamp(boat_speed * 0.3, 0.0, 1.0);
	float hull_foam = 1.0 - smoothstep(0.5, 1.1, length(vec2(side / 1.6, fwd / 3.0)));
	hull_foam *= 0.35 + 0.65 * spd_f;
	float behind = clamp(-fwd, 0.0, 40.0);
	float wake_width = 0.9 + behind * 0.32;
	float v_wake = (1.0 - smoothstep(wake_width * 0.4, wake_width, abs(side)))
		* exp(-behind * 0.10) * step(fwd, 0.0) * spd_f;
	float wake = clamp(hull_foam + v_wake, 0.0, 1.0) * (0.55 + 0.45 * noise_v);
	foam = max(foam, wake);
	col = mix(col, foam_color, foam * 0.85);

	ALBEDO = col;
	ALPHA = 1.0;
	if (debug_view == 1) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(foam);
	}
	if (debug_view == 2) { // 水深调试图：白=深 黑=浅
		ALBEDO = vec3(0.0);
		EMISSION = vec3(clamp(water_depth * 0.1, 0.0, 1.0));
	}
	ROUGHNESS = mix(0.06, 0.55, foam) + precip * 0.08;
	SPECULAR = 0.5;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(fn, 0.0)).xyz);
	}
}
