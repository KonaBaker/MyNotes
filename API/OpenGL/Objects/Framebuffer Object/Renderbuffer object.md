# Renderbuffer object

一种包含图像的OpenGL对象，与framebuffer objects配合使用。

专门针对作为render target做了优化，当不需要对image进行采样的时候，应该选用renderbuffer object而不是texture object.

不能直接上传/下载texel。只能分配存储空间

- 只用于depth/stencil测试，不采样
- MSAA

## use

在attach到FBO上，并且设置好draw/read buffer后，可以使用pixel transfer来对RBO进行读写。或者渲染到它上面。

**RBO怎么读？**

blit到一个附加了texture的FBO。然后gettexturesubimage 读texture

```c++
GLuint rbo = 0;
glCreateRenderbuffers(1, &rbo);
glNamedRenderbufferStorage(rbo, internalFormat, width, height);

GLuint fbo = 0;
glCreateFramebuffers(1, &fbo);
glNamedFramebufferRenderbuffer(
    fbo,
    GL_DEPTH_STENCIL_ATTACHMENT,   // 或 GL_DEPTH_ATTACHMENT / GL_STENCIL_ATTACHMENT / GL_COLOR_ATTACHMENTi
    GL_RENDERBUFFER,
    rbo
);
```

