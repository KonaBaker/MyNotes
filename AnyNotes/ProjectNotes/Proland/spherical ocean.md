# 全球球形海洋系统实现方案

> 参考来源：[Proland 库](https://proland.inrialpes.fr/) — 特别是其 `ocean` 模块中的 projected grid 与 cube sphere 技术。
> 本文档描述现有实现的架构、数学原理、关键代码路径，以及已知问题与改进方向。

---

## 目录

1. [系统概述](#1-系统概述)
2. [整体渲染架构](#2-整体渲染架构)
3. [坐标系设计：Ocean Space](#3-坐标系设计ocean-space)
4. [近场渲染：屏幕空间投影网格](#4-近场渲染屏幕空间投影网格)
   - 4.1 网格生成
   - 4.2 地平线解析计算
   - 4.3 投影光线求交
   - 4.4 位移采样
5. [远场渲染：Cube Sphere 网格](#5-远场渲染cube-sphere-网格)
   - 5.1 Cube-to-Sphere 映射
   - 5.2 网格生成与索引
6. [LOD 切换策略](#6-lod-切换策略)
7. [FFT 波浪集成](#7-fft-波浪集成)
8. [光照模型](#8-光照模型)
9. [渲染管线数据流](#9-渲染管线数据流)
10. [配置参数说明](#10-配置参数说明)
11. [已知问题与改进方向](#11-已知问题与改进方向)

---

## 1. 系统概述

本模块实现了一个行星尺度（半径约 6360 km）的球形海洋表面渲染系统，采用 **双 LOD 策略**：

| LOD 层级 | 技术 | 应用条件 |
|----------|------|----------|
| **近场（Near）** | 屏幕空间投影网格（Screen-Space Projected Grid） | 相机距球面高度 `< max_altitude`（默认 20 km）|
| **远场（Far）** | Cube Sphere 静态网格 | 相机高度 `>= max_altitude` |

两个层级都复用同一套 FFT 波浪位移贴图系统（4 个 cascade），通过不同的顶点着色器将贴图映射到球面几何上。

---

## 2. 整体渲染架构

```
Spherical_Ocean_Pass::update()
    ├── 判断 camera 高度 vs (radius + max_altitude)
    ├── [Near] init(near_pass) → update_near_field()
    │       ├── 构建 Ocean Space 矩阵
    │       ├── 计算地平线参数（horizon_1, horizon_2）
    │       ├── 更新/生成 Screen_Space_Grid
    │       ├── 设置 FFT 采样参数
    │       └── 更新 IBL / LTC / 光源 uniforms
    └── [Far]  init(far_pass) → update_far_field()
            ├── 设置 local_to_world (scale by radius)
            ├── 按需生成 Cube_Sphere mesh
            └── 更新 IBL / LTC / 光源 uniforms

Spherical_Ocean_Pass::render()
    ├── blit.render()  — 将当前 color/depth 拷贝到 blit_color/blit_depth
    │                    供折射计算使用
    ├── setup_blit_color_depth(pass)
    ├── setup_reverse_z(pass)  — 处理 Reverse-Z 深度
    └── near_pass.render() 或 far_pass.render()
```

**Pass 配置文件**（JSON）：
- `/ext-fx-water-system/pass/spherical-ocean-near-pass.json`
- `/ext-fx-water-system/pass/spherical-ocean-far-pass.json`

**Framebuffer 输出**（3个颜色附件 + 深度）：

| 附件 | 内容 |
|------|------|
| `colors[0]` | `out_color` — HDR 颜色 |
| `colors[1]` | `out_normal` — 世界空间法线 |
| `colors[2]` | `out_ibl_specular` — IBL 间接高光（用于 SSR） |
| `depth` | `out_DEPTH` |

---

## 3. 坐标系设计：Ocean Space

Ocean Space 是一个随相机位置更新的局部正交坐标系，其设计目标是：
**将球面上的任意一点映射到一个"局部平面"坐标中**，使 FFT 波浪纹理可以用 2D UV 正常平铺。

### 坐标轴构建（`setup_ocean_space_parameters`）

```
uy = normalize(camera_pos)          // 指向相机正上方（球面法线方向）
ux = normalize(cross(uy, last_uz))  // 利用上一帧的 z 轴，避免奇点
uz = normalize(cross(ux, uy))       // 右手系第三轴
origin = uy * radius                // 锚定在球面上（相机正下方）
```

**world_to_ocean_space**（列主序 glm::dmat4）：

```
         | ux.x  uy.x  uz.x  0 |
W→O  =   | ux.y  uy.y  uz.y  0 |
         | ux.z  uy.z  uz.z  0 |
         | -dot(ux,o) -dot(uy,o) -dot(uz,o) 1 |
```

### 偏移量累积（解决浮点精度问题）

由于相机在行星尺度下移动，world 坐标绝对值极大（~10^6 m），直接用 float 矩阵传给着色器会损失精度。系统维护一个 `offset` 累积量：

```cpp
// 每帧计算 ocean space 原点相对上一帧的位移
auto delta = world_to_ocean_space * (inverse(last_world_to_ocean_space) * vec4(0,0,0,1));
offset += vec3(delta.x, delta.y, delta.z);

// 传给着色器的是"修正后的相机位置"
revised_ocean_camera_pos = vec3(-offset.x, ocean_camera_pos.y, -offset.z)
```

`offset.xz` 是 UV 坐标系下的滑动偏移，用于驱动 FFT 贴图的平铺位置（防止纹理跳变）。`ocean_camera_pos.y` 是相机在 ocean space 中的高度，用于投影求交。

---

## 4. 近场渲染：屏幕空间投影网格

### 4.1 网格生成（`Screen_Space_Grid::Impl::generate`）

在 NDC/屏幕空间中生成一张均匀矩形网格，覆盖 `[-f, f] x [-f, f]`（f=1.25，稍超出屏幕边界防止裂缝）：

```cpp
float f = 1.25;
int NX = int(f * screen_width  / resolution);
int NY = int(f * screen_height / resolution);

// 顶点：Vector2，范围 [-f, f]
vertices[i][j] = vec2(2*f*j/(NX-1) - f,  2*f*i/(NY-1) - f);

// 索引：标准三角形网格
```

网格在 CPU 端只生成一次（屏幕分辨率变化时重新生成），传给 GPU 后在顶点着色器中进行投影。

### 4.2 地平线解析计算（`setup_spherical_ocean_config → setup_horizon`）

**问题**：屏幕空间网格的每个顶点需要沿视线方向射出光线并求交球面，但地平线以上的光线不会与球面相交，需裁剪。

**解法**（来自 Proland）：将地平线约束表达为屏幕 NDC 坐标 `(x, y)` 的解析函数，在顶点着色器中用于 clamp `y` 坐标。

定义：
- `A0`，`dA`，`B` — 将 clip space 方向向量变换到 ocean space 的基向量
- `h` — 相机在 ocean space 中的高度（`ocean_camera_pos.y`）
- `R` — 球半径

**球形海洋地平线方程**（二次型）：

```
horizon(x) = horizon_1.x + horizon_1.y * x
           - sqrt(horizon_2.x + horizon_2.y * x + horizon_2.z * x^2)
```

其中：
```
h1 = h * (h + 2*R)
h2 = (h + R)^2
alpha = dot(B,B)*h1 - B.y^2 * h2

horizon_1 = (-beta0, -beta1, 0)
horizon_2 = (beta0^2 - gamma0,  2*(beta0*beta1 - gamma1),  beta1^2 - gamma2)
```

**平坦海洋退化情况**（`radius == 0`）：
```
horizon(x) = -(h*1e-6 + A0.y) / B.y - (dA.y / B.y) * x
```
（线性函数，即视觉上的"无穷远水平线"）

**奇点处理**（`dot_nadir < -0.9`，即相机正朝下看）：
直接设置 `horizon_1 = (1000, 0, 0)`，`horizon_2 = 0`，使地平线推到无穷远，全屏填满海面。

### 4.3 投影光线求交（`spherical-near-vert.glsl: get_ocean_pos`）

```glsl
// 1. 计算地平线，clamp 顶点 y 坐标
double horizon = horizon_1.x + horizon_1.y * x
               - sqrt(horizon_2.x + (horizon_2.y + horizon_2.z*x)*x);
camera_dir = normalize(clip_to_view * vec4(x, min(y, horizon), ndc_z, 1)).xyz;

// 2. 变换到 ocean space
ocean_dir = (view_to_ocean_space * vec4(camera_dir, 0)).xyz;

// 3. 在 ocean space 中求光线与球面交点（二次方程）
//    球方程：(pos.y + R)^2 + pos.xz^2 = R^2  =>  cy*(cy + 2R) = c
float cy = revised_ocean_camera_pos.y;
float dy = ocean_dir.y;
float b = dy * (cy + R);
float c = cy * (cy + 2*R);
float tSphere = -b - sqrt(max(b*b - c, 0));

// 4. 近似解（稳定性优化）
//    当 b^2 趋近 c 时（光线近乎平行球面），球面公式数值不稳定，改用泰勒近似
float tApprox = -cy/dy * (1 + cy/(2R) * (1 - dy*dy));
t = abs((tApprox - tSphere)*dy) < 1.0 ? tApprox : tSphere;

// 5. 输出 ocean space 2D 坐标（用于 FFT 采样）
ocean_pos_uv = revised_ocean_camera_pos.xz + t * ocean_dir.xz;
```

### 4.4 位移采样与最终位置

```glsl
// 各向异性梯度采样（抗锯齿）
vec2 dpdx = get_ocean_pos(vertex + vec3(grid_size.x, 0, 0)) - ocean_pos_uv;
vec2 dpdy = get_ocean_pos(vertex + vec3(0, grid_size.y, 0)) - ocean_pos_uv;
vec3 disp = sample_displacement_spherical(ocean_pos_uv, dpdx, dpdy);

// 最终 clip 位置：沿视线偏移 t，再叠加位移（在 ocean space -> view space 转换后）
gl_Position = view_to_clip_space * vec4(
    t * camera_dir + vec3(ocean_to_view_space * vec4(disp, 0)),
    1.0
);
```

---

## 5. 远场渲染：Cube Sphere 网格

### 5.1 Cube-to-Sphere 映射（`cube_to_sphere`）

使用球化立方体（Spherified Cube）映射，相比简单归一化，此方法在球面上产生更均匀的顶点分布：

```
x = cx * sqrt(1 - cy^2/2 - cz^2/2 + cy^2*cz^2/3)
y = cy * sqrt(1 - cx^2/2 - cz^2/2 + cx^2*cz^2/3)
z = cz * sqrt(1 - cx^2/2 - cy^2/2 + cx^2*cy^2/3)
```

其中 `(cx, cy, cz)` 是立方体表面上的点（各分量 ∈ [-1, 1]）。

参考：https://catlikecoding.com/unity/tutorials/procedural-meshes/cube-sphere/

### 5.2 网格生成（`Cube_Sphere::Impl::generate`）

6 个面，每面独立生成顶点 + 索引，顶点偏移量 `vertex_offset` 用于正确索引：

```
面定义（origin + u_dir * u + v_dir * v，u,v ∈ [0,1]）：
  Back   : (-1,-1,-1), (2,0,0),  (0,2,0)
  Front  : ( 1,-1, 1), (-2,0,0), (0,2,0)
  Left   : (-1,-1, 1), (0,0,-2), (0,2,0)
  Right  : ( 1,-1,-1), (0,0, 2), (0,2,0)
  Bottom : (-1,-1,-1), (2,0,0),  (0,0,2)
  Top    : (-1, 1, 1), (2,0,0),  (0,0,-2)
```

每面顶点数：`(resolution+1)^2`，三角形：`2 * resolution^2`，默认 resolution=256。

**远场顶点着色器**（`spherical-far-vert.glsl`）：

```glsl
// vertex_position 是 [-1,1] 的球面单位向量
vec4 world_pos4 = local_to_world_space * vec4(vertex_position, 1.0);
// local_to_world_space = scale(radius)，将单位球放大到实际海洋半径

world_normal = normalize(vertex_position);
gl_Position = view_to_clip_space * world_to_view_space * world_pos4;
```

远场不使用 FFT 位移（顶点数虽多但距离远，位移不可见），仅做表面着色。

---

## 6. LOD 切换策略

```cpp
// spherical-ocean-pass.cpp: update()
if (length(camera_pos) > config.radius + config.max_altitude) {
    // 切换到 Far 模式，同时重置 ocean space 偏移量
    last_world_to_ocean_space = dmat4{1.0};
    offset = dvec3{0.0};
    render_mode = Render_Mode::Far;
} else {
    render_mode = Render_Mode::Near;
}
```

切换时重置 `offset` 的原因：
Far 模式下相机在太空中，ocean space 的连续性不再重要；
回到 Near 时从零重新建立偏移量，避免历史偏移量污染。

**当前限制**：两个模式之间没有过渡混合（Blend mode 已定义但未实现）。在 `max_altitude` 附近切换时存在突变。

---

## 7. FFT 波浪集成

### 波浪级联（Cascades）

系统使用 4 个级联，以固定尺度覆盖不同频率范围：

| Cascade | 网格尺寸（`GRID_SIZE`） | 覆盖范围 |
|---------|------------------------|----------|
| 0 | 5488 m | 大浪（涌浪） |
| 1 | 392 m  | 中浪 |
| 2 | 28 m   | 小浪 |
| 3 | 2 m    | 毛细波 |

（注：普通海洋的级联使用 `length_scale` uniform 动态控制，球形海洋使用硬编码常量 `GRID1_SIZE` 等，两者是独立的采样路径。）

### 球形海洋专用采样函数（`fft-wave.glsl`）

```glsl
// 位移：使用 textureGrad 做各向异性采样
vec3 sample_displacement_spherical(vec2 ocean_pos_uv, vec2 dpdx, vec2 dpdy) {
    res += textureGrad(displacement, vec3(ocean_pos_uv/GRID1_SIZE, 0), dpdx, dpdy).xyz;
    res += textureGrad(displacement, vec3(ocean_pos_uv/GRID2_SIZE, 1), dpdx, dpdy).xyz;
    res += textureGrad(displacement, vec3(ocean_pos_uv/GRID3_SIZE, 2), dpdx, dpdy).xyz;
    res += textureGrad(displacement, vec3(ocean_pos_uv/GRID4_SIZE, 3), dpdx, dpdy).xyz;
}

// 导数（用于法线计算）：使用 mipmapped texture
vec4 sample_derivatives_spherical(vec2 ocean_pos_uv) {
    res += texture(derivative, vec3(ocean_pos_uv/GRID1_SIZE, 0));
    // ... 4 个 cascade 叠加
}
```

### 法线计算（`spherical-near-frag.glsl`）

球面上的法线需要额外减去球面曲率引起的倾斜：

```glsl
vec3 get_normal_spherical() {
    vec4 derivatives = sample_derivatives_spherical(ocean_pos_uv);
    vec2 slope = vec2(
        derivatives.x / max(0.001, 1 + derivatives.z),
        derivatives.y / max(0.001, 1 + derivatives.w)
    );
    // 修正球面曲率：减去当前位置相对于球心的切向分量
    slope -= ocean_pos.xz / (radius + ocean_pos.y);
    return normalize(vec3(-slope.x, 1.0, -slope.y));
}
```

**导数贴图 Mipmap**：在 `setup_fft_config()` 中每帧重新生成 derivative 贴图的 mipmap，以支持 LOD 采样：
```cpp
rr.generate_mipmaps(*io.in_derivative);
```

---

## 8. 光照模型

两个 pass（近场/远场）共用同一套着色逻辑（`shading.glsl`），基于 PBR：

### PBR BSDF（`evaluate_BSDF_for_pbr`）

| 组件 | 实现 |
|------|------|
| 法线分布 | GGX（`distribution_GGX`） |
| 可见性 | Smith GGX 近似（`visibility_Smith_GGX_correlated_approx`） |
| 菲涅尔 | Schlick（`Fresnel_Schlick`） |
| 次表面散射 | **球形海洋禁用**（`vec3 sss = vec3(0.0f)`） |

### 表面参数

```glsl
shading_data.roughness = mix(material_data.distant_roughness,
                             material_data.roughness,
                             1.0 / (1.0 + roughness_scale * dist_to_camera));
// 距离越远 roughness 越高（模拟 mean slope variance）

shading_data.diffuse_color = scattering_color(view_dir);
// 基于视线仰角的散射颜色插值（水深感）
```

### 间接光照

- **IBL 漫反射**：`IBL_diffuse_irradiance(normal)`
- **IBL 镜面反射**：`IBL_spec_radiance(reflection_dir, roughness)` × Fresnel 项
- **SSR 支持**：当 `reflection_mode == SCREEN_SPACE_REFLECTION` 时，将反射结果写入 `indirect_specular` 输出，由后续 SSR 合并 pass 处理

### 远场附加参数

```cpp
far_pass.set_uniform("mean_slope_variance", 0.05f);
```
用于远距离粗糙度偏移，控制广角下的高光形状。

---

## 9. 渲染管线数据流

```
[上游 pass]
    in_color, in_DEPTH       ─────────────────────────────────────────
    in_normal                                                          │
    in_displacement (FFT)                                             │
    in_derivative   (FFT)                                             │
    in_ibl_specular                                                   │
    in_pipeline_camera_data                                           │
    in_ibl_data, in_ltc_data                                         │
    in_common_light_cache                                             │
    in_top_view_depth                                                 │
                                                                      ▼
                                                  Blit Pass (拷贝 in_color / in_DEPTH)
                                                      │
                                                      ▼
                                          blit_color, blit_depth
                                         （传入着色器做折射背景）
                                                      │
                                          ┌───────────┴───────────┐
                                          │                       │
                                     near_pass               far_pass
                                  (Screen-Space Grid)     (Cube Sphere)
                                          │                       │
                                          └───────────┬───────────┘
                                                      ▼
                                    out_color, out_DEPTH, out_normal, out_ibl_specular
```

---

## 10. 配置参数说明

### `Spherical_Ocean_Config`（场景 Trait，挂载在 ocean 节点上）

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `radius` | `double` | 6,360,000 m | 行星海洋半径 |
| `max_altitude` | `double` | 20,000 m | 近/远 LOD 切换高度阈值 |
| `screen_space_config.resolution` | `int` | 8 | 屏幕空间网格分辨率（像素/格） |
| `cube_sphere_config.resolution` | `int` | 256 | Cube Sphere 每面细分数 |

### 关键 Uniforms（运行时）

| Uniform | 来源 | 说明 |
|---------|------|------|
| `revised_ocean_camera_pos` | C++ 每帧计算 | 浮点精度修正后的相机位置 |
| `horizon_1_in`, `horizon_2_in` | C++ 每帧计算 | 地平线二次曲线参数 |
| `view_to_ocean_space` | C++ 每帧计算 | view → ocean 空间变换 |
| `ocean_to_view_space` | C++ 每帧计算 | ocean → view 空间变换 |
| `radius` | 来自 config | 球面半径（着色器中用于法线曲率修正） |
| `grid_size` | 屏幕分辨率 / resolution | 相邻顶点间的 NDC 步长（用于梯度估计）|
| `time` | 帧时间 | FFT 时间驱动 |

---

## 11. 已知问题与改进方向

### 11.1 近/远切换无过渡（已知缺陷）

`Render_Mode::Blend` 已定义但未实现。在 `max_altitude` 边界附近，两种渲染模式之间会有突变：
- 近场的屏幕空间网格有波浪位移
- 远场的 Cube Sphere 是静态的（无位移）

**建议**：在切换高度附近实现一个过渡区，对远场 cube sphere 也采样 FFT 位移（低 mip 即可），并在混合阶段根据高度插值。

### 11.2 远场无 FFT 位移

当前远场 `spherical-far-vert.glsl` 不采样 FFT 位移贴图，导致从高空俯瞰时海面完全静止。
对于低轨道相机（20~100 km）观察到的波浪效果不真实。

**建议**：在远场顶点着色器中加入低 cascade（仅 cascade 0，大浪）的位移采样，使用 `textureGrad` 或 `textureLod`。

### 11.3 FFT 级联尺寸硬编码

球形海洋的 `GRID1_SIZE` 等为编译期常量（5488, 392, 28, 2 m），无法在运行时调整。
而普通海洋使用 `length_scale` uniform 动态控制，两者不统一。

**建议**：将球形海洋级联尺寸也改为 uniform，从 `Wave_Config` trait 读取，与普通海洋共用同一套配置路径。

### 11.4 偏移量浮点精度

`offset` 使用 `dvec3`（双精度）累加，但最终传给着色器时截断为 `vec3`（单精度）：
```cpp
near_pass.set_uniform("revised_ocean_camera_pos",
    glm::vec3(-offset.x, ocean_camera_pos.y, -offset.z));
```
在长时间运行后，`offset` 绝对值可能变大，截断误差也随之增大，导致纹理抖动。

**建议**：定期将 `offset` 对级联尺寸取模（`fmod(offset, GRID1_SIZE)`），保持其绝对值在可控范围内。

### 11.5 次表面散射在球形海洋中被禁用

`shading.glsl` 中明确将球形海洋的 SSS 置为 `vec3(0)`（缺乏波浪高度偏移量作为输入）。近场实际上有 `ocean_pos.y` 可用，可以基于此估算波峰/波谷深度差，重新启用 SSS。

### 11.6 折射处理

当前近/远两个 pass 都接收 `blit_scene_color` / `blit_scene_depth` 用于折射，但远场（太空视角）实际上几乎不需要折射效果。`surface-lighting.glsl` 中的 `apply_refraction_color` 函数目前在球形海洋着色器中**未被调用**（球形海洋 frag shader 没有调用折射）。

### 11.7 Screen Space Grid 重生成条件

当前仅在屏幕分辨率变化时重新生成 SSG（即 `screen_width/height` 改变），但 `resolution` 配置变化（用户在编辑器中修改）不会触发重生成（`is_empty()` 只检查 vertices 是否为空）。

**建议**：缓存上次使用的 `resolution` 值，变化时触发重生成。

---

*文档版本：2026-04-24，基于 `feature/river` 分支当前代码状态生成。*