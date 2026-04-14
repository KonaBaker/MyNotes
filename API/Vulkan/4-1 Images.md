## intro

将一个texture添加到app需要以下步骤：

- 创建一个使用device memory的image object
- 从一个image file 填充 pixels
- 创建一个 image sampler
- 添加一个combined image sampler descriptor来采样颜色

和vertex buffer类似，我们需要创建一个staging，然后填充数据，再copy到final image object。

这个staging可以是image，也可以是buffer。后者更加快，限制更少，更加简单。

额外的，对于image来说需要声明`ImageLayout`，这决定了在memory中如何组织pixels。因为显卡的工作方式，我们不能简单的一行一行的存储这个image。对于不同的用途，有optimal的存储方式。

- `vk::ImageLayout::ePresentSrcKHR`: Optimal for presentation
- `vk::ImageLayout::eColorAttachmentOptimal`: Optimal as attachment for writing colors from the fragment shader
- `vk::ImageLayout::eTransferSrcOptimal`: Optimal as source in a transfer operation, like `vkCmdCopyImageToBuffer``
- `vk::ImageLayout::eTransferDstOptimal`: Optimal as destination in a transfer operation, like `vkCmdCopyBufferToImage`
- `vk::ImageLayout::eShaderReadOnlyOptimal`: Optimal for sampling from a shader

pipeline barriers主要用于资源的同步，queue family拥有权的转换以及这一节要使用image transition layout。

```c++
void createTextureImage() {}
```

## loading an image

```c++
#define STB_IMAGE_IMPLEMENTATION // function body
#include <stb_image.h> // only function prototypes
void createTextureImage() { 
    int texWidth, texHeight, texChannels;
    stbi_uc* pixels = stbi_load("textures/texture.jpg", &texWidth, &texHeight, &texChannels, STBI_rgb_alpha);
    vk::DeviceSize imageSize = texWidth * texHeight * 4;

    if (!pixels) {
        throw std::runtime_error("failed to load texture image!");
    }
}
```

pixels的layout是row by row的对于`STBI_rgb_alpha` 来说每个texel是4bytes。

## staging buffer

**<font color = ligblue> Notes: </font>**

images 应该总是被保存在gpu中，如果保存在只有host可见的memory，会极大的占用带宽。所以需要staging传递到GPU中。当然，staging也不是必须的，如果有host visible且device local的memory也是可以的。

流程和之前的vertex staging buffer一样。但是多了个最后的步骤

```c++
stbi_image_free(pixels);
```

## Texture Image

需要一个Image object以及背后的device memory。

image object的创建同样需要createinfo

```c++
vk::ImageCreateInfo imageInfo { 
    .imageType = vk::ImageType::e2D, 
    .format = format,
    .extent = {width, height, 1}, 
    .mipLevels = 1, 
    .arrayLayers = 1, 
    .samples = vk::SampleCountFlagBits::e1,
    .tiling = tiling, 
    .usage = usage, 
    .sharingMode = vk::SharingMode::eExclusive
};
```

- `imageType` 定义了texel寻址使用哪套坐标系统，1D可以用来存储一个data的数组，2D主要用于texture，3D可以用来存储voxel volumes。

- `extent` 每一维有多少的texel。

- `format` texel的format必须和pixels一致，否则copy的时候会出错误。

- `tiling` 描述了texel内存的组织方式

  - `vk::ImageTiling::eOptimal` 和实现相关的

  - `vk::ImageTiling::eLinear` row major，并且在row之间有padding

    **<font color = ligblue> Notes: </font>**

    linear一般不用，因为只能用于2Dimage。depth/stencil都不可以。且不能有多的levels和layer。运行效率也比较低。所以极少情况会用这个。

- `initialLayout`
  - `vk::ImageLayout::eUndefined` GPU无法使用，初始layout未定义，使用前需要通过layout transition转换到一个具体可用的layout。此时原数据会丢弃。**基本上都会使用这个**。
  - `vk::ImageLayout::ePreinitialized` GPU无法使用，转换后内容不会丢弃。例子：我们分配了host-visible的内存，然后memcpy进这里，gpu可以直接读，作为staging image。只对linear tiling有意义，因为optimal tiling的布局对cpu不透明，cpu无法预测gpu如何读数据。

- `usage`  transfer以及用于sampled
- `samples` 和多重采样相关。

之后就是创建对象，分配memory。

## layout transition

vulkan中的image可以存在于不同的layout之中，这些layout会影响pixel data在内存中的组织方式，这些方式是为了进行某些操作而进行了优化的，比如：从shader中读取，作为render target等等。

我们需要显式对layout进行管理。

对于我们的texture image。我们首先要从undefined转换为transferdst，接收staging的数据。其次要转换为适合shader reading的布局。这些操作通过pipeline barrier来完成

**<font color = ligblue> Notes: </font>**

usage中`VK_IMAGE_USAGE_TRANSFER_DST_BIT`的声明和layout中的`VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL`的表达是有区别的：

- `VK_IMAGE_USAGE_TRANSFER_DST_BIT` 是静态能力的描述，这个image可能会用作干什么，是多个能力的并集。gpu会据此进行优化，满足这些能力的同时，关闭或避免 其他不需要的功能 的一些冗余设置或者其他任何可能的开销。
- `VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL` 是动态的状态，在某一刻需要的时候，优化内存排布，让操作高效运行。

此时image以及copy命令都需要需要record在cmd buffer中，我们这时候就需要把这个逻辑转换为辅助函数：

```c++
vk::raii::CommandBuffer beginSingleTimeCommands() {
    vk::CommandBufferAllocateInfo allocInfo{ .commandPool = commandPool, .level = vk::CommandBufferLevel::ePrimary, .commandBufferCount = 1 };
    vk::raii::CommandBuffer commandBuffer = std::move(device.allocateCommandBuffers(allocInfo).front());

    vk::CommandBufferBeginInfo beginInfo{ .flags = vk::CommandBufferUsageFlagBits::eOneTimeSubmit };
    commandBuffer.begin(beginInfo);

    return commandBuffer;
}

void endSingleTimeCommands(vk::raii::CommandBuffer& commandBuffer) {
    commandBuffer.end();

    vk::SubmitInfo submitInfo{ .commandBufferCount = 1, .pCommandBuffers = &*commandBuffer };
    graphicsQueue.submit(submitInfo, nullptr);
    graphicsQueue.waitIdle();
}
```

除此之外还需要编写一个转换imagelayout的函数

```C++
void transitionImageLayout(const vk::raii::Image& image, vk::ImageLayout oldLayout, vk::ImageLayout newLayout) {
    auto commandBuffer = beginSingleTimeCommands();

    endSingleTimeCommands(commandBuffer);
}
```

```c++
vk::ImageMemoryBarrier barrier{ .oldLayout = oldLayout, .newLayout = newLayout, .image = image, .subresourceRange = { vk::ImageAspectFlagBits::eColor, 0, 1, 0, 1 } };
```

pipeline barrier都通过同一函数提交

```c++
void CommandBuffer::pipelineBarrier(
    vk::PipelineStageFlags                     srcStageMask,
    vk::PipelineStageFlags                     dstStageMask,
    vk::DependencyFlags                        dependencyFlags,
    ArrayProxy<const vk::MemoryBarrier>        memoryBarriers,
    ArrayProxy<const vk::BufferMemoryBarrier>  bufferMemoryBarriers,
    ArrayProxy<const vk::ImageMemoryBarrier>   imageMemoryBarriers
);
```

```c++
commandBuffer.pipelineBarrier(sourceStage, destinationStage, {}, {}, nullptr, barrier);
```

- sourceStage 是指barrier 前面、**必须先完成**的那些管线阶段。比如 `eTopOfPipe` 表示"没有任何前置工作要等",`eTransfer` 表示"等所有 transfer 操作结束",`eColorAttachmentOutput` 表示"等颜色写入结束"。
- deststage 是指 barrier 之后、**必须等 barrier 完成才能开始**的管线阶段。设置为非shader阶段没有实际意义。
- 0 or  `vk::DependencyFlagBits::eByRegion`按区域读取，已经可以读取资源中已经写入的部分（局部同步，主要用于TBR)
- `memoryBarriers` 针对**所有内存**的通用屏障,不绑定到具体资源。很少直接用
- `bufferMemoryBarriers `针对某个 buffer 的某段范围做同步
- `imageMemoryBarriers` 针对具体 image 的子资源做同步,**而且这是唯一能做 layout transition 的地方**。

**有Idle，为什么还要barrier?**

1) waitIdle只能同步工作全部跑完，但是不能保证内存可见性
2) barrier不止是同步，整个layout transition本身都是它做的。

## copy buffer to image

```c++
vk::BufferImageCopy region{ .bufferOffset = 0, .bufferRowLength = 0, .bufferImageHeight = 0,
    .imageSubresource = { vk::ImageAspectFlagBits::eColor, 0, 0, 1 }, .imageOffset = {0, 0, 0}, .imageExtent = {width, height, 1} };
```

就类似于`vk::BufferCopy(0, 0, size)`

imageSubresource精确指定这次拷贝操作要写入(或读出)image 的哪一部分"子资源"。一个 Vulkan image 并不是一块单一的像素数据 —— 它可能同时拥有多个 **mip 层级**、多个 **array layer**,以及多个 **aspect**(颜色 / 深度 / 模板)。`imageSubresource` 的作用就是在这三个维度上"定位"。

```C++
struct VkImageSubresourceLayers {
    VkImageAspectFlags aspectMask;      // 哪个 aspect
    uint32_t           mipLevel;        // 哪个 mip level
    uint32_t           baseArrayLayer;  // 从哪个 array layer 开始
    uint32_t           layerCount;      // 涉及几个 array layer
};
```



最后调用命令

```c++
commandBuffer.copyBufferToImage(buffer, image, vk::ImageLayout::eTransferDstOptimal, {region});
```



## preparing

`transitionImageLayout(textureImage, vk::ImageLayout::eTransferDstOptimal, vk::ImageLayout::eShaderReadOnlyOptimal);`

最后一步转换到着色器能看的。

## access mask & stage mask

- 未定义 → 传输目标：传输写入无需等待任何操作  

- 传输目标 → 着色器读取：着色器读取应等待传输写入，特别是片段着色器中的读取操作，因为这是我们将使用纹理的地方  

`vkImageMemoryBarrier`中有两个access mask字段

```C++
vk::AccessFlags srcAccessMask;  // 源访问掩码
vk::AccessFlags dstAccessMask;  // 目标访问掩码
```

决定了什么类型的内存访问需要同步。stage 是执行依赖，acess是内存依赖

- src 告诉 driver:"在 `srcStageMask` 指定的阶段里,**之前发生过哪些写操作,需要把它们从 cache 刷回 memory**,让后续读得到。"
  - `eTransferWrite` —— 之前做过 `vkCmdCopy*` / `vkCmdBlit*` / `vkCmdClear*` 的写入
  - `eColorAttachmentWrite` —— 之前作为 color attachment 被渲染
  - `eDepthStencilAttachmentWrite` —— 之前作为 depth/stencil attachment 被写入
  - `eShaderWrite` —— compute / fragment shader 通过 storage image 写入
  - `{}`(无)—— 之前没有需要同步的写(典型场景:image 刚从 `eUndefined` 出来,之前压根没写过东西)

- 告诉 driver:"在 `dstStageMask` 指定的阶段里,**接下来会发生哪些访问,需要让它们看到最新数据**(把目标 cache 作废,重新从 memory 取)。"
  - `eTransferWrite` / `eTransferRead` —— 接下来要做 copy/blit
  - `eShaderRead` —— 接下来 shader 要采样这张 image
  - `eColorAttachmentWrite` —— 接下来要作为 color attachment 渲染
  - `eDepthStencilAttachmentRead/Write` —— 接下来做 depth test / depth write
  - `eInputAttachmentRead` —— 接下来作为 input attachment 被读

`VkImageMemoryBarrier` 是一个结构，里面填好参数。声明完毕后，`vkCmdPipelineBarrier` 是commandbuffer的一条命令，需要执行，里面还有stage mask，完整的语义是：

**在** `srcStageMask` **阶段里所有** `srcAccessMask` **类型的访问必须完成并对内存可见,然后** `dstStageMask` **阶段里的** `dstAccessMask` **类型访问才能开始并看到最新数据。**



## 异步改造

### 改造前（同步，每个 helper 自己等）

cpp

```cpp
void createTextureImage() {
    // ... 创建 staging buffer、image ...

    transitionImageLayout(image, ..., UNDEFINED, TRANSFER_DST);
    // → submit #1, waitIdle #1

    copyBufferToImage(staging, image, w, h);
    // → submit #2, waitIdle #2

    transitionImageLayout(image, ..., TRANSFER_DST, SHADER_READ);
    // → submit #3, waitIdle #3
}
```

时间线（`|` 是 CPU 等待点）：

```
CPU: record→submit|wait| record→submit|wait| record→submit|wait|
GPU:              [t1]              [cp]              [t2]
```

### 改造后（异步，批一次）

给类加两个成员：

cpp

```cpp
VkCommandBuffer setupCmd = VK_NULL_HANDLE;

VkCommandBuffer getSetupCommandBuffer() {
    if (setupCmd == VK_NULL_HANDLE) {
        VkCommandBufferAllocateInfo ai{};
        ai.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        ai.commandPool = commandPool;
        ai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        ai.commandBufferCount = 1;
        vkAllocateCommandBuffers(device, &ai, &setupCmd);

        VkCommandBufferBeginInfo bi{};
        bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        vkBeginCommandBuffer(setupCmd, &bi);
    }
    return setupCmd;
}

void flushSetupCommands() {
    if (setupCmd == VK_NULL_HANDLE) return;

    vkEndCommandBuffer(setupCmd);

    VkSubmitInfo si{};
    si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1;
    si.pCommandBuffers = &setupCmd;

    vkQueueSubmit(graphicsQueue, 1, &si, VK_NULL_HANDLE);
    vkQueueWaitIdle(graphicsQueue);          // 只等这一次

    vkFreeCommandBuffers(device, commandPool, 1, &setupCmd);
    setupCmd = VK_NULL_HANDLE;
}
```

然后把 helper 改成**只记录，不 submit**：

cpp

```cpp
void transitionImageLayout(VkImage img, ..., VkImageLayout oldL, VkImageLayout newL) {
    VkCommandBuffer cb = getSetupCommandBuffer();   // ← 不再 beginSingleTimeCommands
    VkImageMemoryBarrier barrier{ /* ... */ };
    vkCmdPipelineBarrier(cb, srcStage, dstStage, 0, 0,nullptr, 0,nullptr, 1,&barrier);
    // ← 不再 endSingleTimeCommands
}

void copyBufferToImage(VkBuffer buf, VkImage img, uint32_t w, uint32_t h) {
    VkCommandBuffer cb = getSetupCommandBuffer();
    VkBufferImageCopy region{ /* ... */ };
    vkCmdCopyBufferToImage(cb, buf, img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
}
```

调用方：

cpp

```cpp
void createTextureImage() {
    // ... staging buffer, image 创建 ...
    transitionImageLayout(image, ..., UNDEFINED,    TRANSFER_DST);
    copyBufferToImage   (staging, image, w, h);
    transitionImageLayout(image, ..., TRANSFER_DST, SHADER_READ);
    // 此时三条命令都躺在 setupCmd 里，GPU 还没开工

    flushSetupCommands();  // 一次 submit、一次 wait
    // 现在才真正安全销毁 staging buffer
}
```

时间线变成：

```
CPU: record record record submit|wait|
GPU:                      [t1 → cp → t2]  (连续跑，中间无停顿)
```
