# Drawing

## Framebuffers&dynamic rendering

在之前我们需要创建framebuffers去把image views绑定到render pass。现在dynamic rendering允许我们直接渲染到image views，无需framebuffer和render pass。

`vk::RenderingAttachmentInfo`指定attachment

```C++
vk::RenderingAttachmentInfo attachmentInfo = {
    .imageView   = swapChainImageViews[imageIndex],
    .imageLayout = vk::ImageLayout::eColorAttachmentOptimal,
    .loadOp      = vk::AttachmentLoadOp::eClear, // 渲染前对image的操作
    .storeOp     = vk::AttachmentStoreOp::eStore, // 渲染后对image的操作
    .clearValue  = clearColor};
```

`vk::RenderingInfo`指定渲染参数

```c++
vk::RenderingInfo renderingInfo = {
    .renderArea           = {.offset = {0, 0}, .extent = swapChainExtent},
    .layerCount           = 1,
    .colorAttachmentCount = 1,
    .pColorAttachments    = &attachmentInfo};
```

**尺寸**：

- swapChainExtent是swapChain中image的尺寸（像素的），几乎所有情况等于窗口的尺寸，对于高ddi相应变大。
- renderArea 是只在这个区域内干活：load/store，只对这个范围内的坐标生效。所有渲染**must**在这个区域内，画到外面是ub。例如tile-based会局部更新脏区域。
- viewport 定义了从image（ndc空间）到framebuffer（attachment上）的坐标变换

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
  - `VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT`  poll会使用更复杂的内存管理策略，可以单独重置某一个command buffer。单个buffer的内存在reset的时候不会被回收。

如果不带任何flag，pool管理方式类似一个线性allocator,重置的话只能全部reset。

reset并不会重新分配内存。

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

````c++
commandBuffer->begin({})
````

这里需要指定一个`vk::CommandBufferBeginInfo` 

- `.flags`表明我们如何使用cmd buffer(usage)
  
  - `eOneTimeSubmit` submit完之后直接invalid(内存没有回收需要reset后使用），不会复用。避免驱动为复用产生一些额外工作。
  
    如果不设置这个，submit之后回到executable，理论上可以复用，但是由于image index的变化等等，复用不太实际，而且command buffer record的开销其实不是很大。
  - `eRenderPassContinue` 仅用于secondary cmd buffer。会在rendering之间调用
  - `eSimultaneousUse` 可以在待执行状态重新提交。可以在queue中排队多次。如果不加，则只能执行完再次提交。

### image layout transitions

```c++
void transition_image_layout(
	    uint32_t                imageIndex,
	    vk::ImageLayout         old_layout,
	    vk::ImageLayout         new_layout,
	    vk::AccessFlags2        src_access_mask,
	    vk::AccessFlags2        dst_access_mask,
	    vk::PipelineStageFlags2 src_stage_mask,
	    vk::PipelineStageFlags2 dst_stage_mask)
{
		vk::ImageMemoryBarrier2 barrier = {
		    .srcStageMask        = src_stage_mask,
		    .srcAccessMask       = src_access_mask,
		    .dstStageMask        = dst_stage_mask,
		    .dstAccessMask       = dst_access_mask,
		    .oldLayout           = old_layout,
		    .newLayout           = new_layout,
		    .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
		    .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
		    .image               = swapChainImages[imageIndex],
		    .subresourceRange    = {
		           .aspectMask     = vk::ImageAspectFlagBits::eColor,
		           .baseMipLevel   = 0,
		           .levelCount     = 1,
		           .baseArrayLayer = 0,
		           .layerCount     = 1}};
		vk::DependencyInfo dependency_info = {
		    .dependencyFlags         = {},
		    .imageMemoryBarrierCount = 1,
		    .pImageMemoryBarriers    = &barrier};
    commandBuffer.pipelineBarrier2(dependencyInfo);
}
```

### dynamic rendering

```c++
vkBeginCommandBuffer(...)    // ← 开始"录制"命令到 command buffer
    vkCmdBeginRendering(...) // ← 在录制期间，开始第一个pass
    vkCmdDraw(...)
    vkCmdEndRendering(...)
    
    vkCmdBeginRendering(...) // ← 在录制期间，开始第二个pass
    vkCmdDraw(...)
    vkCmdEndRendering(...)
vkEndCommandBuffer(...)      //← 结束录制
```

一次录制期间是可以有多个pass的

1) 在rendering attachment info中设置color attachment

2) 设置rendering info

3) commandBuffer->begin

4) 进行layout转换，将swapchain中的image转换为color attachment **// barrier命令**

5) **commandBuffer.beginRendering(renderingInfo)**

6) 绑定graphics pipeline `commandBuffer.bindPipeline(vk::PipelineBindPoint::eGraphics, *graphicsPipeline);`

7) 设置viewport和scissor(如果在pipeline中设置了动态的话)

8) drawcall

   `commandBuffer.draw(3, 1, 0, 0)`

   - `vertexCount`
   - `instanceCount` 默认1不启用
   - `firstVertex` offset
   - `firstInstance `offset

9) **commandBuffer.endRendering()**

10) layout转换到present **// barrier命令**

11) commandBuffer->end

使用的是raii，无需显示清理，command pool销毁时，command buffer自动销毁。

## rendering

写主循环drawcall。

```c++
void mainLoop()
{
    while (!glfwWindowShouldClose(window)) {
        glfwPollEvents();
        drawFrame();
    }
}
```

1) 等待前一帧完成
2) 从swap chain获取image
3) record cmd buffer 准备绘制到image上。
4) submit cmd buffer
5) present swapchain上的image

### 同步

vulkan API很多调用都是异步的，没有完成就返回了(GPU上继续运行，CPU不发生阻塞）。我们需要显式同步,定义操作顺序,例如：

- 从swap chain获取image
- 执行drawcall
- present到屏幕上，并将image还给swap chain

**semaphores**

使用的是**binary semaphore**，只有两种状态unsignaled(默认) & signaled **指定GPU操作之间的执行顺序**

可以为queue中的任务排序，以及不同queue之间协调。

```C++
vk::raii::CommandBuffer A, B = ... // record command buffers
vk::raii::Semaphore S = ...        // create a semaphore

// enqueue A, signal S when done - starts executing immediately
queue.submit(work: A, signal: S, wait: None)

// enqueue B, wait on S to start
queue.submit(work: B, signal: None, wait: S)
```

semaphores会自动重置为unsignaled(例如：在queueB开始执行之后)

**fence**

其主要在于协调CPU上的执行顺序。当主进程需要知道GPU何时完成某项任务的时候，使用fence。**保持CPU与GPU之间的同步**

同样分为signaled和unsignaled两种状态。

任务上带fence,任务完成以后，主进程会继续运行。（主进程会阻塞）

例子：

```C++
vk::raii::CommandBuffer A = ... // record command buffer with the transfer
vk::raii::Fence F = ...         // create the fence

// enqueue A, start work immediately, signal F when done
queue.submit(work: A, fence: F)

device.waitForFences(F) // blocks execution until A has finished executing

save_screenshot_to_disk() // can't run until the transfer has finished
```

fence不会自动重置，需要手动重置。

**fence vs semaphores**

等待前一帧完成使用fence

交换链操作使用semaphores

### 同步对象

```c++
vk::raii::Semaphore presentCompleteSemaphore = nullptr; // 从swap chain拿image
vk::raii::Semaphore renderFinishedSemaphore  = nullptr; // 渲染已经完成之后进行present
vk::raii::Fence     drawFence                = nullptr; // 确保一次只渲染一帧
```

两个对象同样需要createInfo。但是目前版本semaphore的info中没有字段。仅需要填写fence的。

### 等待前一帧

```c++
void drawFrame()
{
    auto fenceResult = device.waitForFences(*drawFence, vk::True, UINT64_MAX); // (drawFence_array, isAnyOrAll, maxWaitTime);
    if (fenceResult != vk::Result::eSuccess)
    {
        throw std::runtime_error("failed to wait for fence!");
    }
    device.resetFences(*drawFence);
}
```

为了公用的semaphores以及cmdbuffer可以在这一帧使用。

### 从 swapchain获取image

```C++
auto [result, imageIndex] = swapChain.acquireNextImage(UINT64_MAX, *presentCompleteSemaphore, nullptr); //(time, semaphore_to_be_signaled, fence_to_be_signaled);
```

之前帧present占用的image和当前获取image之间的同步是swapchain自带的，presentation engine会自行查询哪个image空闲、繁忙。如果占用，就会阻塞。

### 记录cmd buffer

```c++
recordCommandBuffer(imageIndex);
```

### submit cmd buffer

```c++
vk::PipelineStageFlags waitDestinationStageMask( vk::PipelineStageFlagBits::eColorAttachmentOutput );
```

需要填写`submitInfo`,包括：

- wait semaphore的信息
  - `pWaitDstStageMask` 指定同步的阶段，semephore并不是整个submit都等，而是当到了submit中的某一个阶段才会去等这个信号。比如这里我们等的是swapchain交换来的image,我们在写attachment的时候才需要这个image，所以在这个阶段等就可以了。
- cmd buffer信息
- 唤醒的semaphore信息

最后

```c++
queue.submit(submitInfo, *drawFence);
```

### presentation

```c++
const vk::PresentInfoKHR presentInfoKHR{
    .waitSemaphoreCount = 1,
    .pWaitSemaphores    = &*renderFinishedSemaphore,
    .swapchainCount     = 1,
    .pSwapchains        = &*swapChain,
    .pImageIndices      = &imageIndex};
result = queue.presentKHR(presentInfoKHR);
```

呈现然后还回去

```c++
device.waitIdle();
```

关闭窗口后等待队列中的操作完成。

## frames in flight 

“frame in flight"是指已经被cpu提交给gpu，但是gpu还没有渲染完的帧”。

我们现在必须等待前一帧的完成，才能开始渲染下一帧。我们可以上cpu提前准备，不同帧并行运行，这就需要让所有在渲染中被访问和修改**的资源**都有副本（因为多个帧都要用）。所以我们需要更多的cmd buffers\semaphores\fences。

```c++
constexpr int MAX_FRAMES_IN_FLIGHT = 2;
```

通常情况下设置为两帧就足够了。如果数值过大，可能增加gpu负载，cpu跑得过快，CPU 在 GPU 还在渲染第 1 帧的时候，就已经准备好了第 2、3、4 帧的命令。这样会增加帧延迟。

**Notes**

提前准备确实会增加**吞吐量（每秒帧数）**，即cpu和gpu一直在算，流水线处于满载状态，FPS肯定是高的。但是会增加**帧延迟**，也就是说cpu在准备每一帧的时候会读取用户/玩家的输入，然后基于这个输入计算游戏状态。如果只使用1frame in flight，帧渲染完成之前，cpu就会等着，不会读入输入。准备开始渲染这一帧的时候再读入，那么你输入和你看到画面的之间的延迟就是帧渲染的时间。如果使用过大的frame in flight，那么你输入和你看到画面之间的延迟，可能已经隔了好几帧了。**“操作手感更加黏滞”**

我们需要把semaphore\fences\cmdbuffer全部用`std::vector`存储。
