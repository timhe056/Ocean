shader_type spatial;
render_mode cull_back;

// 海床着色：生态区混色（顶点色 r 连续插值）+ 坡度岩石化 + 焦散。
// 水下雾由 Environment 统一处理；焦散强度随深度与天气衰减。

uniform sampler2D caustic_noise : filter_linear_mipmap, repeat_enable;
uniform float time = 0.0;
uniform float light_fade = 1.0; // 1 晴天 → 0.25 风暴（main/terrain 注入）

varying vec3 world_pos;
varying float biome_coord;
varying vec3 wnormal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	biome_coord = COLOR.r * 3.0;
	wnormal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	// 生态区调色：0 浅滩沙地 / 1 藻场 / 2 岩礁 / 3 深海平原
	vec3 sand = vec3(0.62, 0.55, 0.40);
	vec3 kelp = vec3(0.15, 0.30, 0.16);
	vec3 reef = vec3(0.38, 0.32, 0.30);
	vec3 deep = vec3(0.08, 0.12, 0.17);
	vec3 col = mix(sand, kelp, smoothstep(0.4, 1.1, biome_coord));
	col = mix(col, reef, smoothstep(1.4, 2.1, biome_coord));
	col = mix(col, deep, smoothstep(2.4, 2.9, biome_coord));

	// 陡坡岩石化：坡度越陡越露岩
	float slope = 1.0 - normalize(wnormal).y;
	col = mix(col, reef * 0.7, smoothstep(0.15, 0.5, slope));

	// 深度压暗偏蓝
	float depth = -world_pos.y;
	col *= mix(1.0, 0.25, clamp(depth / 40.0, 0.0, 1.0));
	col = mix(col, vec3(0.04, 0.10, 0.14), clamp(depth / 45.0, 0.0, 0.7));

	// 焦散：噪声零交叉线（1-|2n-1|）取高次幂形成网状亮纹；浅水强、深水无、风暴弱
	float ca1 = texture(caustic_noise, world_pos.xz * 0.08 + vec2(time * 0.021, time * 0.013)).r;
	float ca2 = texture(caustic_noise, world_pos.xz * 0.11 - vec2(time * 0.017, time * 0.025)).r;
	float c1 = 1.0 - abs(ca1 * 2.0 - 1.0);
	float c2 = 1.0 - abs(ca2 * 2.0 - 1.0);
	float caustic = pow(c1 * c2, 4.0) * 0.9;
	caustic *= clamp(1.0 - depth / 28.0, 0.0, 1.0) * light_fade;
	col += vec3(0.9, 0.95, 0.9) * caustic;

	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
