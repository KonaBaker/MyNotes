1. # spherical-ocean 与 GIS 整合实现报告

   ## 1. object

   这次整合的核心，不是“把海面画出来”，而是让 `spherical-ocean` 能在 `grand terrain / GIS` 场景里和地球坐标系统对齐，并且只在 GIS 判定为水域的位置渲染。

   本次实现主要解决三件事：

   1. 地球是椭球，海洋是球体，视角靠近地平线时会产生明显错位。
   2. GIS 水域判定过于依赖单点颜色，导致海面只在少量块上触发。
   3. near / far 两条 spherical ocean 渲染路径要共享同一套 GIS 掩码逻辑。

   ## 1. overview

   | 模块 | 文件 | 作用 |
   |---|---|---|
   | 地球服务 | `ext-fx-grand-terrain/source-earth/ext-fx-grand-terrain/service/earth-service.cpp` | 统一提供地球中心、半径、参考 ECEF、坐标转换 |
   | 地球渲染 | `ext-fx-grand-terrain/source-earth/ext-fx-grand-terrain/earth-pass.cpp` | 在 sphere 模式下把地球状态写入 `Earth_Service` |
   | 海洋网格 | `ext-fx-water-system/source/ext-fx-water-system/spherical-ocean-mesh.cpp` | 生成近场 `Screen_Space_Grid` 和远场 `Cube_Sphere` |
   | 球面海洋主流程 | `ext-fx-water-system/source/ext-fx-water-system/spherical-ocean-pass.cpp` | 选择 near/far 路径、绑定地球参考、准备渲染参数 |
   | GIS 水域 mask | `ext-fx-water-system/asset/ext-fx-water-system/shader/spherical/spherical-water-mask.glsl` | 根据屏幕颜色判断当前位置是否应渲染海面 |
   | 近场片元 | `ext-fx-water-system/asset/ext-fx-water-system/shader/spherical/spherical-near-frag.glsl` | 屏幕网格近场海面渲染 |
   | 远场片元 | `ext-fx-water-system/asset/ext-fx-water-system/shader/spherical/spherical-far-frag.glsl` | cube-sphere 远场海面渲染 |
   | 配置 | `ext-fx-water-system/source/ext-fx-water-system/trait/spherical-ocean-config.hpp` | spherical ocean 默认半径和分辨率 |
   | 资产默认值 | `ext-fx-water-system/asset/ext-fx-water-system/pool/object-spherical-ocean.json` | 导入时的默认 spherical ocean 参数 |

   ## 3. 地球侧：GIS 参考数据从哪里来

   `earth-pass.cpp` 在 `Earth_Type::sphere` 下，会把地球服务需要的参考信息写入 `Earth_Service`。这一步是 spherical ocean 和 GIS 对齐的基础。

   ```cpp
   auto reference_ecef = lon_lat_height_to_ecef(ref_lon, ref_lat, ref_h);
   auto ecef_to_local = create_ecef_to_enu_rotation(ref_lon, ref_lat);
   
   earth_service.mutable_earth_radius() = earth_radius;
   earth_service.mutable_reference_ecef() = reference_ecef;
   earth_service.mutable_reference_point_lon_lat() = vec2{(float)ref_lon, (float)ref_lat};
   earth_service.mutable_earth_rotation_matrix() = rot4;
   earth_service.mutable_earth_center() = world_offset - rot4 * reference_ecef;
   ```

   这段代码的职责很明确：

   1. `earth_radius` 提供球体尺度。
   2. `earth_center` 提供球心位置。
   3. `reference_ecef` / `earth_rotation_matrix` 提供经纬度到世界坐标的转换基础。

   `Earth_Service` 本身还负责两个方向的坐标转换：

   1. `convert_latlonh2world()`：经纬高转世界坐标。
   2. `convert_world2latlonh()`：世界坐标转经纬高。

   这意味着 spherical ocean 不需要自己再猜 GIS 的地球原点，而是直接复用地球服务的标准坐标系。

   ## 4. spherical-ocean 主流程

   `spherical-ocean-pass.cpp` 是整条链路的中心。它做三件事：

   1. 读取 spherical ocean 配置。
   2. 结合 GIS 地球服务，决定当前海面参考球心和半径。
   3. 根据相机位置选择 near / far 渲染路径。

   ### 4.0 海洋网格模块

   `spherical-ocean-mesh.cpp` 提供两种几何：

   1. `Screen_Space_Grid`：近场使用的屏幕空间网格。
   2. `Cube_Sphere`：远场使用的立方球网格。

   ```cpp
   float f = 1.25;
   int NX = static_cast<int>(f * io.screen_width / io.resolution);
   int NY = static_cast<int>(f * io.screen_height / io.resolution);
   ```

   这段逻辑的作用是让近场网格略微超出屏幕边界，避免视口边缘出现裂缝。`resolution` 越大，网格越密，近场细节越稳定，但性能开销也越高。

   ### 4.1 参考球心和半径

   ```cpp
   auto resolve_ocean_reference(Spherical_Ocean_Config const& config) -> Ocean_Reference
   {
       Ocean_Reference reference{};
       reference.radius = config.radius;
   
   #if SS_EXT_WATER_SYSTEM_USE_GRAND_TERRAIN == 1
       if (reference.radius != 0.0) {
           auto graph = scene::Scene::graph().read_only_transaction();
           auto earth_node = ss::ext_fx_grand_terrain::earth::Earth_Service::current().trait_node();
           if (earth_node != scene::Scene_Node_ID::nil &&
               graph.has_trait<ss::ext_fx_grand_terrain::Earth_Config>(earth_node)) {
               if (ss::ext_fx_grand_terrain::earth::Earth_Service::current().earth_type() ==
                   ss::ext_fx_grand_terrain::Earth_Type::sphere) {
                   auto earth_center = ss::ext_fx_grand_terrain::earth::Earth_Service::current().earth_center();
                   auto earth_radius = ss::ext_fx_grand_terrain::earth::Earth_Service::current().earth_radius();
                   reference.center = glm::dvec3{earth_center.x, earth_center.y, earth_center.z};
                   reference.radius = std::max({
                       reference.radius,
                       static_cast<double>(earth_radius.x),
                       static_cast<double>(earth_radius.y),
                       static_cast<double>(earth_radius.z)
                   });
                   return reference;
               }
           }
       }
   #endif
   
       reference.center = preset_spherical_ocean_center_pos;
       return reference;
   }
   ```

   功能说明：

   1. `radius == 0` 时保留平面海洋模式。
   2. sphere + grand terrain 时，海洋中心直接跟随 `Earth_Service::earth_center()`。
   3. 海洋半径不会小于地球半径，避免海面被椭球地球裁掉。

   ### 4.2 近场：屏幕空间网格

   近场逻辑在 `update_near_field()`。

   ```cpp
   auto camera_pos_rel = camera_pos - ocean_center_pos;
   uy = glm::normalize(camera_pos_rel);
   origin = ocean_center_pos + uy * ocean_radius;
   near_pass.set_uniform("radius", static_cast<float>(ocean_radius));
   ```

   这段逻辑的含义是：

   1. `uy` 不再直接用世界原点到相机的方向，而是用“相机相对球心”的方向。
   2. `origin` 落在当前海洋球面上，而不是固定在旧的参考点。
   3. `radius` 统一使用 `ocean_radius`，与 GIS 地球参考一致。

   后续还会计算 horizon 参数、`grid_size` 和 FFT 波浪相关 uniform。`Screen_Space_Grid` 的职责只是生成近场网格，海面真实形态仍由 shader 和 wave service 决定。

   ### 4.3 远场：cube-sphere

   远场逻辑在 `update_far_field()`。

   ```cpp
   auto model = glm::translate(glm::dmat4(1.0), glm::dvec3(0.0));
   model = glm::translate(model, ocean_center_pos);
   model = glm::scale(model, glm::dvec3(ocean_radius));
   far_pass.set_uniform("local_to_world_space", glm::mat4(model));
   ```

   功能说明：

   1. cube-sphere 被平移到 GIS 球心。
   2. cube-sphere 按 ocean 半径缩放。
   3. far path 和 near path 使用同一个 ocean reference。

   ### 4.4 路径选择和渲染

   `update()` 按相机到球心距离决定使用 near 还是 far：

   1. 相机距离小于 `ocean_radius + max_altitude` 时使用 near。
   2. 否则使用 far。
   3. 当球心或半径变化时，重置 `last_world_to_ocean_space` 和 `offset`，避免旧状态污染新参考系。

   `render()` 的职责是：

   1. 先 `blit` 当前场景颜色和深度。
   2. 给当前 pass 绑定 `blit_scene_color` / `blit_scene_depth`。
   3. 根据 reverse-Z 设置深度比较函数。
   4. 执行 near 或 far pass。

   ## 5. GIS 水域 mask

   `spherical-water-mask.glsl` 是这次整合里最关键的 GIS 识别层。它不直接理解“GIS 语义水体”，而是从当前场景颜色中推断水域区域。

   ### 5.1 单点颜色分类

   ```glsl
   float classify_gis_water(vec3 scene_color)
   {
       vec3 c = clamp(scene_color, vec3(0.0), vec3(1.0));
       float blue_dominance = c.b - max(c.r, c.g);
       float blue_vs_red = c.b - c.r;
       float blue_vs_green = c.b - c.g;
   
       float water_score = smoothstep(-0.12, 0.14, blue_dominance);
       water_score *= smoothstep(-0.10, 0.16, blue_vs_red);
       water_score *= smoothstep(-0.14, 0.12, blue_vs_green);
       water_score *= smoothstep(0.02, 0.50, c.b);
       return water_score;
   }
   ```

   这段函数的作用是给一个像素打“水域分数”：

   1. `blue_dominance` 判断蓝色是否整体强于红绿。
   2. `blue_vs_red` 和 `blue_vs_green` 进一步抑制偏灰、偏绿的误判。
   3. `c.b` 保证蓝通道本身足够强。

   这里的阈值被故意放宽，是为了兼容 GIS 贴图压缩、抗锯齿、海岸线和 label 污染。

   ### 5.2 邻域投票

   ```glsl
   float sample_gis_water_score(vec2 screen_uv)
   {
       vec2 texel_size = 1.0 / vec2(textureSize(blit_scene_color, 0));
       float water_score = 0.0;
   
       for (int y = -2; y <= 2; ++y) {
           for (int x = -2; x <= 2; ++x) {
               vec2 sample_uv = clamp(screen_uv + vec2(float(x), float(y)) * texel_size, vec2(0.0), vec2(1.0));
               water_score = max(water_score, classify_gis_water(texture(blit_scene_color, sample_uv).rgb));
           }
       }
   
       return water_score;
   }
   ```

   这一步把单点分类变成 5x5 邻域膨胀，主要解决：

   1. GIS 瓦片边界断裂。
   2. 单个像素被文字或图标污染。
   3. 水域本来连续，但屏幕采样点太稀疏。

   ### 5.3 最终判定

   ```glsl
   bool should_draw_spherical_ocean(vec2 screen_uv)
   {
       return sample_gis_water_score(screen_uv) > 0.16;
   }
   ```

   这一步决定当前片元是否参与 spherical ocean 渲染。阈值比初版更低，用来减少“稀疏块状替换”。

   ## 6. 近场 / 远场片元着色器

   `spherical-near-frag.glsl` 和 `spherical-far-frag.glsl` 共享同一个 mask 文件，因此它们的 GIS 水域判断是一致的。

   ### 6.1 near frag

   ```glsl
   vec2 screen_uv = gl_FragCoord.xy / vec2(textureSize(blit_scene_color, 0));
   if (!should_draw_spherical_ocean(screen_uv))
       discard;
   
   ...
   gl_FragDepth = biased_spherical_ocean_depth(gl_FragCoord.z);
   ```

   near path 的主要职责：

   1. 用屏幕空间网格计算波浪表面。
   2. 通过 `ocean_pos_uv` 和 FFT derivative 生成法线。
   3. 用 `world_ocean_pos` 做光照和粗糙度衰减。

   ### 6.2 far frag

   ```glsl
   vec2 screen_uv = gl_FragCoord.xy / vec2(textureSize(blit_scene_color, 0));
   if (!should_draw_spherical_ocean(screen_uv))
       discard;
   
   ...
   gl_FragDepth = biased_spherical_ocean_depth(gl_FragCoord.z);
   ```

   far path 的主要职责：

   1. 在 cube-sphere 上做远距离海面。
   2. 使用 `world_pos` / `world_normal` 参与光照。
   3. 与 near path 共用同一套 GIS mask 和深度偏移逻辑。

   ## 7. 配置和默认资产

   ### 7.1 `Spherical_Ocean_Config`

   ```cpp
   double radius{6378137.0};
   double max_altitude{15000};
   Screen_Space_Config screen_space_config;
   Cube_Sphere_Config cube_sphere_config;
   ```

   含义：

   1. `radius` 默认对齐地球赤道半径。
   2. `max_altitude` 控制 near / far 切换距离。
   3. `screen_space_config.resolution` 控制近场网格密度。
   4. `cube_sphere_config.resolution` 控制远场网格密度。

   ### 7.2 `object-spherical-ocean.json`

   导入默认值也同步到了：

   1. `radius = 6378137.0`
   2. `screen_space_config.resolution = 8`
   3. `cube_sphere_config.resolution = 256`

   这保证默认创建的 spherical ocean 不会再和 GIS 地球尺度错开太远。

   ## 8. 数据流

   整条链路可以理解为：

   1. `earth-pass.cpp` 先把 GIS 地球的球心、半径、参考 ECEF 写入 `Earth_Service`。
   2. `spherical-ocean-pass.cpp` 读取 `Earth_Service`，选择海洋球心和半径。
   3. 近场和远场 pass 共享同一组 ocean reference。
   4. `blit_scene_color` 被送进 `spherical-water-mask.glsl`。
   5. mask 决定当前位置是否允许海面渲染。
   6. 允许渲染时再进入波浪、光照、深度写回。

   ## 9. 结果

   当前实现后的效果是：

   1. 球面海洋不再以错误的世界原点运行。
   2. 视角接近地平线时，海面不会再被椭球 GIS 不规则切断。
   3. GIS 水域覆盖从“零散块”变成更连续的区域。
   4. near / far 的行为一致，调试和后续维护更容易。

   ## 10. Notes

   是基于 GIS 颜色的水域判定，不是基于真正的地理水体语义数据。

   1. 从 GIS 元数据里引入显式水体标识。
   2. 或者接入单独的水域 mask 纹理，而不是仅靠当前可见颜色。
