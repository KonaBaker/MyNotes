# multisampling

用于减少rasterized primitives边缘锯齿的过程

## aliasing

当模拟信号转换为数字信号时（连续到离散），由于采样点不足，导致的一种异常现象，会产生aliasing。

## antialiasing

最简单但是最耗性能的方法就是以某种方式增加采样数量。

**texture filtering**是一种抗锯齿形式，专门处理因访问纹理而产生的锯齿。mipmap纹素都相当于多个采样点（采样更高层级）。纹理过滤只处理因访问纹理或者基于此类访问的计算而产生的锯齿。不处理图元边缘的锯齿。

更通用的抗锯齿形式：高分辨率渲染，然后平均其中的像素值。这就是**超采样(super-sampling)**。就是把高分辨率图像的像素当作采样点。

当开启supersampling的时候，在光栅化时为每个像素分解为多个采样点去采样primitive。会为每个sample生成一个fragments。

缺点很明显：高分辨率渲染，而且最后还要额外做平均。

## multisampling

多重采样对超采样进行了一个小修改，更关注于边缘的抗锯齿。

多重采样仍为每个sample points生成光栅化数据，per-sample test顾名思义，也是按照每个sample来进行的。

区别是在fs中不是per-sample的。一把来说是每4个采样点执行一次，具体取决于实现和硬件。

对于这一组采样点，选择其中一个执行，然后这4个采样点获得一样的处理后值。

**coverage**

**edges**





## smooth antialiasing

