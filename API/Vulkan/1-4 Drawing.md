# Drawing

## Framebuffers&dynamic rendering

在之前我们需要创建framebuffers去把image views绑定到render pass。现在dynamic rendering允许我们直接渲染到image views，无需framebuffer和render pass。

`vk::RenderingAttachmentInfo`指定attachment

`vk::RenderingInfo`指定渲染参数

## Command Buffers

与opengl不同，drawcall以及一些内存操作，不是直接通过函数调用来执行，而是将操作记录在command buffer中。所有命令到最后一起提交。还可以多线程进行。

### command pool

command pool是用来管理存储buffer的memory的，command buffer也是从pool中分配的

```c++
CommandPool
├── CommandBuffer A  [cmd1, cmd2, cmd3...]
├── CommandBuffer B  [cmd1, cmd2...]
└── CommandBuffer C  [cmd1...]
```

```c++
vk::raii::CommandPool commandPool = vk::raii::CommandPool(device, poolInfo);
```

同样的它也需要createInfo，需要两个参数

- `.flags` 标志位
  - `VK_COMMAND_POOL_CREATE_TRANSIENT_BIT` command buffer会频繁的记录新命令（buffer生命周期很短），从而驱动可以优化分配策略，比如堆分配。
  - `VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT`  poll会使用更复杂的内存管理策略，可以单独重置某一个command buffer

如果不带任何flag，pool管理方式类似一个线性allocator,重置的话只能全部reset

```c++
vkResetCommandPool(device, commandPool, 0);
vkResetCommandBuffer(commandBufferA, 0); // ❌ 行为未定义或报错
```

上述两个flag可以同时使用。

- `.queueFamilyIndex`

需要将commandbuffer中的命令提交到device queues中，pool里面的所有buffer只能提交到一种queue（不是一个）。所以这里需要指定一个queue family

### command buffer allocation

```
vk::raii::CommandBuffer commandBuffer = std::move(vk::raii::CommandBuffers(device, allocInfo).front());
```

commandBuffers是可以一次分配多个的。

同样需要allocateInfo

- `.commandPool` 指定pool
- `.level` 
  - `VK_COMMAND_BUFFER_LEVEL_PRIMARY`  primary cmd buffer 可以直接提交到queue执行
  - `VK_COMMAND_BUFFER_LEVEL_SECONDARY `secondary cmd buffer 只能被primary调用执行

1) 可以复用命令：假设场景里有 100 个物体都用同一套命令绘制，可以把这套命令录制成一个 secondary command buffer，然后在 primary 里多次调用，避免重复录制。

2) 多线程：Vulkan 的 Command Buffer 录制本身是 CPU 端操作，单线程录制大量命令会成为瓶颈。Secondary Command Buffer 允许你把录制工作拆分到多个线程：

   ```c++
   主线程 (Primary CB)
   ├── Thread 1 → 录制 Secondary CB A（场景几何体）
   ├── Thread 2 → 录制 Secondary CB B（UI）
   ├── Thread 3 → 录制 Secondary CB C（粒子）
   └── 汇总：vkCmdExecuteCommands(primary, {A, B, C})
   ```

- `commandBufferCount`

### command buffer recording

