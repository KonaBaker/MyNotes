# 全球球形海洋与地形系统整合方案

> 本文档覆盖三个层面：
> 1. **Proland 球形地形实现原理**（参考背景）
> 2. **现有引擎地形（Geometry Clipmap + 旋转伪全球）的工作机制分析**
> 3. **海洋与地形整合的具体实现方案**

---

## 1. Proland 球形地形原理

Proland 的地形模块（`terrain` + `edit/proland` 模块）是理解整合思路的基础背景。

### 1.1 核心概念：Spherical Deformation

Proland 中地形并不直接构建在球面上，而是采用一种**延迟变形**策略：

```
平面四叉树 Tile 网格  →  Deformation 变换  →  球面（或其他曲面）
```

`TerrainNode` 持有一个 `Deformation` 对象，该对象的 `setUniforms()` 负责向着色器传入把平面坐标弯曲到球面的矩阵/参数。`SphericalDeformation` 是其球面实现，将 `(u, v)` 坐标通过立方体投影映射到单位球面上，再乘以行星半径 `R`。

### 1.2 四叉树 Tile 分级（Quadtree LOD）

```
根 Tile（对应立方体一个面，~10000 km）
    └── 4 个子 Tile（~5000 km）
            └── ...
                    └── 叶 Tile（~几十米，高精度 DEM）
```

每个 Tile 持有：
- **高程纹理（Elevation Texture）**：R16 格式，存储球面半径的相对偏移量
- **法线纹理（Normal Texture）**：由高程推导
- **正射纹理（Ortho Texture）**：卫星图 / GIS 数据

Tile 按相机与节点的**投影立体角（Projected Solid Angle）** 决定是否细分，类似 Geometry Clipmap 但基于四叉树而非同心环。

### 1.3 顶点着色器变形

```glsl
// Proland 风格的球面地形顶点着色器核心
vec3 deformedVertex(vec2 uv, float elev) {
    // 1. 平面 tile 上的点
    vec3 localP = vec3(uv * tileSize, 0.0);
    // 2. 应用 SphericalDeformation → 映射到球面
    vec3 sphereP = normalize(cube_to_sphere(origin + localP)) * (R + elev);
    return sphereP;
}
```

`SphericalDeformation` 内部使用与我们 `cube_to_sphere()` 相同的数学，即基于三维立方体面坐标投影到球面的等角映射。

### 1.4 Proland 地形与海洋的交互点

Proland 的 `ocean` 模块中，`OceanFFT` 依赖 `TerrainNode` 提供**海底高程**：

```
TerrainNode::getTerrainQuadAtCamera()
    → 获取当前相机正下方的 Tile
    → 读取其高程值 → 判断是否在水面以下
    → 如在水下 → 渲染海洋，并从高程纹理读取海床深度
```

海洋着色器通过一张**全局地形深度贴图**（由地形从顶部正交相机渲染得到）确定哪里是陆地、哪里是海底。这正是我们引擎中 `Top_View_Pass` 的等价物。

---

## 2. 引擎现有地形系统分析

### 2.1 Geometry Clipmap 结构

地形使用 `Clipmap_Terrain_Mesh_Service` 管理，`Grand_Terrain_Object` 是每块地形的数据容器，包含：

| 数据 | 类型 | 说明 |
|------|------|------|
| `height_map` | R16 纹理 | 高程图，`max_height` 控制垂直缩放 |
| `normal_map` | RG16 纹理 | 法线，由高程计算得到 |
| `terrain_size` | `Vector2` | 地形水平覆盖范围 |
| `lod_chunk_resolution` | `int` | 每个 LOD chunk 的顶点数 |
| `lod_level` | `int` | LOD 层级数，默认 7 |

Clipmap 网格由 5 种 mesh 类型组成（`tile`、`filler`、`trim`、`cross`、`seam`），拼接成同心 LOD 环。

### 2.2 "旋转伪全球"机制

地形本身是一个**局部平面 heightfield**，但通过将 `local_to_world` 变换矩阵中加入一个**绕水平轴的旋转**，使网格随相机位置在球面上"跟随旋转"：

```
Grand_Terrain_Object::get_rotate_transformation()
    → 根据相机在球面上的位置计算旋转矩阵
    → 将平面地形"贴"到球面相机正下方
```

这是一个近似方法：在相机附近（数十公里内），曲率误差小到肉眼不可见；但随距离增大，地形边界明显"翘起"，不能覆盖全球。

**关键约束**：这个旋转会随相机移动更新，因此地形始终以相机为中心，世界坐标系下地形的绝对位置是动态的。

### 2.3 Top_View_Pass（已有的海洋-地形接口）

当 `SS_EXT_WATER_SYSTEM_USE_GRAND_TERRAIN == 1` 时，`Top_View_Pass` 从地形正上方以正交相机渲染地形深度图：

```cpp
// top-view-pass.cpp
top_camera_pos = {camera_pos.x, top_camera_extra_depth + ocean_height, camera_pos.z};
// 以 (camera.x, very_high_y, camera.z) 为相机位置，向下看
// 输出 1024×1024 深度图 → out_top_view_depth
```

此深度图在普通海洋（`ocean-pass`）着色器中通过 `terrain_height.glsl` 使用，用于：
- 遮挡水下地形（深度测试）
- 计算水深（用于散射颜色、泡沫等近岸效果）

**目前球形海洋 pass 尚未使用 `in_top_view_depth`**（接口已声明但未接入）。

---

## 3. 两个系统的坐标对齐分析

这是整合的核心难点。两个系统使用不同的坐标约定：

| 系统 | 坐标约定 | 说明 |
|------|----------|------|
| 地形（Clipmap） | 世界坐标（绝对） | 地形有世界空间 AABB，高程 Y 轴向上 |
| 球形海洋（近场） | Ocean Space（随相机更新的局部坐标） | `uy` 指向相机正上方（球面法线） |
| 球形海洋（远场） | 世界坐标（球心在原点） | Cube Sphere 以 `radius` 为半径 |

### 3.1 当前为何近场"无违和感"

在相机高度很低（<< `max_altitude`）、离地面很近时：
- 球面曲率引起的 `uy` 偏转极小（相机在球面上的偏转角 ≈ `height / R` ≈ `100 / 6,360,000` ≈ 0.001°）
- Ocean Space 的 XZ 平面与地形的 XZ 平面几乎完全重合
- 地形的旋转角度也极小

两者在局部看起来就是同一个"水平面 + 竖直方向"，因此近景无缝。

### 3.2 需要解决的中远距离问题

当相机拉到 5~20 km 高度时：
- 球面曲率开始可见（地平线弯曲）
- 地形旋转偏转变为可感知（~0.05°~0.3°）
- 若海洋与地形没有统一的"球面高度"参考，会出现：
  - 陆地露出水面或被水淹
  - 海岸线位置不匹配
  - 深度遮挡错误（地形穿透海面 或 海面遮住山峰）

---

## 4. 整合目标与挑战

### 4.1 整合目标

| 目标 | 优先级 | 说明 |
|------|--------|------|
| 地形正确遮挡海面（陆地不被水覆盖） | 高 | 深度写入正确对齐 |
| 浅水区视觉效果（折射、深度散射） | 高 | 需要海底地形深度 |
| 海岸线过渡（泡沫、波浪衰减） | 中 | 依赖 top_view_depth |
| 远场 GIS 高程驱动海洋边界 | 中 | 全球哪里是海，哪里是陆 |
| 太空视角下地形与海洋的球形一致性 | 低 | 远场 Cube Sphere 无地形细节 |

### 4.2 核心挑战

**挑战 A：高程参考面不一致**
地形高程以某个"海平面 Y = ocean_height"为基准（世界坐标绝对高度），而球形海洋的"海平面"是半径为 `radius` 的球面。需要建立映射关系：
```
terrain_world_y  ←→  sphere_radial_height = |world_pos| - radius
```

**挑战 B：Top_View_Pass 坐标在球形海洋中的适用性**
现有 top_view_pass 使用垂直正交相机（`look_down`），在平坦地形中有效。球形海洋的 ocean space 中，"向下"是径向方向（`-uy`），而非世界坐标 `-Y`。在低海拔时差异极小，但在高海拔或极地方向差异明显。

**挑战 C：地形旋转与海洋 offset 的漂移**
地形的 `get_rotate_transformation()` 每帧更新，海洋的 `offset` 也每帧累积。当两者参考的"原点"不一致时，海岸线会随相机运动漂移。

---

## 5. 整合方案：海水遮挡与深度

### 5.1 接入现有 Top_View_Pass 深度图

**这是最小改动、收益最大的整合路径。**

球形海洋近场 Pass（`spherical-ocean-near-pass`）的 `Spherical_Ocean_Pass` 已声明了 `in_top_view_depth` 接口，但尚未使用。接入步骤：

**Step 1**：在 `Spherical_Ocean_Pass::Impl::update_near_field()` 末尾，将 `in_top_view_depth` 传给着色器：

```cpp
// 在 update_near_field() 末尾
#if SS_EXT_WATER_SYSTEM_USE_GRAND_TERRAIN == 1
    util::set_uniform_and_sampler(
        near_pass, io.in_top_view_depth,
        "water_depth_map",
        resource::Sampler::Wrap::clamp_to_edge,
        resource::Sampler::Filter::nearest
    );
    // top_view 正交相机参数（从 top_view_pass 共享）
    near_pass.set_uniform("top_camera_extra_depth",  top_camera_extra_depth);
    near_pass.set_uniform("one_over_top_camera_region", 1.0f / top_camera_region);
    near_pass.set_uniform("top_camera_pos_xz",
        glm::vec2(camera_pos.x, camera_pos.z));
#endif
```

**Step 2**：在 `spherical-near-frag.glsl` 中包含 `terrain-height.glsl` 并使用：

```glsl
#if SS_EXT_WATER_SYSTEM_USE_GRAND_TERRAIN == 1
    #include "../../collision/terrain-height.glsl"
    uniform vec2 top_camera_pos_xz;
#endif

void main() {
    // ... 现有代码 ...

    #if SS_EXT_WATER_SYSTEM_USE_GRAND_TERRAIN == 1
        // 从 top_view 深度图读取地形高度
        float terrain_y = terrain_depth(world_ocean_pos.xz, top_camera_pos_xz);
        // 如果当前像素的海底高于海面，说明这里是陆地，直接 discard
        // 或者利用高度差计算水深
        float water_depth = ocean_pos.y - terrain_y;  // ocean_pos.y ≈ 0 在海面
        // water_depth > 0：海水中；water_depth <= 0：陆地
        if (water_depth <= 0.0) discard;
    #endif
}
```

> **注意**：`terrain_depth()` 函数返回的是地形相对于海平面 Y 的高度（以 `top_camera_extra_depth` 为参考），与 `ocean_pos.y`（相机高于海面的距离）在同一参考系下。

### 5.2 水深效果（折射颜色、浑浊度）

利用水深计算散射颜色（近岸浅水变绿/浑浊，深水变深蓝）：

```glsl
// spherical-near-frag.glsl
#if SS_EXT_WATER_SYSTEM_USE_GRAND_TERRAIN == 1
    float depth_for_scatter = max(water_depth, 0.0);
    // 重写散射颜色，融入水深信息
    vec3 shallow_color = material_data.shallow_diffuse_color;
    vec3 deep_color = material_data.diffuse_color;
    float depth_blend = 1.0 - exp(-depth_for_scatter * 0.1); // 调整 0.1 系数
    shading_data.diffuse_color = mix(shallow_color, deep_color, depth_blend);
#endif
```

### 5.3 深度遮挡的正确写法（地形 depth buffer 与海洋 depth buffer 的合并）

当前渲染顺序（已有 blit 机制）：
```
地形 pass (写入 out_DEPTH)
    → blit_pass (拷贝 depth 到 blit_depth)
    → 球形海洋 near_pass (读取 blit_depth 用于折射)
```

球形海洋近场使用了**屏幕空间投影网格**，每个顶点直接计算 `gl_Position`，深度由顶点着色器的投影结果决定。地形的深度已经在 `blit_depth` 中。

关键验证点：
- 球形海洋的 `depth_stencil_state.depth_func` 已根据 Reverse-Z 正确设置（`greater` 或 `less`）
- 地形渲染在球形海洋之前执行，深度缓冲中已有地形数据
- 海洋投影网格的顶点深度应与地形深度正确比较（同一 clip space）

若出现 Z-fighting（地形和海面交错闪烁），检查：
- 海平面 `ocean_height`（世界坐标 Y）与球面 `radius` 的对应关系
- 确保地形 Y=0 对应球半径 `radius`（即地形坐标原点在球面上）

---

## 6. 整合方案：海岸线与浅水效果

### 6.1 现有基础（已在普通 Ocean Pass 中实现）

普通 `ocean-pass` 通过 `top_view_depth` + `terrain-height.glsl` 实现：
- 泡沫（Foam）：在水深 < 阈值时增加 foam 强度
- 波浪衰减（Wave Attenuation）：在 `manifest-shoreline-wave-attenuation.txt` 中（可选编译）

### 6.2 球形海洋的海岸线扩展

在 `spherical-near-frag.glsl` 中追加：

```glsl
#if SS_EXT_WATER_SYSTEM_USE_GRAND_TERRAIN == 1
    // --- 岸边泡沫 ---
    float shore_foam = smoothstep(2.0, 0.0, water_depth);   // 2m 以内开始出现泡沫
    shading_data.foam_diffuse = vec3(shore_foam);

    // --- 折射强度随水深衰减（浅水折射弱，避免穿帮） ---
    float refract_scale = smoothstep(0.0, 3.0, water_depth);
    // 将 refract_scale 乘入 refraction_distortion_strength
    // （需要将 material_data.refraction_distortion_strength 改为变量）
#endif
```

### 6.3 Top_View_Pass 适配球形坐标（中优先级改进）

现有 top_view_pass 使用世界坐标 XZ 平面的正交相机（固定向下 `(0,-1,0)`）。对于球形海洋的低海拔情况，这是足够的（误差 < 0.01°）。

若需要支持更高海拔或极地区域，需要改进：

```cpp
// top-view-pass.cpp: 将相机方向改为球面径向方向
glm::dvec3 camera_world = { camera_pos.x, camera_pos.y, camera_pos.z };
glm::dvec3 radial_down = -glm::normalize(camera_world); // 球面向下
glm::dvec3 up_hint = glm::abs(radial_down.y) < 0.9 ?
    glm::dvec3(0,1,0) : glm::dvec3(1,0,0);
glm::dvec3 radial_right = glm::normalize(glm::cross(radial_down, up_hint));
// 以此构建正交相机的 view 矩阵
```

但这会改变深度图的解读方式（`terrain_depth()` 中的 UV 映射需对应更新），**建议留到近场海岸线效果稳定后再处理**。

---

## 7. 整合方案：GIS 高程数据驱动球形海洋

### 7.1 目标

从真实地球高程数据（如 SRTM / ETOPO）中读取：
- **陆地**（elevation > 0）→ 不渲染海洋，渲染地形
- **海洋**（elevation <= 0）→ 渲染球形海洋，海底高程用于水深计算

### 7.2 全球水陆掩码纹理

构建一张**球面 Cube Map 水陆掩码**（6 面，每面 512×512 或更高分辨率），存储每个球面点的：
- R 通道：`1.0` = 海洋，`0.0` = 陆地
- G 通道：归一化海底高程（`-depth / max_ocean_depth`）

```glsl
// spherical-near-vert.glsl 中采样水陆掩码
uniform samplerCube ocean_mask_cube;

// world_ocean_pos 是球面上的点
vec3 sample_dir = normalize(world_ocean_pos); // 转为立方体采样方向
vec2 mask_data = texture(ocean_mask_cube, sample_dir).rg;
float is_ocean = mask_data.r;
float seafloor_depth = mask_data.g * max_ocean_depth;

if (is_ocean < 0.5) discard; // 陆地区域丢弃该顶点
```

### 7.3 GIS 数据导入管线

```
SRTM/ETOPO NetCDF 或 GeoTIFF
    → 离线工具：采样到 Cube Map 6 面
    → 存为 6 张 PNG 或 1 张 KTX2 Cubemap
    → 引擎资产管理系统导入
    → 作为 Spherical_Ocean_Config 的一个字段：
        resource::Texture* ocean_mask_cubemap
```

在 `Spherical_Ocean_Config` 中新增：

```cpp
CCTT_INTROSPECT(.serde_optional true)
std::string ocean_mask_cubemap_path;   // 水陆掩码 cubemap 资产路径

CCTT_INTROSPECT(.serde_optional true)
float max_ocean_depth{11000.0f};        // 最大海深（马里亚纳海沟约 11 km）
```

### 7.4 海底地形的波浪衰减

在浅水区（`seafloor_depth < 30m`），波浪会因海底摩擦而衰减：

```glsl
// 在 sample_displacement_spherical 之后
float shoaling_factor = smoothstep(0.0, 30.0, seafloor_depth);
disp *= shoaling_factor;
```

---

## 8. 整合方案：远场过渡（海洋 + 太空视角地形）

### 8.1 现状

- 远场（相机高度 > `max_altitude`）：Cube Sphere 海洋，无地形
- `max_altitude` = 20 km，这个高度下地形已不可见（超过 Clipmap 范围）

所以**远场不需要地形几何整合**，但需要：
1. 从 GIS 掩码正确区分陆地/海洋区域（见第 7 节）
2. 保证远场 Cube Sphere 在陆地区域不渲染

### 8.2 远场水陆掩码

在 `spherical-far-frag.glsl` 中：

```glsl
#ifdef HAS_OCEAN_MASK
    uniform samplerCube ocean_mask_cube;
    // world_pos 已在顶点着色器中传出
    float is_ocean = texture(ocean_mask_cube, normalize(world_pos)).r;
    if (is_ocean < 0.5) discard;
#endif
```

远场着色器已有 `world_pos` 输出（`spherical-far-vert.glsl` 第 13 行），可以直接用于 Cube Map 采样。

### 8.3 近/远场切换时的海岸线连续性

- 近场：Ocean Space 网格 + 地形深度遮挡 → 海岸线由地形决定
- 远场：Cube Sphere + GIS 掩码 → 海岸线由低分辨率掩码决定

两者在 `max_altitude = 20km` 附近的过渡中，海岸线分辨率会有突变。缓解方法：
- 在 15~20 km 高度范围内，对掩码进行模糊处理（增大 `smoothstep` 过渡范围）
- 或者在中间高度同时渲染两个 Pass，进行 alpha 混合（即实现已定义的 `Render_Mode::Blend`）

---

## 9. 渲染管线调整

### 9.1 建议的 Pass 执行顺序

```
[地形 Pass]
    → 写入 out_color, out_DEPTH (含地形)
    → 写入 out_gbuffer (法线等)
[Top_View_Pass]
    → 使用正交相机，渲染地形 → out_top_view_depth (1024×1024)
[球形海洋 Near/Far Pass]
    → 读取:
        in_color     = 地形 out_color
        in_DEPTH     = 地形 out_DEPTH        (blit 后用于折射深度)
        in_top_view_depth = top_view out     (用于水深/遮挡)
    → 写入:
        out_color    (叠加海洋到地形颜色上)
        out_DEPTH    (水面深度，若水面更近则覆盖地形深度)
        out_normal   (水面法线)
```

### 9.2 需要修改的连接点

`Spherical_Ocean_Pass` 的 `in_top_view_depth` 已声明，在效果图（`.fxg`）中补充连线：

```json
// water-system.fxg 或相关效果图配置
{
  "connections": [
    {
      "from": "top_view_pass.out_top_view_depth",
      "to": "spherical_ocean_pass.in_top_view_depth"
    }
  ]
}
```

同时在 C++ 侧（`Spherical_Ocean_Pass::update_near_field`）补充对应 uniform 设置。

### 9.3 编译宏控制

建议复用现有的 `SS_EXT_WATER_SYSTEM_USE_GRAND_TERRAIN` 宏来条件编译整合代码，保持对无地形场景的兼容：

```cpp
// spherical-ocean-pass.cpp
pass.program().configure_int_macro(
    "SS_EXT_WATER_SYSTEM_USE_GRAND_TERRAIN",
    SS_EXT_WATER_SYSTEM_USE_GRAND_TERRAIN
);
```

---

## 10. 已知限制与工程风险

### 10.1 坐标系精度问题（高优先级）

地形使用 `float` 精度的世界坐标，而球形海洋近场在行星尺度下依赖 `double` 精度的 `ocean_space`。两者传给着色器的矩阵精度不同。

**当前安全范围**：相机与地形中心的水平距离 < ~50 km（float 精度足够），近场满足此条件。

若地形尺寸远大于 50 km，需要对地形顶点也进行"以相机为中心的相对坐标"处理，与海洋的 `offset` 机制统一。

### 10.2 地形旋转与海洋球面的角度误差

地形的"旋转伪全球"假设小角度近似。与球形海洋整合时，若将海洋 radius 设定与地形旋转的曲率参数**不一致**，会在数公里外出现地形翘起、穿透海面的情况。

**建议**：确保 `Spherical_Ocean_Config::radius` 的值与地形旋转计算中使用的球半径参数一致（同一个全局常量）。

### 10.3 Top_View_Pass 的相机区域限制

`top_view_pass` 的 `top_camera_region` 决定深度图覆盖的水平范围（例如 1000 m × 1000 m）。超出范围的地形不在深度图中，会导致：
- 远处岸边没有水深遮挡
- 远处泡沫/浅水效果失效

**建议**：球形海洋的近场可见范围远大于普通海洋（投影网格理论上到地平线），若需要远距离海岸线效果，需要扩大 `top_camera_region` 或使用多级 top_view 采样。

### 10.4 GIS Cubemap 精度 vs 实时地形精度

GIS 掩码 cubemap 提供低分辨率（~10~100m/texel）的全球海陆信息，而实时 clipmap 地形有高分辨率（<1m）的局部高程。两者在海岸线位置上会有偏差。

**缓解方案**：在近场（使用 top_view_depth 时）忽略 GIS 掩码，仅用 GIS 掩码在中场/远场（top_view 覆盖范围之外）。

### 10.5 球形海洋 Far Pass 与地形的过渡

`max_altitude = 20km` 时，clipmap 地形已不可见（地形 LOD 范围通常 < 10km），因此远场下不存在地形-海洋交叉的问题。但若 `max_altitude` 被降低到 5km 以下，两者会在同一视口内共存，需要统一深度。

---

## 附录：实施优先级建议

| 优先级 | 工作项 | 预期收益 |
|--------|--------|----------|
| P0 | 在球形近场 Pass 接入 `in_top_view_depth`，实现地形遮挡水面 | 消除陆地被水覆盖的问题 |
| P0 | 球形近场 frag shader 用水深 discard 陆地像素 | 海岸线基本正确 |
| P1 | 水深驱动浅水散射颜色（浅绿/深蓝） | 近岸视觉质量 |
| P1 | 岸边泡沫（基于 water_depth smoothstep） | 海岸线自然感 |
| P2 | 构建全球 GIS Ocean Mask Cubemap | 远场海陆分离 |
| P2 | 远场 Cube Sphere 接入 GIS 掩码，discard 陆地 | 太空视角正确 |
| P3 | `Render_Mode::Blend`：近/远场过渡混合 | 消除 LOD 切换突变 |
| P3 | Top_View_Pass 改为径向相机（球面向下） | 高海拔精度提升 |

---

*文档版本：2026-04-24，基于 `feature/river` 分支及 `ext-fx-grand-terrain` 当前代码状态。*