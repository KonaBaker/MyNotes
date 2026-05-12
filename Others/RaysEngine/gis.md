# Earth 地球模块文档

## 概述

Earth 模块（`ext-fx-grand-terrain/earth`）实现了基于 **Clipmap** 技术的球形地球地形渲染系统。其核心思路是：

1. 将地球曲面用一个二维平铺的 UV 贴图空间（经纬度投影）描述地形网格位置。
2. 用多层 Clipmap 网格在摄像机附近以高精度细分、在远处以低精度覆盖地球表面。
3. 在 GPU 顶点着色器中将平面网格坐标实时转换为球体世界坐标（反投影到椭球体表面）。
4. 通过虚拟纹理（Virtual Texture）系统流式加载全球卫星影像和高度图。

---

## 文件结构

```
source-earth/ext-fx-grand-terrain/
  earth-pass.hpp           -- Earth_Pass 结构体声明、Debug 结构体
  earth-pass.cpp           -- Earth_Pass::Impl 完整实现（核心逻辑）
  action/earth-config.hpp  -- Earth_Config 场景 trait 声明
  action/earth-config.cpp  -- earth_config scene action 实现
  init.cpp                 -- 模块初始化，加载 .fxg 效果图

asset/ext-fx-grand-terrain/earth/
  earth-terrain.fxg        -- 渲染效果图（FXG2格式），描述 Pass 依赖与资源
  pass/earth-pass.json     -- Pass 的 shader 绑定与 attribute 声明
  shader/earth-vert.glsl   -- 顶点着色器（主用）
  shader/earth-frag.glsl   -- 片元着色器（主用，含 VT 采样）
  shader/vert.glsl         -- 辅助顶点着色器（调试/小窗口用）
  shader/frag.glsl         -- 旧版/参考片元着色器（VT已注释）
  shader/virtual-texture1.glsl -- 虚拟纹理采样函数库
```

---

## 核心数据结构

### `Earth_Config`（场景 Trait）

附加在场景节点 `/scene/earth` 上，存储地球的配置参数：

| 字段 | 类型 | 说明 |
|------|------|------|
| `auto_adjusting_camera` | bool | 是否根据摄像机高度自动调整 draw distance 和 bounding radius |
| `enable_lon_lat_h` | bool | 是否使用经纬高模式定位地球中心 |
| `lon_lat_h` | Vector3 | 经度(x)、纬度(y)、高度(z)，单位：度 / 米 |
| `material_node` | string | 地球材质节点的场景路径 |

通过 `scene_action::earth_config(node, config)` 写入场景图。

---

### `Earth_Pass`（渲染 Pass）

继承自 `core::Opaque<Earth_Pass>`，暴露如下接口：

| 成员 | 说明 |
|------|------|
| `in_camera` | 输入相机 |
| `out_color` / `out_DEPTH` | 输出颜色/深度缓冲 |
| `in_common_light_cache` | 直接光照缓存 |
| `in_ibl_data` / `in_ltc_data` | IBL 和 LTC 间接光照数据 |
| `update()` | 每帧 CPU 侧更新（网格、剔除、Uniform） |
| `render()` | 每帧 GPU 渲染调用 |

所有实现细节封装在 `Earth_Pass::Impl` 中（PIMPL 模式）。

---

### `Debug`（调试结构）

控制调试参数（ImGui 可编辑）：

| 字段 | 说明 |
|------|------|
| `lati` / `lonti` | 调试用经纬度偏移 |
| `rotate` | 地球旋转调试角度 |
| `stop_culling` | 冻结相机剔除（定格当前 frustum 进行调试） |

---

## 坐标系与投影

### 平面网格空间 → 经纬度 → 三维世界坐标

模块维护一个 **[0, 2*terrain_size] × [0, terrain_size]** 的二维平铺空间（`terrain_size = 3200.0`），对应全球经纬度范围：

```
U ∈ [0, 2*terrain_size]  →  经度 lon ∈ [-π, π]
V ∈ [0,   terrain_size]  →  纬度 lat ∈ [-π/2, π/2]
```

转换公式（C++ 侧 `update_attribute()`，与 GLSL `clip_uv_to_lat_lon` 对应）：

```
mesh_uv = pos / terrain_size          // 归一化到 [0,2]×[0,1]
lat = mesh_uv.y * π - π/2
lon = (2 - mesh_uv.x) * π - π
```

椭球体表面法线（`geodetic_surface_normal`）：

```
normal.x = cos(lat) * cos(lon)
normal.y = -sin(lat)
normal.z = cos(lat) * sin(lon)
```

最终世界坐标：

```
world_pos = normal * earth_radius + earth_center
```

`earth_radius` 为非均匀椭球半径（赤道 6378137 m，极半径 6356752.3 m），按场景节点 scale 缩放。

### 地球中心位置

- 默认：`preset_earth_center_pos = (0, -6356752.3, 0)`，即地球极点朝上对齐 Y 轴。
- 启用 `enable_lon_lat_h` 时：通过 `Ellipsoid::geodetic_to_wgs()` 将经纬高转为 WGS84 直角坐标，再取反作为中心偏移，使得指定地点位于场景原点正上方。

### 地球旋转

通过 `Earth_Config` 的场景节点 `rotation` 四元数获取，转为欧拉角后构造旋转矩阵，传入 shader 的 `uniform mat4 rotation`。Shader 用此矩阵将法线方向旋转到纹理坐标空间，实现地球自转对齐卫星图。

---

## Clipmap 网格系统

### 网格类型

`Mesh_Kind` 枚举定义了五种网格，共同覆盖所有 Clipmap 层级：

| 类型 | 节点路径 | 用途 |
|------|----------|------|
| `tile` | `.../tile-mesh` | 每层的主体方形地块（4×4布局，中心空洞） |
| `filler` | `.../filler-mesh` | 填补相邻层级之间的 1 单位宽缝隙 |
| `trim` | `.../trim-mesh` | L 形裁剪条，修正层级吸附偏移时产生的接缝 |
| `cross` | `.../cross-mesh` | 最内层（level 0）十字网格，覆盖摄像机正下方 |
| `seam` | `.../seam-mesh` | 沿每层外边缘的边缝，消除 T 型接缝 |

### `init_mesh()`

**在第一帧**生成所有五种网格的顶点和索引数据，上传到场景图节点。

- `tile_resolution = 256`，顶点数为 257×257
- Tile 网格使用 **Triangle Strip** 拓扑（逐行）
- Filler/Trim/Cross/Seam 使用 **Triangles** 拓扑

所有网格坐标均为**局部平面整数坐标**，不含世界变换；顶点到世界位置的映射完全在 GPU Vertex Shader 中完成。

### `update_attribute()`

每帧重新计算所有 Clipmap 实例的位置和缩放，写入 `clipmap_cache` 和 `level_cached`。

**核心算法**：

1. 从摄像机世界坐标出发，通过椭球体投影计算摄像机在平面网格空间中的 `camera_xz`。
2. 按 `needed_level = 6` 个层级迭代（`l = 0..5`）：
   - 每层 `scale = 2^l / texel_per_unit`（`texel_per_unit = 4`）
   - 对 4×4 tile 布局，内层 (1,1)(1,2)(2,1)(2,2) 在 `l > 0` 时跳过（由下层填充）
   - 生成 trim 时计算 `next_snapped_pos` 与当前 `snapped_pos` 的偏差方向，选取 4 种旋转（`r = 0..3`）之一
3. 每个实例编码为 `vec4(offset.x, offset.y, scale, rotation_index)`

### `instance_culling()`

对 `tile` 网格执行两级实例剔除：

**1. 背面剔除（Face Culling）**

将 Tile 的四个角点转回世界坐标，检查所有角点的椭球面法线是否均背向摄像机。若全部背向则剔除（地球背面不可见）。

**2. 视锥剔除（View Frustum Culling）**

将 4 个角点 + 对应 50000m 高空点（共 8 点）变换到 Clip Space，用 Cohen-Sutherland 风格的位掩码判断是否完全在某一裁剪平面外侧。全 8 点在同一侧时剔除。

---

## 每帧 CPU 更新流程

```
Earth_Pass::update()
  └── Impl::update()
        ├── [第一帧] init_mesh()          -- 生成并上传 Clipmap 网格
        ├── [第一帧] 绑定材质节点          -- Link + set_typeless_material
        ├── update_transform()            -- 计算 earth_center / earth_radius / earth_rotate
        ├── update_camera()              -- 更新相机快照；自动调整 draw distance
        ├── 清空 pass.queue
        ├── 设置 framebuffer (color + depth)
        ├── 配置 camera / lighting uniforms (IBL / LTC / 直接光)
        ├── material.configure_pass()    -- 注入材质 shader 宏
        ├── update_attribute()           -- 重算所有 Clipmap 实例位置
        ├── instance_culling()           -- CPU 剔除 tile 实例
        ├── set_uniform()                -- 上传 earth_center/radius/rotation/terrain_size 等
        ├── generate_render_queue()      -- 组装 Draw Call（实例化）
        └── 上传 VT feedback uniforms    -- factor / period / screen_size / frame_cnt
```

### `set_uniform()`

向 Pass 上传全局 Uniform：

| Uniform | 含义 |
|---------|------|
| `earth_center` | 椭球体中心世界坐标 |
| `earth_radius` | 椭球体三轴半径 |
| `rotation` | 4×4 地球自转矩阵 |
| `terrain_size` | 3200.0（平面网格总边长） |
| `max_height` | 100.0（高度图最大高度，暂未激活） |
| `clipmap_vert_num` | 1026（= 256*4+2） |
| `max_level` | 6 |

### `generate_render_queue()`

对五种网格各生成一条 **Instanced Draw Call**：

- `CLIPMAP` 属性：`vec4(offset_x, offset_y, scale, rotation_idx)`，实例化步进
- `CLIPMAP_LEVEL` 属性：`float level`，实例化步进
- `mesh_kind` uniform：区分网格类型（shader 内可按类型差异化处理）

---

## 每帧 GPU 渲染流程

### Render 调用（`Impl::render()`）

检测相机投影矩阵中 `view_to_clip[3][2]` 的符号判断是否为 **Reverse-Z**：
- Reverse-Z：`glClipControl(GL_ZERO_TO_ONE)` + `depth_func = GREATER`
- 正常 Z：`glClipControl(GL_NEGATIVE_ONE_TO_ONE)` + `depth_func = LESS_EQUAL`

渲染完毕后将 ClipControl 复原为标准值。

---

## 顶点着色器（`earth-vert.glsl`）

### 输入

| 属性 | 说明 |
|------|------|
| `vert_pos` (vec3) | 局部平面网格坐标 |
| `clipmap_data` (vec4) | (offset_x, offset_y, scale, rotation_idx) |
| `clipmap_level` (float) | 当前 Clipmap 层级 |

### 主要流程（`vert_function`）

```
1. 应用 rotation_matrix[rotation_idx] 旋转局部顶点（trim 网格四向对称）
2. pos.xz = clipmap_offsets + pos.xz * clipmap_scale  -- 缩放+偏移到平面网格空间
3. 处理 x 轴环绕（< 0 或 > 2*terrain_size 时平移）
4. mesh_uv = pos.xz / terrain_size                   -- 归一化 UV
5. lat_lon = clip_uv_to_lat_lon(mesh_uv)             -- UV → 经纬度
6. normal = geodetic_surface_normal(lat_lon)         -- 经纬度 → 球面法线
7. 应用 rotation 矩阵 → atan2 球面 UV → 纹理坐标
8. world_pos = normal * earth_radius + earth_center  -- 映射到椭球面
9. clip_pos = MVP * world_pos
```

### Trim 旋转矩阵（4种）

| rotation_idx | 效果 |
|---|---|
| 0 | 恒等（右上角） |
| 1 | 顺时针 90°（左上角） |
| 2 | 逆时针 90°（右下角） |
| 3 | 旋转 180°（左下角） |

---

## 片元着色器（`earth-frag.glsl`）

### UV 计算

在片元着色器中重新由 `out_local_pos`（顶点传入的球面法线）计算精确球面 UV：

```glsl
point = normalize(rotation * vec4(out_local_pos, 0.0));
angle_xz = atan(point.z, point.x);    // 经度方向
acos_y   = atan(sqrt(x²+z²), point.y); // 纬度方向（更稳定）
uv.x = fract(angle_xz / (2π)) * 2.0;
uv.y = 1.0 - fract(acos_y / π);
```

UV 范围 `[0,2]×[0,1]`，左半（x≤1）采样 `earth_0`，右半（x>1）采样 `earth_1`。

### 材质与光照

- 通过 `material_function_get_fragment_material_data()` 调用材质函数（由 `material_node` 配置的材质决定具体外观）
- 用 `evaluate_direct_lighting_for_pbr()` 计算 PBR 直接光照（漫反射 + 高光 + 自发光）
- 法线取球面法线（`vert.normal`），未启用法线贴图

### VT Feedback

每帧按 `period`（帧周期）和 `factor`（屏幕分块因子）对屏幕像素分块采样，将 VT 请求（mip 层级、页面坐标）写入 SSBO `vt_feedback`，供虚拟纹理系统决定哪些页需要流式加载。

---

## 虚拟纹理系统（`virtual-texture1.glsl`）

### 数据结构

- `Earth_Vt_Uniform`：描述一张虚拟纹理，含 pagetable sampler、physical texture sampler、宽高、tile 尺寸、border 等参数。
- `VT_Pagetable_Result`：查表结果，含实际物理纹理 UV 和打包的 feedback 请求。

### 主要函数

| 函数 | 功能 |
|------|------|
| `compute_mip_level(uv, tex_size)` | 用 dFdx/dFdy 计算适合的 mip 层级 |
| `texture_load_virtual_pagetable(pagetable, vt, uv)` | 自动计算 mip，查 pagetable，返回物理页信息 |
| `texture_load_virtual_pagetable1(pagetable, vt, uv, level)` | 指定 mip 层级查 pagetable |
| `texture_virtual_sample(physical_texture, result, vt)` | 根据查表结果在物理纹理中采样 |
| `texture_virtual_sample_layer(...)` | 带 layer 索引的物理纹理采样（旧版接口） |

### 地球纹理分配

| 虚拟纹理 | 范围 | 内容 |
|----------|------|------|
| `earth_0` | UV.x ∈ [0, 1] | 东半球卫星影像 |
| `earth_1` | UV.x ∈ [1, 2] | 西半球卫星影像 |
| `earth_height` | 全球 | 高度图（f32x1，预留，当前高度为 0） |

---

## 效果图配置（`earth-terrain.fxg`）

```
earth-terrain (alias) → earth-terrain.full
  PASS: Earth_Pass
  输入: camera, common-light-cache, ibl-data, ltc-data, color, depth
  输出: color, depth
  旁路: earth-terrain.bypass（不含 PASS，直接透传资源）
```

`earth-terrain.bypass` 用于在不需要地球渲染时跳过该 Pass，保持资源管线完整性。

---

## 相机自适应（`update_camera()`）

当 `auto_adjusting_camera = true` 时，按摄像机距地面高度动态调整场景的 `draw_distance` 和 `camera_bounding_radius`：

| 高度范围 | camera_bounding_radius | draw_distance |
|----------|----------------------|---------------|
| < 100 m | 1.0 | 8,000 m |
| 100 ~ 200 m | 5.0 | 50,000 m |
| 200 ~ 500 m | 50.0 | 80,000 m |
| 500 ~ 1000 m | 200.0 | 80,000 m |
| 1000 ~ 20000 m | 500.0 | 30,000,000 m |
| > 20000 m | 8000.0 | 30,000,000 m |

地平线可见距离公式：`draw_distance = sqrt(2 * R * h + h²)`，R = 6,371,000 m。

---

## 整体数据流

```
[场景图 /scene/earth]
  └── Earth_Config trait
        ├── material_node ──────────────────────────┐
        ├── enable_lon_lat_h / lon_lat_h            │
        └── auto_adjusting_camera                   │
                                                    │
[每帧 CPU side]                                     │
  update_transform()                                │
    └── earth_center, earth_radius, earth_rotate    │
  update_camera()                                   │
    └── draw_distance / camera_bounding_radius      │
  update_attribute()                                │
    └── clipmap_cache[5 kinds] × 6 levels           │
  instance_culling()                                │
    └── 过滤不可见 tile 实例                           │
  set_uniform()                                     │
    └── earth_center/radius/rotation → Pass         │
  generate_render_queue()                           │
    └── 5 × Instanced Draw Call                    │
                                                    ▼
[GPU Vertex Shader: earth-vert.glsl]         [Material Node]
  平面网格坐标                                  material_function
    → 旋转/缩放/偏移                           (纹理、PBR 参数)
    → UV → lat/lon → 球面法线                       │
    → world_pos = normal * radius + center          │
    → clip_pos = MVP * world_pos                    │
                                                    │
[GPU Fragment Shader: earth-frag.glsl] ◄────────────┘
  球面法线 → 球面 UV
    → VT Pagetable 查表 (earth_0 / earth_1)
    → VT Physical Texture 采样
    → material_function → PBR 材质参数
    → evaluate_direct_lighting (漫反射 + 高光)
    → fragment_color
    → VT feedback 写入 SSBO
```

---

## 注意事项与已知状态

- **高度图**（`earth_height`）已预留接口（`init_vt` / `update_normal_tex`）但当前已注释，顶点高度固定为 0。
- `frag.glsl` / `vert.glsl`（earth/shader 目录下不含 "earth-" 前缀的）为早期版本，目前已不被 `earth-pass.json` 引用。
- `HEIGHT_FEEDBACK_COUNTER` storage buffer 接口已注释，高度反馈尚未启用。
- Trim 网格的旋转方向（`r` 计算）依赖当前层与下一层 snapped_pos 之差，确保 L 形裁剪条始终朝向正确方向避免缝隙。
- 视锥剔除目前仅对 `tile` 实例执行，`filler/trim/cross/seam` 不剔除。