shader_type spatial;
render_mode cull_disabled;

// 观赏鱼：MultiMesh 实例。INSTANCE_CUSTOM = (摆尾相位, 摆尾频率)。
// 摆尾在顶点着色器：越靠尾振幅越大（二次曲线），受惊时频率加快（wag_boost）。

uniform float fish_len = 0.3;
uniform float wag_boost = 1.0;

void vertex() {
	float tail01 = clamp(VERTEX.z / (0.62 * fish_len), 0.0, 1.0); // 头 0 → 尾 1
	float w = sin(TIME * INSTANCE_CUSTOM.y * wag_boost + INSTANCE_CUSTOM.x);
	VERTEX.x += w * tail01 * tail01 * 0.22 * fish_len;
}

void fragment() {
	ALBEDO = COLOR.rgb; // MultiMesh 实例颜色
	ROUGHNESS = 0.6;
}
