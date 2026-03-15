# per sample processing

对从fragment shader中输出的fragments进行处理，将结果数据写入各种buffer

## early operations

某些操作可以在fs之前执行

- po test
- scissor
- stencil
- depth
- occlusion query

它们不只是测试，还包括写入操作，如果它们在fs之前执行，即使是discard，也会对buffer进行写入。

现在pixel ownership test以及scissor已经**强制提前执行**。

## pixel ownership test

default framebuffer背后渲染到屏幕的窗口资源，不由opengl完全控制，属于外部资源。

窗口资源由系统创建和管理：

- Windows 下的 WGL / GDI / DWM

- Linux 下的 GLX / EGL / X11 / Wayland

可能由于屏幕遮挡，导致一些pixels不由opengl持有或控制，fail to pass po test,那么覆盖这些pixels的fragments就会被丢弃。

仅影响default framebuffer,不会影响FBO。

## scissor test

【详细见 scissor test】

可以指定目标framebuffer的一个矩形区域作为有效的渲染区域。其余地方的会被丢弃。

## multisample

【详细见 multisamping】

## stencil test

【详细见 stencil test】

> The stencil test, when enabled, can cause a fragment to be discarded  based on a **bitwise operation** between **the fragment's stencil value** and  **the stencil value stored in the current Stencil Buffer** at that fragment's sample position.

允许用户根据模板有条件的剔除片段。

[tag] sample是什么意思，为什么是sampler。

## depth test

【详细见 depth test】

> between the fragment's depth value and the depth value stored in the current Depth Buffer

## occlusion query

【详细见occlusion query】

若片段通过深度测试（且仅检查是否通过深度测试）,若查询为 GL_SAMPLES_PASSED 类型，计数器将递增；若为布尔型查询之一，布尔值将被设为真。

## blending

【详细见 blending】

## srgb conversion

## dithering

## logic op

【详细见 logic op】

## write mask

【详细见 write mask】

