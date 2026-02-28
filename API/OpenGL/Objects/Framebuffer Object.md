# Framebuffer Object

## 概念

> Framebuffer objects are a collection of attachments

**image**
二维像素数组，这些像素有特定的格式。

**layered image**
单个mipmap中的一组images。

**texture**

texture object

**renderbuffer**

包含single image的图像。着色器无法访问。只能被创建，或者被附加到FBO中。

**attach**
对象之间互相附加。

**attachment point**
A named location within a framebuffer object that a **framebuffer-attachable image** or l**ayered image** can be attached to.

其限制了附加image的format.

**framebuffer-attachable image**

能够attach到FBO的image

**Framebuffer-attachable layered image**

能够attach到FBO的layered image



## FBO结构

`glCreateFramebuffers` 创建FBO

`glNamedFramebufferTexture` or `glNamedFramebufferRenderbuffer` 进行附加操作

`GL_FRAMEBUFFER`, `GL_READ_FRAMEBUFFER`, or `GL_DRAW_FRAMEBUFFER`

这三个target虽然在配置阶段用不着了，但是在使用也就是绘制的时候，还是要将FBO绑定到上述三个target上。

FBO中有很多attachment point,每个point都可以附加一个image: //一般是texture 或者 renderbuffer(专门用作attachment的存储object)

- `GL_COLOR_ATTACHMENTi` 

`GL_MAX_COLOR_ATTACHMENTS` 至少为8。只能绑 **color-renderable** format的image。压缩格式不可以。

- `GL_DEPTH_ATTACHMENT`

只能绑定depth format的格式。成为depth buffer。如果没有attach将禁用深度测试。

- `GL_STENCIL_ATTACHMENT`

模板格式。成为stencil buffer.

- `GL_DEPTH_STENCIL_ATTACHMENT`

**注意**： depth buffer/stencil buffer不是object，只是一个**用途/角色**

## Attaching Images

