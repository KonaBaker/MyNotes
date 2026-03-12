RHI:

```c++
void RenderWater() {
    #ifdef VULKAN
        vkCmdDraw(...); // 写一大堆 Vulkan 代码
    #elif defined(DX12)
        commandList->DrawInstanced(...); // 写一大堆 DX12 代码
    #endif
}
```

类似这中就是RHI引擎逻辑和api调用的接口层。

RHI会封装这些#if else。一般来说由引擎实现。

一般用于跨平台。

**RenderGraph(RDG)**

在RHI之上的一个高层架构。管理资源的生命周期

一种基于**有向无环图**的数据结构与调度系统。Node代表pass,edge代表resource。

- setup/compile 构建出一张图。构建的过程中，可能会合并资源、剔除pass等等优化操作。
- execute 插入barrier,按照拓扑排序，调用RHI进行渲染

fxg就是data-drive的render graph

从硬编码抽象成配置文件。

**memory aliasing**

负责资源（不是某一块显存）的生命周期分析，决定何时创建，复用或者销毁。

它通常会得出一个结果：
 “这几个 transient texture/buffer 生命周期不重叠，可以复用同一块 backing memory。”

同一块物理内存，在不同时间段，拥有着不同资源。这能极大地降低显存峰值（通常能节省 30% - 50% 的 VRAM）。

**注意：**

render graph不参与具体显存操作。真正向驱动申请大块显存，分配，pool管理以及碎片控制的是**GPU资源分配器**/**显存池层**

- vulkan有自己实现的allocator
- d3d有 heap allocator

```c++
Render Graph
  -> 计算资源生命周期 / alias 机会 / transient 复用
  -> 向 Resource Allocator 请求 backing allocation
       -> Resource Allocator 再调用 VMA / D3D12MA / 自研 pool
            -> API / Driver 真正分配 VkDeviceMemory / D3D12 Heap
```

- **Render Graph 决定“能不能复用、何时复用”**

- **Allocator 决定“这块内存怎么切、怎么池化、怎么对齐、怎么回收”**



**resource barrier**

不同pass之间的barrier，以及同步。自动插入。

不同drawcall之间是glmemorybarrier也可以是不同pass之间的调用，是API级别的



pros:

- 不需要关心显存池和不同pass之间的同步
- 自动剔除dead node
- 简单可配置

cons:

- 每帧需要编译这张图。这张图的构建耗时（一般有缓存，拓扑发生变化的时候重新编译）

  

https://zhuanlan.zhihu.com/p/425830762