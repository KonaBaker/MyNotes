## intro

combined image sampler是一种descriptor，这中descriptor可以使得shader能够通过sampler object来访问image资源。

除了combined还有两种独立的：

<img src="../assets/image-20260413112152021.png" alt="image-20260413112152021" style="zoom: 50%;" />

- `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER`

sampler和image组合成一个descriptor。

- `VK_DESCRIPTOR_TYPE_SAMPLER` ＋ `VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE`

sampler和image绑定到不同的binding，属于不同的descriptor。例如：

```c++
layout(set = 0, binding = 0) uniform sampler       smpLinear;   // 只是采样参数
layout(set = 0, binding = 1) uniform sampler       smpNearest;  // 另一套采样参数
layout(set = 0, binding = 2) uniform texture2D     texA;        // 只是图像数据
layout(set = 0, binding = 3) uniform texture2D     texB;        // 另一张图像

void main() {
    // 关键：用 sampler2D() 在运行时"临时组合"
    vec4 colorA_linear  = texture(sampler2D(texA, smpLinear),  uv);
    vec4 colorA_nearest = texture(sampler2D(texA, smpNearest), uv); // 同一张图，不同采样
    vec4 colorB_linear  = texture(sampler2D(texB, smpLinear),  uv); // 不同图，同一采样器
}
```

整个流程 = 修改descriptor set layout -> descriptor pool -> descriptor set ->shader

## update the descriptors

1) 在layout中增加binding
2) 在pool中增加资源

​	vulkan 1.1以后如果pool不够大，在分配set的时候会返回错误代码，也可能驱动内部解决(分配大于我们描述的分配)，这取决于具体分配。这也意味着vulkan将分配的责任转移给了驱动程序。但是要求写的时候最好还是严格匹配某种descriptor type的数量。

3) 最后就是分配set并绑定资源，对于combined sampler绑定的是image(view)资源，需要imageInfo

**<font color = ligblue> Notes: </font>**

其实这里的做法不是很好，应该根据频率分成不同的set。按照工业界普遍原则：

```c++
Set 0 ── Global / Scene     最稳定，每帧绑定一次
Set 1 ── Per-pass           每个渲染 pass 切换一次  
Set 2 ── Per-material       每次换材质时切换
Set 3 ── Per-object         每个物体切换（或直接用 push constant）
```

这里的频率的gpu bind频率，而不是cpu写入频率，例如对于相机变换矩阵等，虽然cpu每帧都要写入，但是所有drawcall会共用，只bind一次。对于texture sampler可能每个材质变换都要绑定一次，descriptor set layout.

这里的set划分是由于多draw call且可能存在共用的情况导致的，本质上是在解决一个**多 draw call 之间的复用问题**。如果是单drawcall，那么每个set都只bind一次，这里的区别就只有cpu写入频率了。

## texture coord

需要修改vertex结构体中的attribute。以及添加数据。

## shaders

增加vertex中的attribute。

声明sampler2D.调用Sample



