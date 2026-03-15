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



**FBO基本上贯穿从光栅化开始的后续管线。**它是这个阶段的“执行环境”或者“存储模型”

它的结构和参数影响fragment写入、test、sample、颜色空间等多种流程/行为



## FBO结构

`glCreateFramebuffers` 创建FBO



`glBindFramebuffer()`

`GL_FRAMEBUFFER`, `GL_READ_FRAMEBUFFER`, or `GL_DRAW_FRAMEBUFFER`

这三个target虽然在配置阶段用不着了，但是**在使用也就是绘制（还有blit等等需要操作）**的时候，还是要将FBO绑定到上述三个target上。

- glDraw*绘制的时候需要bind draw
- glClear的时候需要bind draw
- readpixel需要bind read
- blit需要bind read + draw    4.5+ -> `glBlitNamedFramebuffer(srcFBO, dstFBO, ...);`



FBO中有很多attachment point,每个point都可以附加一个image: //一般是texture 或者 renderbuffer(专门用作attachment的存储object)

- `GL_COLOR_ATTACHMENTi` 

`GL_MAX_COLOR_ATTACHMENTS` 至少为8。只能绑 **color-renderable** format的image。压缩格式不可以。

- `GL_DEPTH_ATTACHMENT`

只能绑定depth format的格式。成为depth buffer。如果没有attach将禁用深度测试。

- `GL_STENCIL_ATTACHMENT`

模板格式。成为stencil buffer.

- `GL_DEPTH_STENCIL_ATTACHMENT`

**注意**： depth buffer/stencil buffer【详见per-sample processing】不是object，只是一个**用途/角色**



## Attaching Images

`glNamedFramebufferTexture(framebuffer, attachment, texture, level)` 

or `glNamedFramebufferRenderbuffer(framebuffer, attachment, renderbuffertarget, renderbuffer)` 进行附加操作

buffertexture无法附加到framebuffer上。

texture可以容纳多个image所以在附加texture的时候需要通过layer/level指定是哪一张。**注意** dsa模式无法指定layer，所以对于3D则被认为附加的是layered。

renderbuffertarget必须为`GL_RENDERBUFFER`



## Layered Images

和layered rendering配合使用【详见Geometry shader】



## Empty framebuffers

向一个没有任何附着(空的)framebuffer进行渲染，过程可以正常进行，但是fs的输出不会被写入任何地方。

主要用于**image load/store**。

例如在fs中

```c++
layout(rgba32f, binding = 0) uniform image2D img;

imageStore(img, ivec2(x,y), value);
vec4 v = imageLoad(img, ivec2(x,y));
```

**为什么仍然需要绑定一个FBO呢？**

opengl的draw仍然是一个 framebuffer-based pipeline

在光栅化阶段需要

- 定义渲染区域（真正写入像素的范围，是FBO的image尺寸） viewport只是决定屏幕大小。
- 是否有depth test（有无depth attachment,是否允许写入，以及在fs之前的earlyz)
- 定义sampler count

此时的framebuffer是一个**光栅化执行环境**

但是一些属性通常由附加的image定义，在没有attachment的情况下，需要通过`glNamedFramebufferParameteri`进行设置。

`GL_FRAMEBUFFER_DEFAULT_WIDTH`等

附加的image属性会覆盖上述函数设置的属性。



## colorspace

线性或者sRGB。

`GL_FRAMEBUFFER_SRGB`

- 禁用，不进行任何色彩空间的矫正
- 启用，且目标的image处于sRGB，将会进行线性(shader输出)到sRGB的转换

当开启时，针对**sRGB format的color attachment**的logical op将会被禁用

如：`GL_SRGB8`的internal format,并不是指texture是否被当成sRGB采样。

**Blending**

线性插值sRGB空间会导致颜色不准确。

在启用`GL_FRAMEBUFFER_SRGB`的时候，将会经历sRGB -> RGB -> blending -> sRGB

对于源值，采样而来已经是线性。



## 完整性

使用 设置不当或者不完整 的FBO会导致错误，无需手动调用检查，这里只做概念解释。

【详细规则见https://wikis.khronos.org/opengl/Framebuffer_Object】

### attachment完整性

空的附件默认是完整的。附加了需要遵守尺寸范围和特定格式。

### 完整性规则

一些需要满足的规则：比如：

如果一个layered image 被attach那么所有的attachment必须都是layered。但是层数不必相同，也不必来自同一种纹理。等



## feedback loop 

【详见memory model】



## Read color buffer

从read color buffer获取（读取）数据的方式：

- 下面的buffer read部分
- blit
- copy to texture

read color buffer的数量只能是一个。

- 对于FBO`glNamedFramebufferReadBuffer(fbo, GL_COLOR_ATTACHMENT2);`
- 对于default`glReadBuffer(GL_BACK);` 通常不必手动设置



framebuffer  `glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo_or_0);` **此步骤必须绑定** for glReadPixels

-> read buffer  `glNamedFramebufferReadBuffer(fbo, GL_COLOR_ATTACHMENT0);` or `glReadBuffer(GL_BACK);`

->指定区域 `glReadPixels(...);`



## Draw color buffers

可以有多个。

- 对于FBO`glNamedFramebufferDrawBuffers(framebuffer, n, const GLenum *bufs)`
- 对于default`glDrawBuffer(GL_BACK)` 通常不必手动设置



整个framebuffer的定向流程是这样的。

shader中的`layout(location = x) out`         |指定在drawbuffer中的位置

-> `drawbuffers[x]`                              		|将attachment加入到drawbuffer中

-> attachment                                         	       |将texture/renderbuffer附加到attachment上         

-> texture/renderbuffer

```c++
// attachment附加texture
COLOR_ATTACHMENT0 → albedo
COLOR_ATTACHMENT1 → normal
COLOR_ATTACHMENT2 → material

// attachment加到drawbuffer中
GLenum bufs[] = {
    GL_COLOR_ATTACHMENT0,
    GL_COLOR_ATTACHMENT1,
    GL_COLOR_ATTACHMENT2
};
glNamedFramebufferDrawBuffers(fbo, 3, bufs);

// location指定drawbuffer中的位置
layout(location=0) → albedo
layout(location=1) → normal
layout(location=2) → material
```



配置完drawbuffer/readbuffer就可以

`glBindFramebuffer(GL_FRAMEBUFFER, fbo)`  几乎只用`GL_FRAMEBUFFER`不用管别的。

然后调用drawcall就可以了



## buffer read

`void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, GLvoid * data)`

读取到data或者PBO，通过**format指定**从哪里读

比如：

`GL_DEPTH_COMPONENT`  从 depth buffer读。

`GL_RGBA`从color buffer读 。

`GL_DEPTH_STENCIL` depth buffer和stencil buffer都读。

### read color clamp

`void glClampColor(GL_CLAMP_READ_COLOR, clamp)`

如果从中读color的话，可已使用这个函数进行限制：

- GL_TRUE [0,1]
- GL_FALSE OFF
- GL_FIXED_ONLY normalized signed or unsigned will be clamped



**注意**：read buffer和draw buffer都是color buffer，只针对于color attachment

对于readpixel或者blit如果涉及到的是depth或者stencil attachment，是不会受到这两个buffer设置影响的。

## buffer clear

> Images in a framebuffer may be cleared to a particular value.

- 只有没被Mask的才会被clear更改
- 未通过pixel ownership test的pixel会有未定义的值。
- scissor test/
- rasterize discard if discard，clear就会被忽略。

`glClearNamedFramebuffer{iv|uiv|fv|fi}(framebuffer_or_0, buffer, drawbuffer, value)`

depth一般用fv,depth+stencil用fi,

- framebuffer是name

- buffer是`GL_COLOR` `GL_DEPTH` `GL_DEPTH_STENCIL` or `GL_STENCIL`
- drawbuffer是index，对于depth和stencil来说必须是0

clear的是drawbuffer，对于default framebuffer需要提前`glDrawBuffer(GL_BACK)`指定



## API使用

`glBlitNamedFramebuffer`

`glClearNamedFramebuffer`

都可以传入default 0

但是对**对象状态的操作**不可以使用

**A) 设置/查询 draw/read buffer（FBO 版）**

- `glNamedFramebufferDrawBuffers(fbo, ...)`
- `glNamedFramebufferDrawBuffer(fbo, ...)`
- `glNamedFramebufferReadBuffer(fbo, ...)`

没有指定的attachment

default framebuffer 要用：

- `glDrawBuffer(GL_BACK/GL_FRONT/...)`
- `glReadBuffer(GL_BACK/GL_FRONT/...)`

**B) 挂附件（attachments）**

- `glNamedFramebufferTexture`
- `glNamedFramebufferRenderbuffer`
- `glNamedFramebufferTextureLayer`
- `glNamedFramebufferParameteri`

同理，attachment由平台决定，已经固定无法更改。

**C) 查询 FBO attachment 信息**

- `glGetNamedFramebufferAttachmentParameteriv`
- `glGetNamedFramebufferParameteriv`
