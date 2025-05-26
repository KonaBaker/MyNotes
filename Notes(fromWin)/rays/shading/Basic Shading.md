# Basic Shading

相关文件：

- shader/water/shading.glsl
- shader/water/subsurface-scattering.glsl

水的基础着色是使用pplPBR管线进行着色的，分为直接光照和间接光照两个部分

**输入输出**

输入数据Shading_Data:（from ocean-frag.glsl)

```
struct Shading_Data {
    // geometry data
    vec3 normal;

    // surface data
    vec3 diffuse_color;
    vec3 specular_color;
    float roughness;
    float reflection_strength;

    // foam data
    vec3 foam_diffuse;
} shading_data;
```

- normal是传入的世界坐标下的法线world_normal
- diffuse_color传入的函数scattering_color(view_dir)的计算结果.Lambertian里面的Cdiff

```
// shader/water/surface-lighting.glsl
vec3 scattering_color(vec3 view_dir)
{
    vec3 scattering_color = mix(material_data.diffuse_color, material_data.grazing_diffuse_color, 1.0 - pow(abs(view_dir.y), 1.0));
    return scattering_color;
}
```

| Diffuse Color         | color | /    | 水体表面散射的颜色。     |
| --------------------- | ----- | ---- | ------------------------ |
| Grazing Diffuse Color | color | /    | 远处水体表面散射的颜色。 |

即观察视角越垂直于水面，越展现近处颜色，相反，越远越倾斜，越展示Grazing Diffuse Color

- specular_color是简单处理后的用户传入的参数，这里控制菲涅尔的F0项
- roughness是brdf中所需要的粗糙度，由简单处理后的用户传入的参数distant_roughness和roughness共同控制
- foam_diffuse式计算出的foam_color
- reflection_strength 从material_data中获得，如果是水下就为0

输出数据 Shading_Result:(to ocean-frag.glsl)

```
struct Shading_Result {
    vec3 diffuse;
    vec3 specular;
    vec3 subsurface;
} shading_result;
```

**bsdf计算部分**

调用ppl的 ``` auto evaluate_BSDF_for_pbr(
    vec3 light_dir,
    vec3 view_dir,
) -> BSDF_Evaluation```

漫反射采用的是Lambertian漫反射模型.

镜面反射就是经典的Cook-Torrance模型，

存储结果供后面使用：
```
BSDF_Evaluation result = get_initialized_BSDF_evaluation();
    result.diffuse = max(diffuse_result, vec3(0.0f));
    result.specular = max(specular_result, vec3(0.0f));
    result.transmission = max(sss + diffuse_Lambert(shading_data.foam_diffuse), vec3(0.0f));
    return result;
```

这里的sss是次表面散射，另见文档。

**直接光照**

```
auto evaluate_direct_lighting_for_water(
    vec3 world_pos,
    vec3 world_normal,
    vec3 eye_pos,
) -> void {
```

**间接光照 **

```
auto evaluate_indirect_color(
    vec3 view_dir,
    vec3 world_normal,
    float roughness,
) -> void
```

其中还计算了ssr所需要用到的indirect_specular





