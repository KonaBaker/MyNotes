PBO是用于异步像素传输操作的一种buffer object

pixel buffer objects



### 混淆与澄清

PBO和framebuffer毫无关系。PBO是buffer object是一种常规对象，而framebuffer object是和buffer object对应的概念，是一种容器对象。FBO用于离屏图像渲染。PBO则负责user(cpu)和images(gpu)之间的pixel传输。

PBO和texture没有管理。PBO不会以任何方式和纹理建立链接。image数据的存储是归于纹理本身的。



主要用于解决cpu和gpu之间传输像素阻塞的问题。

PBO会利用硬件上的DMA将数据直接传给纹理。

**注意**:其他buffer object也是可以异步传数据的，PBO特殊就特殊在**纹理**

纹理在显存中的存储不是线性的，PBO的异步是异步在`glTextureSubImage2D` ，改变的是这个函数的行为，如下段代码：

```C++
glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pbo);
glTextureSubImage2D(texture, 0, 0, 0, WIDTH, HEIGHT, GL_RGBA, GL_UNSIGNED_BYTE, (void*)0);
glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
```

至于buffer中的数据是怎么来的和上述代码没关，可以选择使用namedbuffer或者map来将数据加载到缓存中。然后再从缓存中上传数据到纹理。



