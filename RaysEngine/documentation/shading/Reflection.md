# Reflection

相关文件：

- source/screen-space-reflection/*
- runtime/shader/screen-space.reflection/*
- runtime/shader/util/screen-quad-vert.glsl
- runtime/shader/util/screen-space-common-function.glsl

---

反射技术总结：[图形学基础|屏幕空间反射(SSR)](https://blog.csdn.net/qjh5606/article/details/120102582)

水体系统采用的是Stochastic Screen-Space Reflections

- [Stochastic Screen-Space Reflections.pptx](https://view.officeapps.live.com/op/view.aspx?src=https%3A%2F%2Fadvances.realtimerendering.com%2Fs2015%2FStochastic%20Screen-Space%20Reflections.pptx&wdOrigin=BROWSELINK)
- [屏幕空间步进方法](https://jcgt.org/published/0003/04/04/)

![0f27a4da-1223-4250-8335-d1aa69e5d070](C:\Users\Administrator\AppData\Local\Temp\0f27a4da-1223-4250-8335-d1aa69e5d070.png)

渲染pass顺序：

hzb_passes - > screen_space_ray_tracing_pass - > resolve_pass - > combine_pass

后面三个pass的vertex shader都为screen-quad-vert.glsl

### hzb_passes

---

#### cpu部分

#### ``` setup_hzb_passes ```

**``` create_and_setup_hzb```**

向```hierarchical_z```的尾部设置一个默认（空）纹理（具有相应的格式），并在对应pass的uniform的对应层级设置vector的指针 image_mip_level[level]。

该函数会被后面的管线设置函数调用。



之后是设置当前屏幕信息的一些参数。这里有一个对“生成多少层”的计算

```
auto mip_levels = 0u;
auto src_width = static_cast<int>(cur_screen_size.x), src_height = static_cast<int>(cur_screen_size.y);
while (src_width != 0 || src_height != 0) {
    src_width  >>= 1;
    src_height >>= 1;
    mip_levels++;
}
```

2^mip_level是大于且最接近屏幕空间大小的一个值

current_level从0开始，current_xy是现在屏幕空间的大小



**两个管线**

```fast dispatch```

快速管线的一些参数设置。

```general_dispatch```

通用管线的一些参数设置。

通用管线最大level数量是2，获取当前的levels

```
auto levels = remaining_levels >= max_general_levels ? max_general_levels : remaining_levels;
```

levels为1或者为2。将当前的屏幕尺寸右移levels的单位得到目标（降采样之后）的尺寸。

```
auto dst_width = current_x >> levels;
dst_width = dst_width ? dst_width : 1u;
```

之后在hzb_passes的vector中创建一个pass到尾部（注意hzb_passes存储的是对应的管线pass，hierarchical_z存储的纹理，保存结果用）。



现在要根据生成的层级设置计算着色器中的参数。

```
if (levels == 1) {
    auto samples = dst_width * dst_height;
    auto threads = 128u;
    cmd.work_group_count_x = (samples + threads - 1) / threads;
    cmd.work_group_count_y = 1;
    cmd.work_group_count_z = 1;

    create_and_setup_hzb(*pass, levels, dst_width, dst_height);
}
```

当levels为1的时候，因为在计算着色器的内部分配了（128,1,1）的局部工作组，在这里根据线程数和采样数量计算全局工作组的大小。并调用``` create_and_setup_hzb```函数

```
else {
    auto horizontal_tiles = (dst_width  + 7u) >> 3u;
    auto vertical_tiles   = (dst_height + 7u) >> 3u;
    cmd.work_group_count_x = horizontal_tiles * vertical_tiles;
    cmd.work_group_count_y = 1;
    cmd.work_group_count_z = 1;

    create_and_setup_hzb(*pass, levels-1, current_x >> 1, current_y >> 1);
    create_and_setup_hzb(*pass, levels, dst_width, dst_height);
}
```

如果需要生成两个level。dst记录的是最高层（最终）level纹理的大小。

tiles计算的是需要几个8x的块（水平和垂直独立）这里计算一遍用于分配局部工作组数量，之后在shader中还要计算一遍。

最后向hierarchical_z添加纹理，并在pass中设置大小，level1的大小为右移一位，level2的大小是右移两位（前面计算好了）。



**两个管线的最后：**

```
if (current_level != 0u) {
    util::set_uniform_and_sampler(
        *pass,
        hierarchical_z[current_level - 1].get(),
        "src_texture",
        resource::Sampler::Wrap::clamp_to_edge,
        resource::Sampler::Filter::nearest
    );
}
```

后面还会设置一个sampler用于访问src纹理（前一层纹理）和前面的create_and_setup_hzb中的设置不通，前面是绑定数据输出的image，这里是绑定采样器，用于访问。

**注意**这里第一次有一个来源设置setup_first_depth()获取深度图并设置为src_texture。



**运行的循环主体**

```
hzb_passes.clear();
hierarchical_z.clear();
while (1) {
    auto levels_done = fast_dispatcher();

    if (levels_done == 0) {
        levels_done = general_dispatch();
    }

    SS_ASSERT_WITH(levels_done <= remaining_levels, "Calculation error with levels_done=", levels_done, " and remaining_levels=", remaining_levels);
    current_level += levels_done;
    remaining_levels -= levels_done;
    current_x >>= levels_done;
    current_x = current_x ? current_x : 1u;
    current_y >>= levels_done;
    current_y = current_y ? current_y : 1u;

    if (remaining_levels == 0u) break;
}
```

判断使用快速管线还是通用管线的部分在快速管线中，依据返回值来判断是否成功。

随着循环的进行，尺寸current_xy，current_level，remaining_levels也随之进行变化，当剩余部分处理完毕为0时，表示hzb已经生成完毕，退出循环。

#### shader部分

**preamble.glsl**

先序文件中主要是使用宏定义了一些和hzb层级有关的简单函数，并开启了subgroup的扩展，在后续hzb层级生成的shader中include了该文件。

主要的函数是：

```
#define LOAD_REDUCE4_FROM_TEXTURE(src_coord, out_) \
{ \
    TYPE sample00, sample01, sample10, sample11; \
    LOAD(src_coord, sample00); \
    LOAD(src_coord + ivec2(0, 1), sample01); \
    LOAD(src_coord + ivec2(1, 0), sample10); \
    LOAD(src_coord + ivec2(1, 1), sample11); \
    REDUCE4(sample00, sample01, sample10, sample11, out_); \
}
```

在实现中，一种是快速管线(fastpipeline)，它用来处理贴图像素为2的指数倍的情况，尽可能在一次 Draw Call 调用中去生成尽可能多的层级缓冲，快速管线一 次最多可以生成5个层级的深度缓冲，另一种是通用管线(generalpipeline)，它用来处理快速管线无法处理的情况，即像素（某一行或某一列）为奇数的情况，这里通用管线一次 多可以生成2个层级的深度缓冲。

> 举例来说，对于一张2560×1440的贴图，像素为2^5×2^5的倍数，它会先进行快速管线生成5个层级深度缓冲；然后由于此时最高层级像素为80×45，45为奇数因此会调用通用管线生成2个层级深度缓冲；这时，最高层级像素变为20×11，依然会调用通用管线，生成2个层级深度缓冲；最高层级像素变为5×2，再调用一次通用管线生成最后一个层级的深度缓冲，像素为2×1。这样通过4次DrawCall调用就生成了完整的HZB，相对于普通方案调用10次DrawCall会有不错的性能提升。

生成目标图像的大小在cpu中计算完成。

**hierarchical-z-buffer-fast-comp.glsl**

快速管线

**hierarchical-z-buffer-general-comp.glsl**

通用管线由于奇数所以存在较为复杂的边缘处理情况，难以很好地进行Subgroup的分配，所以这里线程间的通信都会由SharedMemory进行，且一次最多生成2个层级的深度缓冲。

```kernal_size_from_input_size```

根据输入纹理尺寸决定采样核尺寸的大小。如果输入为1，则为1。如果输入为偶数，则为2。如果为奇数，则为3.

```reduce_store_sample```

计算采样核内深度的最大/最小值,将最终值存储到dst_coord对应的dst_level。过程展示如下图：

[]

```intermadiate_level_loop```

中间层的迭代计算

```fill_intermediate_tile```

填充中间层

```fill_last_tile```

填充最后一层

```main```

```
#if LEVEL_COUNT == 1
        ivec2 kernal_size    = kernal_size_from_input_size(SRC_TEXTURE_SIZE());
        ivec2 dst_image_size = IMAGE_LEVEL_SIZE(0);
        ivec2 dst_coord      = ivec2(int(gl_GlobalInvocationID.x) % dst_image_size.x,
                                     int(gl_GlobalInvocationID.x) / dst_image_size.x);
        ivec2 src_coord = dst_coord * 2;

        if (dst_coord.y < dst_image_size.y) {
            reduce_store_sample(src_coord, false, kernal_size, dst_coord, 0);
        }
```

这里需要**注意**的是```if (dst_coord.y < dst_image_size.y)```丢弃了多余线程的计算，进行了一个**边界检查**

> 单level处理例子：

[]

```
#else // handle two levels
        // Assign a 8x8 tile of mip level 2 to one workgroup.
        ivec2 level2_size = IMAGE_LEVEL_SIZE(1); 
        ivec2 tile_count;
        tile_count.x = int(uint(level2_size.x + 7) >> 3u);
        tile_count.y = int(uint(level2_size.y + 7) >> 3u);
        ivec2 tile_index = ivec2(gl_WorkGroupID.x % uint(tile_count.x),
                                 gl_WorkGroupID.x / uint(tile_count.x));

        bool bounds_check = (tile_index.x >= tile_count.x - 1) || (tile_index.y >= tile_count.y - 1); // 1

        fill_intermediate_tile(tile_index * 2 * ivec2(8, 8), bounds_check);
        barrier();
        fill_last_tile(tile_index * ivec2(8, 8), bounds_check);
    #endif
```

这里的level2_size是最终（也就是第二层）的尺寸大小，并根据它来计算8xtile的数量，获得tile的index，这里要进行一个**边界检查**和上面一样防止多余线程计算导致的数据错误。

先对中间层进行处理fill_intermediate_tile。这之后中间层已经存储在shared uniform中了，在后续访问中可以从共享内存中拿来提升速度。

经过一个并发阻断后。

最后填充最终层（最高层。

### screen_space_ray_tracing_pass

---

这部分主要是实现屏幕空间的光线步进(Ray Marching)过程。并在这里完成了重要性采样相关pdf的计算。

**ray-tracing-frag.glsl**

计算屏幕空间每个点对应的反射点hit_pos,并将其保存

最后输出为ssr_pos_pdf_texture，存储的是vec(hit_pos, pdf)

### resolve_pass

---

从上一个pass中拿到hit_pos的信息，在这一个pass中进行着色。

![image-20241121142629393](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20241121142629393.png)

**resovle-frag.glsl**

最后输出为ssr_resolve_texture

```
result    = 0.0
weightSum = 0.0
for pixel in neighborhood:
	weight = localBrdf(pixel.hit) / pixel.hitPdf
	result += color(pixel.hit) * weight
	weightSum += weight
result /= weightSum
```

如果pdf<0则表明未击中，输出ibl_specular即可。如果开启了ssr，在ocean-frag中对specular项和其他项做了分离，这里framebuffer中的color是不包含ibl的。

```
if (reflection_mode == SCREEN_SPACE_REFLECTION) {
    indirect_specular = vec4(reflection * shading_data.reflection_strength, 1.0);
} else {
    shading_result.specular += reflection * shading_data.reflection_strength;
}
```

如果击中：

```
fragment_color = vec4(mix(indirect_specular_res.rgb, accum_color * FG * max(1.0, intensity), screen_edge_fade * min(1.0, intensity)), 1.0);
```

对两个部分做一个mix

### combine_pass

---

这部分主要是输出最后的结果。

```
auto setup_combine_pass = [&] {
    combine_pass.set_uniform("ssr_resolve_tex", &ssr_resolve_texture);

    combine_pass.framebuffer.colors.resize(1);
    combine_pass.framebuffer.colors[0].texture = io.out_color;
};
```

这里要有一个和原有帧缓冲混合的设置blend_state

**combine-frag.glsl**

```
void main()
{
    out_result = vec4(texture(ssr_resolve_tex, tex_coord).rgb, 1.0);
}
```

把ssr_resolve_texture纹理的内容，输出到out_color端口。
