ramp texture渐变纹理。

一般作为lut(look up table)，一张查找表，简化代码复杂度，性能上直接查表比复杂数学计算更快。

一般为长条状：

<img src="./assets/image-20250709155348818.png" alt="image-20250709155348818" style="zoom:67%;" />

一个ramp纹理可以包含多行，每行代表不同类型的效果

比如：第一行是泡沫ramp，第二行是深度ramp等