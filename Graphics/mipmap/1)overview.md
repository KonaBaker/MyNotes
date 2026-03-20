# mipmap

- blit
- compute
  - nvpro_pyramid
  - unity/DX12
- AMD SPD

### 其他问题

mipmap需要额外占用约1/3的空间.

**Notes**

nvpro_pyramid是一个库，是一个vulkan方案。提供了shader和dispatch的代码，定义相关宏，在vulkan程序中调用。不属于驱动范畴。

vulkan或者DX12是没有像`glGenerateMipmap`这样直接生成的API的。所以在vulkan中的常见做法是使用`vkCmdBlitImage`逐级生成的。如果想要更高效，就需要自己写shader或者调用库。微软也写了这样一个mipmap生成方案。

opengl规范中写明了`glGenerateMipmap`那么这个API就需要驱动/厂商进行实现。

像unity这种引擎可以调用后端API生成，其也会自己在上层自己封装，自己实现一个mipmap的生成方法。



