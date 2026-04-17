# Mipmap

## 0. objective

读完这一章，你应当能回答这四个问题：

1. **Mipmap 到底是什么？为什么 GPU 渲染需要它？**
2. **在 Vulkan 里，如何用 `vkCmdBlitImage` 在 GPU 端"就地"生成 Mipmap？**
3. **为什么 Mipmap 生成的循环里要写那么多 `pipelineBarrier`？每一个屏障到底在保护什么？**
4. **`VkSampler` 的 `minLod` / `maxLod` / `mipLodBias` / `mipmapMode` 分别控制什么？**

------

## 1. Mipmap

Mipmap 是**预先生成的、逐级降采样的图像金字塔**。每一级的宽高都是上一级的一半：

```
Level 0:   1024 x 1024   ← 原图
Level 1:    512 x  512
Level 2:    256 x  256
Level 3:    128 x  128
...
Level N:      1 x    1   ← 只有一个像素
```

对一张 1024×1024 的纹理，级数为：

$$ \text{mipLevels} = \left\lfloor \log_2 \max(W,H) \right\rfloor + 1 = \lfloor\log_2 1024\rfloor + 1 = 11 $$

### 为什么需要？

GPU 采样纹理时，如果一个屏幕像素覆盖了原图的很多个纹素（物体远离相机时就是这种情况），直接用 `magFilter`（最近或线性插值）只采样有限的几个点，会出现：

- **Moiré 摩尔纹**（混叠，像水波纹）
- **闪烁**（相机/物体轻微移动，像素颜色剧烈跳变）
- **浪费带宽**（读了远超必要数量的纹素）

Mipmap 本质是**预先计算好的低通滤波结果**——远看时 GPU 直接去取"已经平滑过的低分辨率版本"，既快又无 aliasing。

> 📖 **术语澄清**
>
> - **mip level（级）**：金字塔的某一层。Level 0 是原图。
> - **mip chain（链）**：除了 level 0 以外的所有层，合起来叫 mip chain。
> - **在 Vulkan 里，一个 `VkImage` 对象本身就可以持有所有 mip 级**，通过 `VkImageCreateInfo::mipLevels` 字段指定级数。不是每级一个 Image！

------

## 2. 在 Image 里给 Mipmap 留空间

### 2.1 计算 mipLevels

先给类加一个成员：

```cpp
uint32_t          mipLevels = 0;
vk::raii::Image   textureImage       = nullptr;
vk::raii::ImageView textureImageView = nullptr;
```

在 `createTextureImage` 中加载完纹理后立即计算：

```cpp
int texWidth, texHeight, texChannels;
stbi_uc* pixels = stbi_load(TEXTURE_PATH.c_str(),
                            &texWidth, &texHeight, &texChannels,
                            STBI_rgb_alpha);
vk::DeviceSize imageSize = texWidth * texHeight * 4;

mipLevels = static_cast<uint32_t>(
              std::floor(std::log2(std::max(texWidth, texHeight)))
            ) + 1;
```

**逐段拆解**：

| 子表达式                        | 作用                                              |
| ------------------------------- | ------------------------------------------------- |
| `std::max(texWidth, texHeight)` | 取长边（非方形贴图时，长边才决定级数）            |
| `std::log2(...)`                | "这个值可以被 2 整除多少次"                       |
| `std::floor(...)`               | 非 2 的幂时向下取整（例如 800 → log2 ≈ 9.64 → 9） |
| `+ 1`                           | 把 level 0（原图本身）也算进去                    |

### 2.2  `mipLevels` 

三个函数需要新增 `mipLevels` 参数：

```cpp
// 1. 创建 Image
void createImage(uint32_t width, uint32_t height, uint32_t mipLevels,
                 vk::Format format, vk::ImageTiling tiling,
                 vk::ImageUsageFlags usage, vk::MemoryPropertyFlags properties,
                 vk::raii::Image& image, vk::raii::DeviceMemory& imageMemory)
{
    vk::ImageCreateInfo imageInfo{
        .imageType     = vk::ImageType::e2D,
        .format        = format,
        .extent        = {width, height, 1},
        .mipLevels     = mipLevels,          // ← 这里
        .arrayLayers   = 1,
        .samples       = vk::SampleCountFlagBits::e1,
        .tiling        = tiling,
        .usage         = usage,
        .sharingMode   = vk::SharingMode::eExclusive,
        .initialLayout = vk::ImageLayout::eUndefined
    };
    // ...
}

// 2. 创建 ImageView —— subresourceRange.levelCount 要覆盖所有级
[[nodiscard]] vk::raii::ImageView createImageView(
    const vk::raii::Image& image, vk::Format format,
    vk::ImageAspectFlags aspectFlags, uint32_t mipLevels) const
{
    vk::ImageViewCreateInfo viewInfo{
        .image    = image,
        .viewType = vk::ImageViewType::e2D,
        .format   = format,
        .subresourceRange = { aspectFlags, 0, mipLevels, 0, 1 }
        //                               baseMipLevel ^   ^ levelCount
    };
    return vk::raii::ImageView(device, viewInfo);
}

// 3. 布局转换 —— 一次性把所有级从 UNDEFINED 转到 TRANSFER_DST
void transitionImageLayout(const vk::raii::Image& image,
                           vk::ImageLayout oldLayout, vk::ImageLayout newLayout,
                           uint32_t mipLevels)
{
    vk::ImageMemoryBarrier barrier{
        .oldLayout = oldLayout,
        .newLayout = newLayout,
        .image     = image,
        .subresourceRange = { vk::ImageAspectFlagBits::eColor, 0, mipLevels, 0, 1 }
    };
    // ...
}
```

### 2.3 更新所有调用点

```cpp
// Depth image 只要 1 级即可
createImage(swapChainExtent.width, swapChainExtent.height, 1,
            depthFormat, vk::ImageTiling::eOptimal,
            vk::ImageUsageFlagBits::eDepthStencilAttachment,
            vk::MemoryPropertyFlagBits::eDeviceLocal,
            depthImage, depthImageMemory);

// 纹理 Image 要完整 mipLevels，并且 usage 要加 eTransferSrc！
createImage(texWidth, texHeight, mipLevels,
            vk::Format::eR8G8B8A8Srgb,
            vk::ImageTiling::eOptimal,
            vk::ImageUsageFlagBits::eTransferSrc    // ← 新增！要从它读取去 blit
          | vk::ImageUsageFlagBits::eTransferDst    //    要写入它
          | vk::ImageUsageFlagBits::eSampled,       //    要采样它
            vk::MemoryPropertyFlagBits::eDeviceLocal,
            textureImage, textureImageMemory);
```

> ⚠️ **易错点 #1：usage 里忘加 `eTransferSrc`** 之前章节里纹理只需要 `eTransferDst | eSampled`（CPU 传进去、着色器采样）。现在要在 GPU 里**从它自己读取**去做 blit，所以必须加 `eTransferSrc`。漏掉这个，validation layer 会直接报错。

------

## 3. generate mipmap

Staging buffer 只填充了 **mip level 0**。其他级还是未定义的垃圾数据。

我们的做法：**用 `vkCmdBlitImage` 逐级把 level `i-1` 缩小一半后写入 level `i`**。

```
   Level 0 (已填充) ──blit─→ Level 1 ──blit─→ Level 2 ──blit─→ ... ──blit─→ Level N-1
```

### 3.1 `vkCmdBlitImage` 

它是一种"带滤波的 copy"：

| 和 `vkCmdCopyBufferToImage` 对比 | `vkCmdBlitImage`                                 |
| -------------------------------- | ------------------------------------------------ |
| 源 / 目的尺寸必须相同            | **可以不同**（会缩放）                           |
| 按字节复制                       | 按像素**插值**（`VK_FILTER_LINEAR` / `NEAREST`） |
| 视为传输操作                     | **也是传输操作**，但要求 queue 必须支持 graphics |
| 源必须是 buffer                  | 源是 Image                                       |

`vkCmdBlitImage` 本身就是 "拷 + 缩 + 滤波" 三合一——这正是生成 mipmap 需要的。

> ⚠️ **易错点 #2：专用 transfer queue 不能执行 blit** 如果你按 Vertex buffer 章节那样创建了一个专用的 transfer queue，**不要**把 `blitImage` 提交到它上面。Spec 规定 blit 操作需要 queue 具有 `VK_QUEUE_GRAPHICS_BIT`。把 mipmap 生成放回 graphics queue。

### 3.2 layout

| 角色                 | 最优布局              |
| -------------------- | --------------------- |
| 作为 blit 的**源**   | `eTransferSrcOptimal` |
| 作为 blit 的**目的** | `eTransferDstOptimal` |

Vulkan 的一大优势：**同一个 Image 的不同 mip level 可以处在不同 layout**。这是整个算法的关键——**我们在循环里逐级翻转 layout**。

### 3.3 起始状态

把 `createTextureImage` 尾部那行旧的"整图到 `SHADER_READ_ONLY_OPTIMAL`"的转换**删掉**：

```cpp
transitionImageLayout(textureImage, vk::ImageLayout::eUndefined,
                      vk::ImageLayout::eTransferDstOptimal, mipLevels);
copyBufferToImage(stagingBuffer, textureImage,
                  static_cast<uint32_t>(texWidth),
                  static_cast<uint32_t>(texHeight));
// ❌ 删掉：transitionImageLayout(..., eTransferDstOptimal, eShaderReadOnlyOptimal, ...);
// 每一级的 SHADER_READ_ONLY 转换都会在 generateMipmaps 内部完成

generateMipmaps(textureImage, vk::Format::eR8G8B8A8Srgb,
                texWidth, texHeight, mipLevels);
```

进入 `generateMipmaps` 时：

- **所有 mip 级**都是 `TransferDstOptimal`
- **只有 level 0** 里有真正的像素数据（来自 staging buffer 的拷贝）
- level 1..N-1 内容未定义，但布局正确

------

## 4. `generateMipmaps` 实现

### 4.1 完整代码

```cpp
void generateMipmaps(vk::raii::Image& image, vk::Format imageFormat,
                     int32_t texWidth, int32_t texHeight, uint32_t mipLevels)
{
    // ── (a) 检查格式是否支持线性 blit ──────────────────────────────
    vk::FormatProperties formatProperties =
        physicalDevice.getFormatProperties(imageFormat);
    if (!(formatProperties.optimalTilingFeatures
          & vk::FormatFeatureFlagBits::eSampledImageFilterLinear))
    {
        throw std::runtime_error(
            "texture image format does not support linear blitting!");
    }

    // ── (b) 申请一个一次性 CommandBuffer ────────────────────────
    std::unique_ptr<vk::raii::CommandBuffer> commandBuffer =
        beginSingleTimeCommands();

    // ── (c) 可复用的屏障模板 ────────────────────────────────
    vk::ImageMemoryBarrier barrier{
        .srcAccessMask       = vk::AccessFlagBits::eTransferWrite,
        .dstAccessMask       = vk::AccessFlagBits::eTransferRead,
        .oldLayout           = vk::ImageLayout::eTransferDstOptimal,
        .newLayout           = vk::ImageLayout::eTransferSrcOptimal,
        .srcQueueFamilyIndex = vk::QueueFamilyIgnored,
        .dstQueueFamilyIndex = vk::QueueFamilyIgnored,
        .image               = image
    };
    barrier.subresourceRange.aspectMask     = vk::ImageAspectFlagBits::eColor;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount     = 1;
    barrier.subresourceRange.levelCount     = 1;   // 一次只管一级！

    int32_t mipWidth  = texWidth;
    int32_t mipHeight = texHeight;

    // ── (d) 主循环：i 从 1 开始，一路到 mipLevels-1 ───────────────
    for (uint32_t i = 1; i < mipLevels; i++) {

        // (d.1) 把 level(i-1) 从 TransferDst → TransferSrc
        barrier.subresourceRange.baseMipLevel = i - 1;
        barrier.oldLayout     = vk::ImageLayout::eTransferDstOptimal;
        barrier.newLayout     = vk::ImageLayout::eTransferSrcOptimal;
        barrier.srcAccessMask = vk::AccessFlagBits::eTransferWrite;
        barrier.dstAccessMask = vk::AccessFlagBits::eTransferRead;

        commandBuffer->pipelineBarrier(
            vk::PipelineStageFlagBits::eTransfer,   // src stage
            vk::PipelineStageFlagBits::eTransfer,   // dst stage
            {}, {}, {}, barrier);

        // (d.2) 组织 blit 参数
        vk::ArrayWrapper1D<vk::Offset3D, 2> offsets, dstOffsets;
        offsets[0]    = vk::Offset3D(0, 0, 0);
        offsets[1]    = vk::Offset3D(mipWidth, mipHeight, 1);
        dstOffsets[0] = vk::Offset3D(0, 0, 0);
        dstOffsets[1] = vk::Offset3D(
            mipWidth  > 1 ? mipWidth  / 2 : 1,
            mipHeight > 1 ? mipHeight / 2 : 1,
            1);

        vk::ImageBlit blit{
            .srcSubresource = {},
            .srcOffsets     = offsets,
            .dstSubresource = {},
            .dstOffsets     = dstOffsets
        };
        blit.srcSubresource = vk::ImageSubresourceLayers(
            vk::ImageAspectFlagBits::eColor, i - 1, 0, 1);
        blit.dstSubresource = vk::ImageSubresourceLayers(
            vk::ImageAspectFlagBits::eColor, i,     0, 1);

        // (d.3) 执行 blit：同一张 image 内部不同级之间的缩放拷贝
        commandBuffer->blitImage(
            image, vk::ImageLayout::eTransferSrcOptimal,   // src
            image, vk::ImageLayout::eTransferDstOptimal,   // dst
            { blit }, vk::Filter::eLinear);

        // (d.4) 把 level(i-1) 从 TransferSrc → ShaderReadOnly
        //        —— 这一级已经不会再被 blit 读了
        barrier.oldLayout     = vk::ImageLayout::eTransferSrcOptimal;
        barrier.newLayout     = vk::ImageLayout::eShaderReadOnlyOptimal;
        barrier.srcAccessMask = vk::AccessFlagBits::eTransferRead;
        barrier.dstAccessMask = vk::AccessFlagBits::eShaderRead;

        commandBuffer->pipelineBarrier(
            vk::PipelineStageFlagBits::eTransfer,         // src stage
            vk::PipelineStageFlagBits::eFragmentShader,   // dst stage
            {}, {}, {}, barrier);

        // (d.5) 维度减半，但不得小于 1
        if (mipWidth  > 1) mipWidth  /= 2;
        if (mipHeight > 1) mipHeight /= 2;
    }

    // ── (e) 循环外：处理最后一级 ──────────────────────────────
    barrier.subresourceRange.baseMipLevel = mipLevels - 1;
    barrier.oldLayout     = vk::ImageLayout::eTransferDstOptimal;  // 它从未被读过
    barrier.newLayout     = vk::ImageLayout::eShaderReadOnlyOptimal;
    barrier.srcAccessMask = vk::AccessFlagBits::eTransferWrite;
    barrier.dstAccessMask = vk::AccessFlagBits::eShaderRead;

    commandBuffer->pipelineBarrier(
        vk::PipelineStageFlagBits::eTransfer,
        vk::PipelineStageFlagBits::eFragmentShader,
        {}, {}, {}, barrier);

    endSingleTimeCommands(*commandBuffer);
}
```

这段代码乍看很长，但模式非常规整。下面逐块剖析。

------

### 4.2 关键结构体：`vk::ImageMemoryBarrier`

屏障的字段含义（**本章真正变动的只有后五个**）：

| 字段                                          | 值                                                           | 含义                                                         |
| --------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| `srcAccessMask` / `dstAccessMask`             | 见下表                                                       | "做完 src 上一次 access 之后、dst 下一次 access 之前" 需要可见 |
| `oldLayout` / `newLayout`                     | 见下表                                                       | 布局转换前后                                                 |
| `srcQueueFamilyIndex` / `dstQueueFamilyIndex` | `QueueFamilyIgnored`                                         | 不跨 queue family                                            |
| `image`                                       | 当前 Image                                                   | 要转换的 Image                                               |
| `subresourceRange`                            | aspectMask=Color, baseArrayLayer=0, layerCount=1, **baseMipLevel=i-1 或 mipLevels-1, levelCount=1** | **每次只影响一级！**                                         |

> 💡 **关键点**：`levelCount = 1` 说明我们在用 subresource range 精细地 **只转换这一级**，而 image 的其他级保持它们各自的 layout 不变。

### 4.3 循环中每一轮的 layout 状态演变

以 `mipLevels = 4` 为例画个状态表：

| 时刻                 | level 0        | level 1         | level 2         | level 3         |
| -------------------- | -------------- | --------------- | --------------- | --------------- |
| 进入 generateMipmaps | **Dst**        | Dst             | Dst             | Dst             |
| i=1, barrier1 后     | **Src**        | Dst             | Dst             | Dst             |
| i=1, blit 后         | Src            | **Dst(已写入)** | Dst             | Dst             |
| i=1, barrier2 后     | **ShaderRead** | Dst             | Dst             | Dst             |
| i=2, barrier1 后     | ShaderRead     | **Src**         | Dst             | Dst             |
| i=2, blit 后         | ShaderRead     | Src             | **Dst(已写入)** | Dst             |
| i=2, barrier2 后     | ShaderRead     | **ShaderRead**  | Dst             | Dst             |
| i=3, barrier1 后     | ShaderRead     | ShaderRead      | **Src**         | Dst             |
| i=3, blit 后         | ShaderRead     | ShaderRead      | Src             | **Dst(已写入)** |
| i=3, barrier2 后     | ShaderRead     | ShaderRead      | **ShaderRead**  | Dst             |
| 循环外最后转换       | ShaderRead     | ShaderRead      | ShaderRead      | **ShaderRead**  |

> ⚠️ **易错点 #3：最后一级需要循环外单独处理** 观察上表：**level 3（最后一级）** 在整个循环中**从未被当作 src 使用**（它没有下一级要往里 blit），所以它始终停留在 `TransferDstOptimal`。必须在循环结束后，**多写一个 barrier** 把它也转到 `ShaderReadOnlyOptimal`。很多人最常见的 bug：忘了这个，导致渲染时 validation layer 报 "image layout mismatch"。

### 4.4 两个 barrier 的同步含义

```cpp
// barrier1 —— blit 之前
pipelineBarrier(eTransfer → eTransfer)
  srcAccess = TransferWrite    (等 level i-1 的写入完成)
  dstAccess = TransferRead     (blit 作为读取者要能看到它)
```

这个屏障等待 **level i-1 被填充**（要么来自 `copyBufferToImage`，要么来自上一轮的 blit），然后允许当前 blit 把它当 src 读取。

```cpp
// barrier2 —— blit 之后
pipelineBarrier(eTransfer → eFragmentShader)
  srcAccess = TransferRead     (等 blit 读完这一级)
  dstAccess = ShaderRead       (之后 Fragment Shader 可以采样)
```

blit 完成后，这一级再也不会被 transfer 操作碰了——它的"使命"是被采样。所以把它切到 `ShaderReadOnlyOptimal`，并保证 `FragmentShader` 阶段的 `ShaderRead` 能看到。

> 💡 **为什么 dst stage 是 `FragmentShader`？** 因为**采样发生在 FS**。把栅栏放在这里，相当于告诉 GPU："如果 FS 要读这一级，请先完成以上所有 transfer 写入/读取"。

### 4.5 `vk::ImageBlit` 结构体详解

```cpp
struct ImageBlit {
    ImageSubresourceLayers srcSubresource;  // 源的"哪一级/哪一层/哪个 aspect"
    Offset3D               srcOffsets[2];   // 源在该级里的 3D 包围盒
    ImageSubresourceLayers dstSubresource;  // 目的的"哪一级/哪一层/哪个 aspect"
    Offset3D               dstOffsets[2];   // 目的在该级里的 3D 包围盒
};
```

- `srcOffsets[0]` / `dstOffsets[0]` = 包围盒的**左上近**角（通常 `{0,0,0}`）
- `srcOffsets[1]` / `dstOffsets[1]` = 包围盒的**右下远**角（即 `{width, height, 1}`）
- **区域大小 = offsets[1] − offsets[0]**，源与目的区域大小不同就会自动缩放

对于 2D 纹理，Z 维度恒为 `1`（不是 0——因为"从 0 到 1"表示厚度为 1）。

```cpp
dstOffsets[1] = vk::Offset3D(
    mipWidth  > 1 ? mipWidth  / 2 : 1,  // 宽度减半，但最小为 1
    mipHeight > 1 ? mipHeight / 2 : 1,  // 高度减半，但最小为 1
    1);
```

> ⚠️ **易错点 #4：非方形纹理的维度收敛** 1024×256 的贴图：
>
> - level 0: 1024×256
> - level 1: 512×128
> - level 2: 256×64
> - level 3: 128×32
> - level 4: 64×16
> - level 5: 32×8
> - level 6: 16×4
> - level 7: 8×2
> - level 8: 4×1 ← **高度已到 1，不能再除**
> - level 9: 2×1
> - level 10: 1×1
>
> 所以 `if (mipHeight > 1) mipHeight /= 2;` 的判断必不可少——否则算到一半会出现 `0`，blit 时会报错。

### 4.6 `blitImage` 调用本身

```cpp
commandBuffer->blitImage(
    image, vk::ImageLayout::eTransferSrcOptimal,   // srcImage + srcImageLayout
    image, vk::ImageLayout::eTransferDstOptimal,   // dstImage + dstImageLayout
    { blit },                                      // regions
    vk::Filter::eLinear);                          // filter
```

- **srcImage 和 dstImage 是同一张 image**——我们就是在它自己不同级之间 blit。
- layout 必须 **恰好是** blit 要求的两个 optimal 布局。因为 blit 前我们已经把 `i-1` 转成 Src、而 `i` 从一开始就是 Dst，所以这里是一致的。
- `Filter::eLinear` 启用双线性插值（这也是教程选它的原因：生成的 mipmap 质量更高；`eNearest` 会像素化）。

------

## 5. filter

不是所有 GPU / 格式组合都支持 `vkCmdBlitImage` 做线性过滤。必须查询：

```cpp
vk::FormatProperties formatProperties =
    physicalDevice.getFormatProperties(imageFormat);

if (!(formatProperties.optimalTilingFeatures
      & vk::FormatFeatureFlagBits::eSampledImageFilterLinear))
{
    throw std::runtime_error(
        "texture image format does not support linear blitting!");
}
```

### `VkFormatProperties` 三个字段

| 字段                    | 何时看它                                                     |
| ----------------------- | ------------------------------------------------------------ |
| `linearTilingFeatures`  | 你创建 image 时用的是 `ImageTiling::eLinear`（CPU 可直接访问，布局固定） |
| `optimalTilingFeatures` | 你用的是 `ImageTiling::eOptimal`（GPU 友好，实际布局由驱动决定）——**我们的情况** |
| `bufferFeatures`        | 描述 buffer 视角下该格式可用的操作                           |

我们建 texture 时用的是 `eOptimal`，所以只需检查 `optimalTilingFeatures` 是否包含 `eSampledImageFilterLinear`。

### 实战中的替代方案

如果格式不支持线性过滤：

1. 运行时搜索一个**支持**的常见格式
2. 用 `stb_image_resize` 这类库在 **CPU 端**离线生成好每一级，再逐级 `copyBufferToImage`
3. **最推荐**：直接用 KTX2 之类的格式，**预先存储好所有 mip 级**，运行时不用再生成

> 💡 **教程作者的提醒** 实际项目中运行时生成 mipmap 并不常见。大多数游戏引擎都是离线生成好 mipmap 并存入纹理文件，这样加载更快、质量更稳定。

------

## 6. Sampler 的 Mipmap 相关参数

`VkImage` 存 mipmap 数据，而 `VkSampler` 决定**渲染时如何读取**这些数据。

### 6.1 Mipmap 选择的伪代码

Vulkan 规范里 sampler 选 mip level 的逻辑大致是：

```cpp
// Step 1: 根据屏幕上每个 fragment 的纹理坐标导数，算出 LOD
lod = getLodLevelFromScreenSize();   // 物体近则小（甚至负），物体远则大
lod = clamp(lod + mipLodBias, minLod, maxLod);

// Step 2: 从 LOD 选级
int level = clamp(floor(lod), 0, texture.mipLevels - 1);

// Step 3: 按 mipmapMode 决定采样方式
if (mipmapMode == eNearest) {
    color = sample(level);                          // 单级采样
} else { // eLinear
    color = blend(sample(level), sample(level+1));  // 相邻两级插值（三线性滤波）
}
```

级内采样又依赖 `lod` 正负：

```cpp
if (lod <= 0) color = readTexture(uv, magFilter);   // 近 → 放大 → magFilter
else          color = readTexture(uv, minFilter);   // 远 → 缩小 → minFilter
```

### 6.2 四个参数详解

| 参数         | 作用                                | 常用取值                                            |
| ------------ | ----------------------------------- | --------------------------------------------------- |
| `minLod`     | LOD 下限（clamp 的下界）            | `0.0f` — 允许采到最清晰的 level 0                   |
| `maxLod`     | LOD 上限（clamp 的上界）            | `VK_LOD_CLAMP_NONE` — 允许采到最小的那一级          |
| `mipLodBias` | LOD 偏移（统一加到算出来的 lod 上） | `0.0f` — 不偏移；正值更"远"更模糊，负值更"近"更清晰 |
| `mipmapMode` | 级间如何取值                        | `eLinear` = 三线性滤波，`eNearest` = 只取一级       |

### 6.3 本章的 sampler 设置

```cpp
void createTextureSampler()
{
    vk::PhysicalDeviceProperties properties = physicalDevice.getProperties();

    vk::SamplerCreateInfo samplerInfo{
        .magFilter        = vk::Filter::eLinear,
        .minFilter        = vk::Filter::eLinear,
        .mipmapMode       = vk::SamplerMipmapMode::eLinear,   // 三线性
        .addressModeU     = vk::SamplerAddressMode::eRepeat,
        .addressModeV     = vk::SamplerAddressMode::eRepeat,
        .addressModeW     = vk::SamplerAddressMode::eRepeat,
        .mipLodBias       = 0.0f,
        .anisotropyEnable = vk::True,
        .maxAnisotropy    = properties.limits.maxSamplerAnisotropy,
        .compareEnable    = vk::False,
        .compareOp        = vk::CompareOp::eAlways,
        .minLod           = 0.0f,
        .maxLod           = vk::LodClampNone                  // 等价于 VK_LOD_CLAMP_NONE
    };
    textureSampler = vk::raii::Sampler(device, samplerInfo);
}
```

> ⚠️ **易错点 #5：`maxLod` 设太小会"卡住"在高分辨率** 之前你可能把 `maxLod = 0.0f`——那等于**禁用了 mipmap**，sampler 永远只用 level 0。要启用完整 mipmap，必须把 `maxLod` 设为 `LodClampNone`（或至少 `mipLevels - 1` 这种够大的值）。

### 6.4 debug

教程里建议改一下 `minLod`：

```cpp
samplerInfo.minLod = static_cast<float>(mipLevels / 2);
```

这会**强制至少从中间那一级开始采样**，你能明显看到画面变模糊——这验证了 sampler 确实在按 LOD 选级。

------

## 7. `createTextureImage` 和调用链的最终状态

```cpp
void createTextureImage()
{
    int texWidth, texHeight, texChannels;
    stbi_uc* pixels = stbi_load(TEXTURE_PATH.c_str(),
                                &texWidth, &texHeight, &texChannels,
                                STBI_rgb_alpha);
    vk::DeviceSize imageSize = texWidth * texHeight * 4;
    mipLevels = static_cast<uint32_t>(
                  std::floor(std::log2(std::max(texWidth, texHeight)))
                ) + 1;

    if (!pixels) throw std::runtime_error("failed to load texture image!");

    // 1. Staging buffer
    vk::raii::Buffer       stagingBuffer({});
    vk::raii::DeviceMemory stagingBufferMemory({});
    createBuffer(imageSize,
                 vk::BufferUsageFlagBits::eTransferSrc,
                 vk::MemoryPropertyFlagBits::eHostVisible
               | vk::MemoryPropertyFlagBits::eHostCoherent,
                 stagingBuffer, stagingBufferMemory);

    void* data = stagingBufferMemory.mapMemory(0, imageSize);
    memcpy(data, pixels, imageSize);
    stagingBufferMemory.unmapMemory();
    stbi_image_free(pixels);

    // 2. 创建纹理 Image —— 注意 usage 里的 eTransferSrc
    createImage(texWidth, texHeight, mipLevels,
                vk::Format::eR8G8B8A8Srgb,
                vk::ImageTiling::eOptimal,
                vk::ImageUsageFlagBits::eTransferSrc
              | vk::ImageUsageFlagBits::eTransferDst
              | vk::ImageUsageFlagBits::eSampled,
                vk::MemoryPropertyFlagBits::eDeviceLocal,
                textureImage, textureImageMemory);

    // 3. 所有级 Undefined → TransferDst
    transitionImageLayout(textureImage,
                          vk::ImageLayout::eUndefined,
                          vk::ImageLayout::eTransferDstOptimal,
                          mipLevels);

    // 4. 只把 level 0 填上像素
    copyBufferToImage(stagingBuffer, textureImage,
                      static_cast<uint32_t>(texWidth),
                      static_cast<uint32_t>(texHeight));

    // 5. GPU 端生成 level 1..N-1；顺带把所有级转到 ShaderReadOnly
    generateMipmaps(textureImage, vk::Format::eR8G8B8A8Srgb,
                    texWidth, texHeight, mipLevels);
}
```

------

## 8. common mistakes

| #    | 坑                                          | 症状                                                         | 修复                                            |
| ---- | ------------------------------------------- | ------------------------------------------------------------ | ----------------------------------------------- |
| 1    | usage 漏掉 `eTransferSrc`                   | validation 报错：image used as blit src but not created with TRANSFER_SRC | 加上该 flag                                     |
| 2    | blit 提交到 transfer-only queue             | validation 报错：queue doesn't support blit                  | 用 graphics queue                               |
| 3    | 忘了循环外最后一级的 barrier                | 最后一级 layout 错，采样时报 layout mismatch                 | 补上循环外的 pipelineBarrier                    |
| 4    | `mipWidth/Height` 无条件除 2                | 非方形时维度变 0，blit 报 invalid extent                     | `if (mip > 1) mip /= 2;`                        |
| 5    | `maxLod = 0.0f`                             | mipmap 形同虚设，只用 level 0                                | 用 `vk::LodClampNone` 或 `(float)(mipLevels-1)` |
| 6    | `createImageView` 的 `levelCount` 写成 1    | 着色器只能看到 level 0，上传的 mipmap 全浪费                 | 传入 `mipLevels`                                |
| 7    | 没检查 `optimalTilingFeatures` 的线性过滤位 | 在某些 GPU 上运行时 blit 失败                                | 加 `FormatProperties` 检查                      |
| 8    | `baseMipLevel` 记错为 `i`（应为 `i-1`）     | 屏障保护错了级，数据未就绪就被读                             | 仔细对照：src 总是 `i-1`、dst 总是 `i`          |

------

## 9. summary

```
CPU 侧                                GPU 侧
──────────                            ────────────────────────────────
load PNG (stb)
    │
    ├──> staging buffer (host visible)
    │
    │                                 createImage
    │                                   mipLevels=N, usage=SRC|DST|SAMPLED
    │                                   所有级: Undefined
    │
    │                                 transitionImageLayout(整图)
    │                                   所有级: Undefined → TransferDst
    │
    ├─── copyBufferToImage ─────────> level 0 已填充；level 0..N-1 都是 TransferDst
    │
    │                                 generateMipmaps: for i=1..N-1
    │                                   ┌─ barrier: level(i-1) Dst → Src
    │                                   ├─ blitImage: level(i-1) → level(i)
    │                                   └─ barrier: level(i-1) Src → ShaderRO
    │                                 barrier: level(N-1) Dst → ShaderRO
    │                                 所有级: ShaderReadOnlyOptimal ✅
    │
    ├─── createImageView(mipLevels) ─> 着色器能看到所有级
    │
    └─── createSampler
           mipmapMode=Linear, minLod=0, maxLod=LodClampNone
```

------

📚 **推荐阅读**

- Vulkan Spec §12.3 *Image Blits*
- Vulkan Spec §16.9 *LOD Operation*（LOD 计算的详细公式）
- `VK_EXT_sampler_filter_minmax` 扩展（更高级的 mipmap 采样模式）
