shader_type spatial;
render_mode cull_disabled, blend_add, unshaded, depth_draw_never;

// 水下体积光柱：MultiMesh 四边形做圆柱广告牌（绕 Y 面向相机），
// 轴向沿太阳方向倾斜，噪声条纹缓慢流动，加性混合。
// intensity 由 main.gd 驱动：水下因子 × 太阳高度 × 清澈度。

uniform sampler2D ray_noise : filter_linear_mipmap, repeat_enable;
uniform float intensity = 0.0;
uniform vec3 sun_axis = vec3(0.0, -1.0, 0.0); // 光线传播方向单位深度向量（-sun_dir/sun_dir.y）

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// 圆柱广告牌：只绕 Y 面向相机（光柱保持竖直感）
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	vec3 fwd = normalize(vec3(to_cam.x, 0.0, to_cam.z) + vec3(1e-4, 0.0, 0.0));
	vec3 right = cross(vec3(0.0, 1.0, 0.0), fwd);
	// 柱轴沿阳光倾斜：局部 y∈[-25,0]，越深沿传播方向偏移越多
	vec3 world = origin + right * VERTEX.x + vec3(0.0, VERTEX.y, 0.0) + sun_axis * (-VERTEX.y);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	// 宽而柔的光带，缓慢下落流动
	float n = texture(ray_noise, vec2(UV.x * 1.2, UV.y * 0.12 + TIME * 0.015)).r;
	float bands = smoothstep(0.35, 0.95, n);
	float fade_y = smoothstep(0.0, 0.15, UV.y) * smoothstep(1.0, 0.72, UV.y); // 顶/底溶出
	float fade_x = sin(UV.x * PI); // 左右羽化
	float a = bands * fade_y * fade_x * intensity;
	ALBEDO = vec3(0.45, 0.75, 0.80);
	ALPHA = a;
}
