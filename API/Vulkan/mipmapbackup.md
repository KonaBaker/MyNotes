## mip level

```c++
mipLevels = static_cast<uint32_t>(std::floor(std::log2(std::max(texWidth, texHeight)))) + 1;
```

计算miplevels的层级，然后需修改 `createImage` 、 `createImageView` 和 `transitionImageLayout` 函数，指定mip level。

```C++
imageInfo.mipLevels = mipLevels;
viewInfo.subresourceRange.levelCount = mipLevels;
barrier.subresourceRange.levelCount = mipLevels;
```

## generate

通过`vkCmdBlitImage`逐级copy/scaling/filtering

对于textureimage我们需要增加两个用途，一个是transfersrc,一个是transferdst。

