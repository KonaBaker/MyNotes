### mipmap实现

每一层是上一层downsample + filter得到的，选一种卷积核。`glGenerateMipmap`并不要求具体实现，所以更深入的讨论应该找具体的驱动。

**逐级blit**:
gallium/mesa采用的是这种方法，从base_level+1一直到last level使用的是硬件的缩放filter。

此时如果采用linear那么就是邻近像素做加权平均。

**非整数倍的问题**

卷积核：lanczos/kaiser

**数据流向**

每一次都要读写显存，走图形管线。主要使用texture cache没有显式的sharedmemory和LDS进行复用。

### compute shader mipmap

- multipass compute:

每个mipmap level一个dispatch。读上一个level，然后写下一个level，需要memory barrier保证可见性。

**数据流向**：
上一层mip VRAM -> l2 -> l1 ->shared memory做reduce -> l1 -> l2 -> VRAM。

缺点：多次dispatch barrier，重新读写显存。

优点：preload footprint 到 shared memory。会用LDS

- cache-aware



### one pass mipmap（SPD)

wave ops + LDS

### 其他问题

mipmap需要额外占用约1/3的空间
