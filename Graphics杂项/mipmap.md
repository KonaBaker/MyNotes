## mipmap实现

每一层是上一层downsample + filter得到的，选一种卷积核。`glGenerateMipmap`并不要求具体实现，所以更深入的讨论应该找具体的驱动。

**逐级blit**:
gallium/mesa采用的是这种方法，从base_level+1一直到last level使用的是硬件的缩放filter。

此时如果采用linear那么就是邻近像素做加权平均。

**非整数倍的问题**

卷积核：lanczos/kaiser

**数据流向**

每一次都要读写显存，走图形管线。主要使用texture cache没有显式的sharedmemory和LDS进行复用。

## compute shader mipmap

传统的cs做法是多次dispatch，每一个层级dispatch，然后barrier，并且会使用L2 cache甚至主内存。

### intro

**nvidia**采取了一种新的方法：

> NVIDIA Vulkan Compute Mipmaps Sample [见strategy.md]

- 一级mipmap的输出可以立即用作下一级mipmap的输入，在单次dispatch中连续生成多个层级，最小化同步的开销，减小barrier的使用（每N个层级使用1个barrier）
- 并且可以保存到 shared memory/L1 cache甚至是register file。通过shuffle操作给另一个warp的core。减少访存的开销。

### 两种管线

`NVPRO_PYRAMID_IS_FAST_PIPELINE`

- Fast pipeline shader: 高效处理2的次幂情况，处理偶数且支持subgroup shuffle的情况，每个线程最多处理6级。

  生成M个层级，要求输入层级能被均匀划分为$ {2^M} * {2^M} $的tile
- General Pipeline shder: 负责处理剩下的，最多只能处理2级。消耗更高。如果处理过程中又满足Fast Pipeline条件就又回去。

不要求在single pass中生成所有层级，如果single dispatch无法覆盖所有level则会发出更多的dispatch。

这样做的一个**好处**是，快速管线可以用于其原始 2 的幂次方用例之外的情况：如果基础 mip 层级具有偶数维度（但不一定是 2 的幂次方），快速管线可用于生成前几个 mip  层级（数据主体所在之处），而通用管线仅用于填充 mipmap 金字塔相对微小的“顶部”。例如：

- Image size 1920×1080: Divide into 8×8 tiles, fill the first 3 levels  using `fastPipeline`, then switch to `generalPipeline`. 
  图像尺寸 1920×1080：划分为 8×8 的图块，使用 `fastPipeline` 填充前 3 个层级，然后切换到 `generalPipeline` 。
- Image size 2560×1440: Divide into 32×32 tiles, fill the first 5 levels  using `fastPipeline`, then switch to `generalPipeline`.
  图像尺寸 2560×1440：划分为 32×32 的图块，使用 `fastPipeline` 填充前 5 个层级，然后切换到 `generalPipeline` 。

### fast pipeline

### general pipeline

https://zhuanlan.zhihu.com/p/419644293

https://github.com/nvpro-samples/vk_compute_mipmaps/blob/main/docs/strategy.md.html

## one pass mipmap（SPD)

https://zhuanlan.zhihu.com/p/18186390357

wave ops + LDS

### 其他问题

mipmap需要额外占用约1/3的空间



---

shuffle操作只能在一个warp中么，还是一个Block内的不同Warp都可以。
