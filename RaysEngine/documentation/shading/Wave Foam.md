Wave Foam

相关文件：

- runtime/shader/water/ocean-frag.glsl
- runtime/shader/water/foam.glsl
- runtime/shader/fft/post-process-comp.glsl
- runtime/shader/water/shading.glsl
- runtime/shader/wave/fft-wave.glsl

---

泡沫的计算主要是通过快速傅里叶变换获得了Jacobian数据，再由得到的Jacobian数据获得白沫的效果。

主要的公式：

```
foam = clamp((−Jacobian +foam_bias) * foam_scale,0.0,1.0)
```

其中，foam_bias 和foam_scale 是用户可以调控的参数，foam_bias 调大可以增加白沫的覆盖率，foam_scale 可以调整白沫的强度。 但是如果直接这样去实现会发现白沫的效果随着波浪变化会略显生硬，针对这种情况，这里在获得这一帧的Jacobian数据时，会根据下面的公式将其与 上一帧的Jacobian数据进行混合。

```
Jacobian = min(Jacobian,Jacobian_last + 0.5dt/max(Jacobian,0.5))
```

其中dt是两帧之间的间隔时间，这样进行混合后，就可以获得较为自然的白沫效果。

**jacobian计算与输出**

在fft post-process处理中根据dx_dz_dy_dxz，dyx_dyz_dxx_dzz，存储到turbulence中。

```
for (int i = 0; i < cascades_count; i++) {
    ivec3 id = ivec3(gl_GlobalInvocationID.xy, i);
    float permute = 1.0 - 2.0 * ((id.x + id.y) % 2);
    vec4 dx_dz_dy_dxz_data = imageLoad(dx_dz_dy_dxz, id) * permute;
    vec4 dyx_dyz_dxx_dzz_data = imageLoad(dyx_dyz_dxx_dzz, id) * permute;
    float jacobian = (1.0 + lambda * dyx_dyz_dxx_dzz_data.z) * (1.0 + lambda * dyx_dyz_dxx_dzz_data.w) - lambda * lambda * dx_dz_dy_dxz_data.w * dx_dz_dy_dxz_data.w;
    float last_jacobian = imageLoad(turbulence, id).x;
    jacobian = min(jacobian, last_jacobian + delta_time * 0.5 / max(jacobian, 0.5));
    imageStore(turbulence, id, vec4(jacobian, 0.0, 0.0, 0.0));
}
```

**shading部分**

首先是使用sample_turbulence获取jacobian的数据，这个函数还对数据应用了上面第一个公式进行处理。

```
float sample_turbulence(vec2 world_uv, vec4 foam_bias, float foam_scale)
{
    float res = 0.0;

    if (ACTIVE_CASCADES[3] && weights[3] > 0.0) {
        res += texture(turbulence, vec3(world_uv / length_scale[0], 0.0)).x;
        res += 
        ...
        res = min(1.0, max(0.0, (-res + foam_bias[3]) * foam_scale));
    }
    else if (
    ...
    return res;
}
```

之后输出到foam_color:

```
if (wave_foam_enable)
        compute_wave_foam(jacobian, foam_color);
```

这个方法只是进行简单的数据拷贝。

之后会把数据传入shading_data中:

```
shading_data.foam_diffuse = foam_color;
```

在shading中 foam_color作为subsurface/transmission的一个影响因子。

直接光照：

```
result.transmission = max(sss + diffuse_Lambert(shading_data.foam_diffuse), vec3(0.0f));
```

间接光照：

```
shading_result.subsurface += shading_data.foam_diffuse * irradiance;
```

