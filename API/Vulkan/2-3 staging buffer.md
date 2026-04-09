# staging buffer

我们现在选择的memory type`host visible`,并不是最理想的供gpu进行访问的type。最理想的type是有`VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT` flag的。它对于cpu是不可访问的。我们会创建两个buffer，一个是staging buffer，这个是cpu可访问的，需要将数据上传到这里，另一个是在device local memory的final vertex buffer。我们会使用buffer copy将数据从staging buffer转移到final vertex buffer。

## queue

我们需要一个queue family来执行transfer操作。`VK_QUEUE_TRANSFER_BIT`。所有的`VK_QUEUE_GRAPHICS_BIT`以及`VK_QUEUE_COMPUTE_BIT`的queue family都默认带有transfer的功能。

## abstract

我们把创建buffer的过程抽象出来。

## using a staging buffer

用staging buffer干我们之前vertex buffer干的活，最后再把数据copy到真正的vertex buffer。

对于usage字段有了新的op:

- `VK_BUFFER_USAGE_TRANSFER_SRC_BIT`: Buffer can be used as source in a memory transfer operation.

- `VK_BUFFER_USAGE_TRANSFER_DST_BIT`: Buffer can be used as destination in a memory transfer operation.


staging buffer的usage是`eTransferSrc`,final vertex buffer的usage是`eTransferDst` 支持的properties是`eDeviceLocal`。

创建好buffer和memory并fill data后就是要进行copy了。

memory transfer的操作是要通过command buffer的，就像draw command一样。我们需要创建cmdbuffer，并在这个cmdbuffer中record copy 命令，这里就不需要繁琐的renderinfo以及beginrendering等等设置了，只需要记录copy这一条命令就可以了。同时这个cmd buffer不是像draw call一样循环的，只提交一次，我们在begin info中可以指定

```c++
commandCopyBuffer.begin(vk::CommandBufferBeginInfo { .flags = vk::CommandBufferUsageFlagBits::eOneTimeSubmit });
```

copy命令如下：

```c++
commandCopyBuffer.copyBuffer(srcBuffer, dstBuffer, vk::BufferCopy(0, 0, size));
```

最后一个参数就是告诉从哪个region去copy。`VkBufferCopy` (source buffer offset, destination buffer offset and size)

之后需要在graphicsQueue中提交这个cmd，我们有两种方式来等待这个transfer完成操作，一个是`vkWaitForFences`。另一个就是`vkQueueWaitIdle`。前者可以更好处理多个同时的transfer,等待它们全部完成。

**在copy完成之后，stagin buffer就会因为RAII自动销毁，释放内存。** staging的raii handle不要全局创建，应当创建在块作用域内。

现在每一帧的Vertex data会从更高效的memory中读取。



## conclusion

不要给每个buffer都单独调用`vkAllocateMemory`，每个物理设备都有一个硬性上限`maxMemoryAllocationCount`,表示同时存在的`VkDeviceMemory`的最大数量。即使在gtx1080中也只有4096。`vkAllocateMemory`本身就是一个昂贵的操作，涉及驱动内部的页表建立、内核态调用等等，频繁的调用会使性能下降。

### sub-allocation

正确的做法是子分配，通过`vkAllocateMemory`拿到一大块内存，然后把不同buffer绑定到这一块内存的不同offset上。

```C++
buffer.bindMemory(*memory, 0); // 第二个参数就是offset
```

```c++
一块 VkDeviceMemory(比如 64 MB)
┌─────────┬─────────┬──────┬─────────┬───────────┐
│ bufferA │ bufferB │ pad  │ bufferC │  free...  │
└─────────┴─────────┴──────┴─────────┴───────────┘
 offset=0  offset=  对齐   offset=
           1024     填充   2048
```

代价是:你必须自己管理这块内存里哪段被占用、哪段空闲、对齐填充怎么算、释放后怎么合并空闲块——本质上就是写一个**内存分配器**(类似 `malloc`/`free` 在用户态做的事)。

写内存分配器很复杂(要处理碎片、不同 memory type、host-visible vs device-local 等),所以 AMD 的 GPUOpen 团队开源了一个事实标准的库:**VulkanMemoryAllocator**(简称 **VMA**)。它是一个 header-only 的 C/C++ 库,接口大致像这样:

```cpp
VmaAllocation allocation;
vmaCreateBuffer(allocator, &bufferInfo, &allocInfo, &buffer, &allocation, nullptr);
```

**pros**

- 减少调用
- cache friendly index buffer/vertex合并到一起，里的更近
- use th