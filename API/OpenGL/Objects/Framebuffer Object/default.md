# Default Framebuffer

default framebuffer在opengl上下文创建的时候就被创建了。并不是一个普遍意义上创建的FBO(user-defined/created)。是context的一部分，代表窗口或者显示设备所有的default image都自动根据output window尺寸进行调整。标识值是0

它的属性由平台决定。

它也是有attachment的，只不过是平台赋予，固定的，无法更改。下面的color buffers就相当于是固定的color attachment

**default framebuffer不是一个object**，因此没有named、create、delete等方法。

`glDrawBuffer(GLenum buf)` 一般用于 default framebuffer。buf指定color buffer。



以下的buffer就相当于user-defined FBO中 color attachment.指一个特定位置。

## color buffers

系统提供的颜色存储平面（相当于user-defined FBO中的color attachment），不是texture，不是renderbuffer也不是buffer object。

默认的帧缓冲，最多有四个color buffers

- `GL_FRONT_LEFT`
- `GL_BACK_LEFT`
- `GL_FRONT_RIGHT`
- `GL_BACK_RIGHT`

**单缓冲**： 只有front buffer直接显示

**双缓冲**： front + back(绘制到back，然后swap) swap不一定是真的swap，复制或者直接成为都有可能。

> 不建议对front进行渲染或者读取操作。

**立体**：消费级显卡基本没有，left + right。所以平常也用不到right,只会用left。

## depth buffer

`GL_DEPTH`有一个默认的depth buffer用于depth test

## stencil buffer

`GL_STENCIL`有一个默认的stencil buffer用于stencil test.

## pixel ownership test

只针对default framebuffer。对于user FBO无效。

- 窗口被遮挡
- 窗口被最小化
- 被部分移除屏幕
- 被另一个窗口覆盖

发生以上情况的像素片元会被丢弃。

```c++
Pixel Ownership Test
↓
Scissor
↓
Stencil
↓
Depth
↓
Blending
```