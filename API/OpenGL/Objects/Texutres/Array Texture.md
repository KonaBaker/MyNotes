# Array Texture

> 是一种纹理类型，其每个mipmap层级都包含一组**尺寸相同、数量相同**的images。

**texture atalases**: a single texture which stores data for multiple objects.

减小纹理切换所带来的开销。Array texture是atalas的一种替代方案。



## 概念

数组纹理的每个mipmap层级都是一系列images。一个mipmap层级内的每个image被称作一个layer



## usage

samplerxDArray

额外的纹理坐标用于指定layer

`actual_layer = max(0, min(d - 1, floor(layer + 0.5)) )`



## limitation

尺寸受限于`GL_MAX_TEXTRUE_SIZE`

layer受限于`GL_MAX_ARRAY_TEXTURE_LAYERS` 通常小于上面那个，要求至少为2048。
