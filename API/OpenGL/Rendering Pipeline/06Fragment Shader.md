# Fragment Shader

负责将**光栅化生成的fragments**处理为**一组colors**和**a single深度值**。

每个fragments包含：

- window-space pos
- few other values
- 插值后的顶点处理阶段output

经过处理后，fs输出：

- 一个深度值
- 一个可能的stencil value
- 0个或者多个颜色值(maybe draw into framebuffer)

fs接收一个fragment，输出一个fragment。

## optional

如果不使用fs(program/pipeline没有fragment shader stage)，光栅化仍然发生，片元仍然产生，depth/stencil test还照常进行。那么color是未定义的，depth 和 stencil和输入保持一致。

用处：

- 不填充color buffer，只填充depth buffer
- depth pre-pass，相当于软件early-z
- shadow mapping 

典型的shadowmap pass:

- 绑定一个只有 depth attachment 的 FBO
- `glNamedFramebufferDrawBuffer(fbo, GL_NONE);`
- `glNamedFramebufferReadBuffer(fbo, GL_NONE);`
- 只用 VS（有时加 GS/TES）
- 不用 FS

## special operations

1. 硬件通常以 **2x2 fragment quad** 为单位执行 fragment shader。fs会自动生成window-space导数dFdx\dFdy，记录uv变化了多少，可以使用大多数纹理函数。在其他stage一般无法使用texture这种可以自动推断的函数，需要使用textureLod texelFetch这种显式的。

2. discard，使用后会抛弃这个片段的输出值(color\depth\stencil及后续定义的output)，不会进入后续的管线阶段。

   但是在某些系统中，因为硬件同步执行的原因，discard之后可能会持续执行指令（discard之前的操作仍然生效。不进入后续管线），**此时需要确保discard之后的image store、atomic Counter、SSBO的写入失效。**（这句话是对驱动实现的限制说明）

   >逻辑语义层面，discard 之后，这个 fragment 已经结束，后续代码不应被当成“有效 GLSL 结果”去依赖

3) `layout(early_fragment_tests) in` early test。一些光照计算以及store/load的操作是比较耗时的。

## Inputs

### system inputs

内置的变量

```c++
in vec4 gl_FragCoord;
in bool gl_FrontFacing;
in vec2 gl_PointCoord;
```

- `gl_FragCoord`

表示片段在window-space中的位置，如果gl_FragDepth未在fs中写入，则这个window-space的z值会被写入到depth buffer中。

xy值是通过`glViewPort`调整，范围是[0,screensize]  `vec2 uv = gl_FragCoord.xy / resolution;`经常会看到这种归一化操作。

且xy可能不是整数，代表的是片元的中心(0.5, 0.5).

z值是通过`glDepthRange(n, f)`调整，范围是[n,f],一般为[0,1]

它的w分量是1/w_clip。来自顶点裁剪空间位置 `gl_Position.w` **插值**得到的那个齐次 `w_clip`。

**注意**不是某个顶点的w_clip而是经过插值的w_clip。【详见w推理】

还可以指定别的qualifier重新声明如：

`layout(origin_upper_left, pixel_center_integer) in vec4 gl_FragCoord;`

`origin_upper_left`改变window的坐标原点。

`pixel_center_integer`按整数解释(0,0)不再是(0.5,0.5)

- `gl_FrontFacing`

该片段由primitive的背面生成就是fasle，否则为true 

- `gl_Pointcoord`

```c++
// for multisample
in int gl_SampleID;
in vec2 gl_SamplePosition;
in int gl_SampleMaskIn[];
```

- `gl_SampleMaskIn[]`

每一个索引是一个32位的bitmask，length是ceil(s/32),s是支持的最大sample数。如果是4xMSAA

那么`gl_SampleMaskIn[0] == 0b1011` bit0~3 = 1101

> 例子：
>
> ```c++
> #version 400 core
> 
> layout(location = 0) out vec4 outColor;
> 
> void main()
> {
>     int mask = gl_SampleMaskIn[0];
> 
>     int count = 0;
>     for (int i = 0; i < 32; ++i)
>     {
>         if ((mask & (1 << i)) != 0)
>             count++;
>     }
> 
>     float intensity = count / 4.0;   // 假设当前是 4x MSAA
>     outColor = vec4(intensity, intensity, intensity, 1.0);
> }
> ```
>
> 根据coverage调整亮度。最终效果，几何边缘会更暗。

- `gl_SampleMask[]`

`gl_SampleMask[0] = 0b0101` 会和input做AND运算 `1111 & 0101 = 0101`. 只能"关"，不能"开"。

- `gl_SampleID`

current sample。**使用会导致fs per-sample运行。**

- `gl_SamplePosition`

sample在pixel中的位置[0,1]，左下角原点。**使用会导致fs per-sample运行**

```c++
in float gl_ClipDistance[];
in int gl_PrimitiveID;

// for geometry shader
in int gl_Layer;
in int gl_ViewportIndex;
```



## outputs

输出类型可以是float\integers\vector of them\array of them。user-defined的输出变量不能聚合到interface block中

### output buffers

user-defined的output会被输出到framebuffer指定的drawbuffer中。

`layout(location = 3) out vec4 diffuseColor;`

location指定drawbuffer的索引。

如果drawbuffer的某一个索引的位置没有存储color attachment也就是`GL_NONE`，被写入的值就会被丢弃。

### 双源混合

### other outputs

内置输出

`out float gl_FragDepth;`

表示fragment的深度值。如果未**静态写入**则采用gl_FragCoord.z的值。

**静态写入**：在代码中出现，即使是不可达。此时fragment shader的深度值由你负责提供。

**warning**：所以说如果说某一个分支存在了静态写入，则在其他位置也必须保证有静态写入。因为静态写入如果只在某些条件下才发生的话，那么对于另外一些条件（也就是没有发生静态写入的条件下）因为已经存在了静态写入，所以不会自动采用gl_FragCoord值。不遵循将会导致ub。

`layout (depth_<condition>) out float gl_FragDepth;`

写入gl_FragDepth可能会导致关闭early-z。写明`depth_<condition>`可以在某些情况下不必关闭。

- any
- greater
- less
- unchanged

如果违反此条件会导致ub。

`out int gl_SampleMask[];`

执行多重采样渲染时片段的样本掩码。如果没有静态写入，则有`gl_SampleMaskIn`填充。这里的samplermask会和光栅化计算的sampler mask进行AND操作。

warning同上。
