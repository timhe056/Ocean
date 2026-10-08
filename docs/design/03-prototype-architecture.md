# 03 · 原型架构说明与调参指南（M1）

> 对应代码：`prototype/`。最后同步：2026-10-06

## 架构总览

```
main.tscn (Main, main.gd)
├── WorldEnvironment        PhysicalSky + ACES + 距离雾
├── DirectionalLight3D      太阳（方向同步给海面 shader 用于 SSS）
├── Ocean (ocean.gd)        3km 网格跟随相机；持有 ShaderMaterial
├── Boat (boat.gd)          RigidBody3D，浮力/推进/舵
├── CameraRig (camera_rig.gd)  跟随相机
└── HUD                     速度/油门/浪高

WaveProvider (wave_provider.gd)  ← 核心：波形参数唯一数据源
    ├── Ocean.setup() 注入 → shader uniforms (wave_a/wave_b)
    └── Boat.wave_provider 注入 → get_height() 物理采样
```

**核心原则：视觉浪 = 物理浪。** 波形参数只存在于 `WaveProvider`，GPU（顶点位移、逐像素法线）与 CPU（浮力采样）使用同一公式和同一时钟（`Time.get_ticks_msec()`）。想换 FFT，只需保持 `get_height(x, z, t)` 接口不变。

## 波形数学（GPU/CPU 必须保持一致）

每个波分量：`dir`(方向) `amplitude`(振幅) `steepness`(陡峭度) `wavelength`(波长)

```
k     = 2π / wavelength
omega = sqrt(9.8 · k)              # 深水色散关系
phase = k · dot(dir, xz) − omega · t

disp.y  += amplitude · sin(phase)
disp.xz += steepness · amplitude · dir · cos(phase)
```

约束：`sum(steepness · amplitude · k)` 应远小于 1，否则波峰打卷穿模（当前约 0.10）。

当前海况（4 分量，约 4 级风的中等海况，最大浪高 ~2.2m）：

| dir | amp (m) | steepness | λ (m) |
|-----|---------|-----------|-------|
| (1.0, 0.25) | 1.1 | 0.16 | 60 |
| (0.85, -0.45) | 0.6 | 0.18 | 31 |
| (0.4, 0.9) | 0.32 | 0.20 | 17 |
| (0.95, 0.6) | 0.15 | 0.24 | 9 |

## 船只模型

- 4 个浮力采样点（船首 L/R、船尾 L/R，y=-0.4），每点独立施力 → 自然产生纵摇/横摇
- 单点浮力 = `浸没深度(钳制≤1.2m) · buoyancy_factor · mass`，另加该点速度阻尼
- 重心 = (0, -0.55, 0)（custom center_of_mass），提供复原力矩
- 推进力沿船头方向；舵扭矩 × 航速系数（静止时舵无效，倒车效率减半）
- 龙骨侧向阻力 = `-侧向速度 · keel_grip · mass`

## 调参指南

### 调海况（`wave_provider.gd` → `waves` 数组）

| 想要的效果 | 调什么 |
|-----------|--------|
| 浪更高 | 增大大波长分量的 amplitude（先调 60m 那个） |
| 浪更碎、更凶 | 增大 steepness（注意打卷约束） |
| 浪更密集 | 减小小分量的 wavelength |
| 浪向混乱（风暴感） | 让小分量方向偏离主浪向 30°~60° |

### 调手感（`boat.gd` 顶部 export，编辑器选中 Boat 节点实时改）

| 参数 | 当前值 | 效果 |
|------|--------|------|
| thrust_force | 3800 | 极速 ≈ 推力/水阻，当前约 11 节 |
| rudder_torque | 1800 | 转弯速率（当前约 20°/s） |
| buoyancy_factor | 7.0 | 浮力刚度；太大船"浮在表面发飘"，太小吃水深、反应钝 |
| point_drag | 90 | 浪中稳定性；太小船随浪乱颤 |
| keel_grip | 2.5 | 侧滑程度；太小转弯时像漂移 |
| max_submersion | 1.2 | 单点浮力饱和深度，抗浪穿模能力 |

### 相机（`camera_rig.gd`）

`follow_speed`（位置跟随刚度）、`turn_speed`（转向跟随）、`arm_length`（距离）、回正速率在 `_physics_process` 中的 0.4。

## 已踩过的坑（避免再犯）

1. **自动化验证时注意帧率陷阱**：场景 ~360fps，按"帧数=秒数"推算物理时间会得到错误结论。验证物理行为要用物理 tick 计数或 `--fixed-fps 60`。
2. **白沫远距离锯齿**：`wave_height` 是顶点插值的 varying，远处按 `exp(-dist·0.012)` 淡出（见 shader）。
3. **海面网格跟随相机不会跳变**的前提是位移在世界空间求值，且网格只有平移没有旋转/缩放。
