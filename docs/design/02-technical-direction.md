# 02 · 技术选型分析

> 2026-10-06 记录。项目基线：Godot 4.7 + Forward+ + Jolt 物理 + D3D12。

## 1. 海面波形：Gerstner 原型 → FFT 目标方案

| 方案 | 优点 | 缺点 | 结论 |
|------|------|------|------|
| Gerstner 波叠加 | 简单便宜；CPU 易复算（浮力方便） | 大浪时不真实：出不了碎浪、白花、方向杂乱的风暴海面 | **原型采用**（M1 已验证） |
| FFT（Tessendorf 光谱法） | 直接以风速/浪向/风区为参数，与气象数据天然对接；风暴海况极佳；Jacobian 自动检测浪峰翻卷生成白沫；GPU 上 O(N log N) | 实现复杂；CPU 侧浪高采样（物理用）需要位移图异步回读或低频解析近似 | **目标方案**（M4 迁移） |

**关键架构决策**：波形系统抽象为 `WaveProvider`（当前实现见 `prototype/wave_provider.gd`），CPU 物理与 GPU 渲染共享同一参数源。迁移 FFT 时只替换后端实现，船只与浮力代码不变。

**参考实现**：
- [2Retr0/GodotOceanWaves](https://github.com/2Retr0/GodotOceanWaves) — RenderingDevice compute shader FFT，代码干净，首选学习样本
- [tessarakkt/godot4-oceanfft](https://github.com/tessarakkt/godot4-oceanfft) — FFT + CDLOD + 浮力 + 白沫，功能最全（WIP）

### FFT 迁移时的已知难点（预案）

1. **CPU 浪高采样**：低分辨率位移图（64×64）异步回读 + 双缓冲；或 CPU 端只算最大几个波分量的解析近似。
2. **海面 LOD**：CDLOD / 四叉树，近处高密度网格 + 远处法线贴图。
3. **船尾迹/交互**：需要额外的交互模拟或贴花系统。

## 2. 天气系统：状态机 + 参数驱动

```
天气数据源 → 天气状态(WeatherState) → 插值过渡 → 各子系统参数
    ├─ 海面: 风速/浪向/风区 → 光谱参数
    ├─ 天空: 云量/云类型/太阳角度
    ├─ 光照: 太阳强度/色温/环境光
    ├─ 雾:   能见度/湿度雾
    ├─ 降水: 雨雪粒子 + 海面涟漪
    ├─ 风:   风速/阵风 → 船、粒子、音效
    └─ 雷电: 闪光 + 音效延迟(距离)
```

**海况标尺：蒲福风级（Beaufort Scale）**作为天气 ↔ 海面的标准映射：

| 风级 | 风速 | 浪高 | 海面表现 |
|------|------|------|----------|
| 2-3 | 2-5 m/s | 0.2-0.6m | 微浪，玻璃质感 |
| 5-6 | 8-13 m/s | 2-3m | 白浪花出现 |
| 8-9 | 17-24 m/s | 5-9m | 大浪、飞沫、能见度下降 |
| 11-12 | >28 m/s | >11m | 风暴，空气中充满水雾 |

FFT 光谱直接用风速作输入，此映射几乎免费。Gerstner 阶段则需手工配几套波参数档位。

**真实天气接入（可选模式）**：Open-Meteo API（免费、无需 key、含 marine 浪高数据），按经纬度拉取风速/风向/浪高/云量/降水，小时级数据在游戏内插值平滑。

## 3. 天空与大气

- 大气散射：Nishita 模型物理天空（Godot 内置 PhysicalSky 作底子，精细控制需自定义 shader）
- 体积云候选：
  - [Bonkahe/SunshineClouds](https://github.com/Bonkahe/SunshineClouds) — 生态最成熟，Compositor v2 性能更好（首选）
  - [MMqd/godot-nishita-sky-with-volumetric-clouds](https://github.com/MMqd/godot-nishita-sky-with-volumetric-clouds) — 天空+云一体，含日月星辰月相
- 云量/云底高/云类型由天气状态驱动；暴雨前乌云压顶是氛围关键。

## 4. 船只物理

- Jolt `RigidBody3D` + 多点浮力采样（M1 已验证 4 点方案可行）
- 重心下置（custom center_of_mass）提供复原力矩
- 舵效随航速缩放；龙骨侧向阻力防侧滑
- 后续：横摇与转向耦合、风对上层建筑的侧向力、风浪导致的航速损失

## 5. 语言与技术栈决策记录

| 决策 | 结论 | 理由 |
|------|------|------|
| 原型语言 | GDScript | 迭代快、无需编译；项目虽配了 .NET，但原型阶段 GDScript 足够 |
| 正式版语言 | 待定（倾向 C# 为主） | 天气/数据系统复杂后 C# 更好维护；波形核心可能 GDExtension |
| 波形接口 | `WaveProvider` 抽象 | CPU/GPU 共享参数源，FFT 迁移无痛 |
| 物理引擎 | Jolt（项目默认） | 已验证可用 |
| 目标平台 | PC only（D3D12） | compute shader + 体积云排除移动/Web |

## 6. 性能风险清单

| 风险 | 缓解 |
|------|------|
| FFT 位移图 CPU 回读卡顿 | 异步回读 + 双缓冲 + 低分辨率 |
| 体积云 raymarching 贵 | 半分辨率渲染 + 时间累积（Sunshine v2 已做） |
| 海面透明/折射/SSR 叠加填充率 | 距离淡出特效 + LOD |
| 原型已踩过的坑：白沫在远处因网格插值产生锯齿斑块 | 按距离 `exp(-dist*k)` 淡出（已实施） |
