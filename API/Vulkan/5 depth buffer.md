# depth buffer

到目前位置我们只有color attachment，还没有depth buffer这个attachment，所以没有进行depth test。

rasterizer每产生一个fragment，就会进行depth test，如果没有通过就会被discard。

在vulkan中 depth range和opengl[-1,1]不同，是[0,1],需要对glm进行限制

```C++
#define GLM_FORCE_DEPTH_ZERO_TO_ONE
```



## depth image & view

同样的image\memory\imageview三件套。写到`createDepthResources`中。

和color attachment一样,需要由从swap chain extent定义的resolution、正确的image usage、最佳的tiling以及device local memory。

format一般是：

- `vk::Format::eD32Sfloat`: 32-bit float for depth

- `vk::Format::eD32SfloatS8Uint`: 32-bit signed float for depth and 8 bit stencil component

- `vk::Format::eD24UnormS8Uint`: 24-bit float for depth and 8 bit stencil component


之后调用`createImageView`即可。

## command buffer

### clear values

在record中声明一个新的clear depth，初始值为1.0远处，

```c++
vk::ClearValue clearDepth = vk::ClearDepthStencilValue(1.0f, 0);
```

### Dynamic rendering

```c++
vk::RenderingAttachmentInfo depthAttachmentInfo = {
    .imageView   = depthImageView,
    .imageLayout = vk::ImageLayout::eDepthAttachmentOptimal,
    .loadOp      = vk::AttachmentLoadOp::eClear,
    .storeOp     = vk::AttachmentStoreOp::eDontCare,
    .clearValue  = clearDepth};
```

之后在renderInfo中指定这个attachmentInfo

```c++
vk::RenderingInfo renderingInfo = {
    ...
    .pDepthAttachment     = &depthAttachmentInfo};
```

### transition

例如我们之前对colorattachment做的那样

```c++
transitionImageLayoutSwapChain(imageIndex, vk::ImageLayout::eUndefined, vk::ImageLayout::eColorAttachmentOptimal,
			{}, vk::AccessFlagBits2::eColorAttachmentWrite,
			vk::PipelineStageFlagBits2::eTopOfPipe, vk::PipelineStageFlagBits2::eColorAttachmentOutput);
transitionImageLayoutSwapChain(
    *depthImage,
    vk::ImageLayout::eUndefined,
    vk::ImageLayout::eDepthAttachmentOptimal,
    vk::AccessFlagBits2::eDepthStencilAttachmentWrite,
    vk::AccessFlagBits2::eDepthStencilAttachmentWrite,
    vk::PipelineStageFlagBits2::eEarlyFragmentTests | vk::PipelineStageFlagBits2::eLateFragmentTests,
    vk::PipelineStageFlagBits2::eEarlyFragmentTests | vk::PipelineStageFlagBits2::eLateFragmentTests,
    vk::ImageAspectFlagBits::eDepth);
```

相较于color attachment来说depth只用transition一次。（因为不需要present

## depth and stencil state

attachment有了，我们现在需要启用depth test。

在pipeline中声明depth和stencil的createInfo

```c++
vk::PipelineDepthStencilStateCreateInfo depthStencil{
    .depthTestEnable       = vk::True,
    .depthWriteEnable      = vk::True,
    .depthCompareOp        = vk::CompareOp::eLess,
    .depthBoundsTestEnable = vk::False,
    .stencilTestEnable     = vk::False};
```

`depthBoundsTestEnable`/`minDepthBounds`/`maxDepthBounds`

是用于可选的bound test，这是一个额外的test。将depth buffer中的值和一个范围做比较，是否满足条件，如果满足就pass，否则就discard。

**Notes**:

比较的buffer里面的值，而不是fragment的深度值。

可以用于

- SSAO的模糊pass(忽略天空盒)
- deferred rendering中Light pass，用光源的包围球只处理特定深度范围的像素。

创建完以后我们需要在pipeline的相关state中指定这个信息。

## window resize

同时我们需要在window size大小变换的时候，重建depth attachment