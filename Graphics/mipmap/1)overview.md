# mipmap

## mipmap 生成

- blit
- compute
  - nvpro_pyramid
  - unity/DirectX
- AMD SPD

## mipmap 基础

### 概念

mipmap 是纹理的多级缩小版本序列，level 0 是原图，之后每一层的宽高通常都缩小为上一层的一半。它的主要目的是解决纹理缩小时的走样问题，并降低采样开销。因为一个屏幕像素在远处往往对应原纹理上的很多 texel，如果仍然直接采原图，就容易出现闪烁、摩尔纹等 aliasing。

**各向异性**

各向异性过滤是普通 mipmap 的改进。普通 mipmap 用单一 lod 近似一个像素在纹理空间的 footprint，适合 footprint 接近各向同性的情况；但斜视表面时 footprint 往往是细长的，单个 lod 会导致**长轴方向 aliasing** 或**短轴方向过度模糊**。各向异性过滤会根据纹理坐标梯度估计 footprint 的主轴和长宽比，沿长轴增加采样，从而在倾斜表面上获得更清晰稳定的贴图效果。

2x 4x之类的都是长宽比。

### mipmap lod 层级计算

```C++
vec2 dudx = dFdx(uv); // dFdx(uv) = uv(x+1, y) - uv(x, y)近似差分，左右两个像素的uv差值。
vec2 dudy = dFdy(uv);
vec2 dx = dudx * vec2(W, H);
vec2 dy = dudy * vec2(W, H);
float rho = max(length(dx), length(dy));
float lod = log2(rho);
```

mipmap 层级的核心是看当前一个屏幕像素在纹理空间覆盖了多大区域。在 shader 里通常通过纹理坐标对屏幕坐标的偏导数 `dFdx`、`dFdy` 来估计这个覆盖范围。 如果纹理大小是 `W,H`，先把导数换算到 texel 空间，再取 `rho = max(length(dudx * texSize), length(dudy * texSize))`， 然后 `lod = log2(rho)`。 `lod=0` 表示用原始纹理，`lod=1` 表示用 1/2 分辨率那层，以此类推。 硬件通常在 fragment quad 上自动求导，普通 `texture()` 会自动算 LOD； 软光栅则需要自己算属性导数、自己做 mip 选择和 trilinear 插值。

**Notes**:

1. 只有在fragment shader里面这样才可以，因为dFdx依赖相邻像素信息，而fragment shader是以2x2quad为一组进行计算的。

2. 这里的uv不能在屏幕空间插值，因为透视除法过了，对于顶点属性，应该进行透视矫正，在原3D空间进行插值。主要用于自己做光栅化的时候：
   插值

   ```
   u / w
   v / w
   1 / w
   ```

   ```
   u = (u/w) / (1/w)
   v = (v/w) / (1/w)
   ```

### Bilinear Filter

```
纹素索引:   0       1       2       3
           ├───────┼───────┼───────┼───────┤
纹素中心:  0.5     1.5     2.5     3.5
```

```c++
float x = uv * texture_size - 0.5;
int x0 = floor(x); // 整数索引用于去内存取值。
int x1 = x0 + 1;
float s = x - x0;
float t = y - y0;
result = (1-s)(1-t)·C00 + s(1-t)·C10 + (1-s)t·C01 + s·t·C11
```

**硬件实现**

GPU对双线性过滤由专门的硬件单元，由极低的延迟（通常1~4个时钟周期）。

输入uv坐标，计算相关参数，从L1 Texture cache(不同于L1 Data Cache)中取texture,并行读取4个texel(在统一cache line内)，之后做bilinear。

相关参数使用的是定点数存储（用整数来表示小数）

8-bit定点：

```
s = 0.7  →  存储为  round(0.7 × 256) = 179
s = 0.5  →  存储为  128
s = 0.0  →  存储为  0
s ≈ 1.0  →  存储为  255  （最大，不到 1.0）
```

**对比**

手动在shader中做，texelFetch，不一定并行，依赖指令发射，以及纹理请求的队列是否有空位。即使并行了也有指令发射和寄存器的开销。

而硬件实现就只有一条指令，无寄存器占用，特定的优化。

**trilinear**

就是先在两层mip各做bilinear，再在mipmap层间进行插值。

### 其他问题

mipmap需要额外占用约1/3的空间. Mipmap 内存占用 =  M/4 + M/16 + M/64 + ... 

---

**Notes**

nvpro_pyramid是一个库，是一个vulkan方案。提供了shader和dispatch的代码，定义相关宏，在vulkan程序中调用。不属于驱动范畴。

vulkan或者DX12是没有像`glGenerateMipmap`这样直接生成的API的。所以在vulkan中的常见做法是使用`vkCmdBlitImage`逐级生成的。如果想要更高效，就需要自己写shader或者调用库。微软也写了这样一个mipmap生成方案。

opengl规范中写明了`glGenerateMipmap`那么这个API就需要驱动/厂商进行实现。

像unity这种引擎可以调用后端API生成，其也会自己在上层自己封装，自己实现一个mipmap的生成方法。



