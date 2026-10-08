# AGENTS.md

## 环境

- Godot 编辑器/运行时：`E:\codes\game\gd\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe`
  （同目录另有非 console 版与 GodotSharp；无头验证用 console 版加 `--headless`）
- 项目为 Godot 4.7（mono 版运行时，但原型代码为 GDScript）

## 常用命令

- 无头运行验证（检查脚本/shader 报错）：
  `"E:\codes\game\gd\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --headless --path . --quit-after 300`
- 编辑器运行：去掉 `--headless --quit-after` 即可

## 项目结构

- `prototype/`：原型（海面 Gerstner 波 shader、船只浮力物理、跟随相机、天气状态机）
  - `wave_provider.gd`：波形参数唯一数据源（蒲福连续插值 + 涌浪通道 `set_swell()`）
  - `weather.gd`：天气状态机（蒲福风级映射 + 自动演变 + 手动锁定 + 涌浪预警→风暴跟随）
  - `day_night.gd`：昼夜循环（唯一时间数据源，太阳/月亮方位与日照因子；[/] 键 ±0.5h）
  - `ambience.gd`：程序合成环境音（布朗噪声风声分级 + 白噪声雨声，水下闷化）
  - `sky.gdshader`：天气联动天空（天色/云量/太阳随 `provider.current_intensity()` 变化；昼夜由 `day_factor`/`dusk`/`moon_direction` 调制，含星空与月亮；`underwater` uniform 负责水下背景；云与闪电光柱用 Simplex 噪声纹理 + `flash_seed` 驱动）
  - `dive_camera.gd`：自由潜水相机（C 键切换，WASD+Space/Ctrl+Shift）
  - `terrain.gd`：海床区块 + 地形/生态区函数（`get_height`/`get_biome` 是唯一数据源，固定 seed 确定性）
  - `seabed.gdshader`：海床着色（生态区混色 + 焦散）
  - `fish_manager.gd` / `fish_school.gd`：观赏鱼群（MultiMesh + 锚点伪群游，生态区配置表在 CONFIGS；摆尾动画在 `fish.gdshader` 顶点阶段，INSTANCE_CUSTOM 携带相位/频率）
  - `god_rays.gd` / `god_rays.gdshader`：水下体积光柱（圆柱广告牌 MultiMesh，强度由 main.gd 按水下×日照×清澈度驱动）
  - `rain.gd`：雨幕粒子（weather.precip 驱动）；`lightning.gd`：雷电（天空闪光 + 合成雷声）
- 新脚本添加 `class_name` 后需同步注册到 `.godot/global_script_class_cache.cfg`（编辑器会自动做，手写脚本时手动补），否则无头运行报 "Identifier not declared"
- C# 代码（`prototype/fft/`）：改完用 `dotnet build ocean.csproj` 重建（`--build-solutions` 会挂起，别用）；C# 全局类同样要在上面的缓存注册（language 为 `C#`）；`project.godot` 的 features 需含 `C#`
- 无头退出时偶发 `AudioStreamGeneratorPlayback` 泄漏警告（引擎音频服务器清理竞态，已在 `_exit_tree` 里 stop+释放引用缓解）：良性，不影响运行
- 截图测试脚本（`_shot_test.gd` 等）会弹出真实游戏窗口渲染，**运行期间不要关闭窗口或按键**，否则进程提前退出/状态被污染
- `docs/PROGRESS.md`：开发进度与里程碑，完成改动后需同步更新
- `docs/design/`：设计文档

## 关键约定

- `WaveProvider`（`prototype/wave_provider.gd`）是波形参数唯一数据源，CPU 物理与 GPU 渲染共享；改海况只改其中 `WIND_TABLE` 蔢福关键帧表（2~11.5 级连续插值）
- 只有前 `displace_count` 个大波参与顶点位移与浮力计算（小波走 shader 逐像素法线，避免网格采样混叠）；CPU `get_height()` 与 shader `gerstner()` 必须保持一致
- `ocean.gdshader` 走透明通道渲染（读深度/屏幕纹理做浅滩折射的前提）；新增透明物体注意 render_priority 排序（水面=-1 先画）
