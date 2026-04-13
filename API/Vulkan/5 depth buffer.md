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

## command buffer



## depth and stencil state



## window resize