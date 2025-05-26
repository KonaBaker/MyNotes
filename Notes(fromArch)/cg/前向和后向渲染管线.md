deferred渲染管线，是专门有一个lighting pass在屏幕空间进行光照，而不是在“传统的”frag shader中，在光栅化之后进行可以剔除很多不必要的操作

Geometry Pass 阶段：逐物体走光栅化流程，把几何信息写入 G-buffer（Position、Normal、Albedo）

Lighting Pass 阶段：不再光栅化场景，只绘制一个**全屏 Quad**，然后在 Fragment Shader 中基于 G-buffer 做逐像素光照计算