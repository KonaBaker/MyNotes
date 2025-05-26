# refrection

相关文件：

- shader/water/surface-lighting.glsl
- shader/water/water-common.glsl
- shader/water/ocean-frag.glsl

注意：这里的折射不是物理中基本的折射,即水面平静的时候不发生折射。因为对于光线的折射，在实时绘制中获取完全正确的结果是相当困难的，性能上是难以接受的，所以watersystem采用的是根据法线和物体具体深度对其采样的坐标进行扰动的方法来模拟折射的效果。

```
struct Material_Data
{
	...
    vec3 depth_fog_density;
    float refraction_distortion_strength;
    ...
};

uniform Material_Data material_data;
```

上面是从外部获取的相关material_data，这个data在water-material-service.cpp中的uniforms进行设置。

只列出了和折射有关的参数。

depth_fog_density 控制水下折射物体的颜色衰减。

refraction_distortion_strength 水下物体折射扰动的强度。

```
vec3 apply_refraction_color(vec3 diffuse_color, vec3 world_normal, vec2 screen_uv, float water_raw_depth, float scene_raw_depth, float water_linear_depth, float scene_linear_depth, bool underwater)
```

这里传入的参数：

diffuse_color:是之前在shading.glsl中计算的水的漫反射颜色。

world_normal:是水的法线的世界坐标，如果在水下这个法线会取反

screen_uv: 屏幕的uv坐标

*_raw_depth: fs中存储的z值

*_linear_depth: 变换前的线性深度

underwater: 是不是在水下

下面这一段是在ocean-frag中设置underwater的一段代码。

```
// underwater
util_parameters.underwater = !gl_FrontFacing;
if (util_parameters.underwater) {
    world_normal = -world_normal;
    pre_wave_normal = -pre_wave_normal;
}
```

gl_FrontFacing是片段着色器的一个输入变量，其用来判断绘制的片段是正面的一部分还是背面的一部分。

如果绘制的片段在背面也就是水下，那么对法线取反，underwater置为1。

```
vec3 scene_color;
vec3 alpha = vec3(0.0);
float depth_fog_distance;
```

这里折射采用的方法是对uv进行扰动偏移。

blit_scene是采样的场景物体的深度或颜色信息。

```
if (!underwater)
{
    vec2 refract_offset = material_data.refraction_distortion_strength * world_normal.xz *
        min(1.0, 0.5 * (scene_linear_depth - water_linear_depth) / scene_linear_depth);
    vec2 background_refract_uv = screen_uv + refract_offset;
    float refract_raw_depth = texture(blit_scene_depth, background_refract_uv).r;
    if (refract_raw_depth $${compare_sign} water_raw_depth)
    {
        depth_fog_distance = linear_depth(multi_sample_depth(background_refract_uv, refract_raw_depth)) - water_linear_depth;
    }
    else
    {
        depth_fog_distance = linear_depth(multi_sample_depth(screen_uv, refract_raw_depth)) - water_linear_depth;
        background_refract_uv = screen_uv;
    }
    depth_fog_distance = abs(depth_fog_distance);
    scene_color = texture(blit_scene_color, background_refract_uv).rgb;
    alpha = 1.0 - exp(-material_data.depth_fog_density.xyz * depth_fog_distance);
}
```

如果不是在水下：

1.计算refract_offset偏移，包括折射扰动的系数、法线、以及一项距离的系数。

- distortion是由用户控制的扰动强度的参数

- 法线，根据法线在xz平面上的偏移来计算uv偏移。

- 距离的系数，场景离水面越远，系数越大，代表偏移越大。也比较符合真实情况。

2.之后计算应该采样的偏移uv坐标background_refract_uv。

3.计算alpha,这里的alpha是由depth_fog_distance和depth_fog_density计算得到的。

4.利用该坐标计算采样的颜色，通过alpha进行混合。得到水面的最终颜色

```
else
{
    vec2 background_refract_uv = screen_uv + material_data.refraction_distortion_strength * world_normal.xz;
    scene_color = texture(blit_scene_color, background_refract_uv).rgb;
}
```

如果在水下：

1.计算应该采样的偏移uv坐标background_refract_uv。这里与上面不同，只是根据折射系数和法线进行了偏移。

2.采样颜色。

3.alpha混合，这里alpha为默认的0，展现从水下向上看的完全透明效果。

```
vec3 color = mix(scene_color, diffuse_color, alpha);
return color;
```

