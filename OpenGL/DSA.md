直接状态访问(DSA)是一种无需将 OpenGL 对象绑定到上下文即可修改它们的方法。这使得开发者能够在局部上下文中修改对象状态，而不会影响应用程序所有部分共享的全局状态。

所有函数都明确指定了操作对象，函数名称也会变得更长。

Tex->Texture

Framebuffer->NamedFramebuffer

buffer->namedbuffer

但是有一些在原来就使用了dsa的风格的旧命名函数就没有再增加新的。

 EXT_DSA & DSA

- 在 EXT_DSA 中，所有 DSA 风格的函数都允许接收尚未关联状态数据的对象名称（即未被绑定过的对象）。因此这些函数需要具备为这些名称生成默认状态的能力，然后再执行常规处理逻辑。如果向任何核心 DSA 函数传递没有状态的对象名称，它们会返回 GL_INVALID_OPERATION 错误。
- 在 EXT 版本中，所有用于修改纹理的 DSA 函数都需要同时接收纹理对象和纹理目标。而核心函数则无需如此，因为纹理类型在对象状态创建时（无论是通过 glBindTexture 还是 glCreateTextures）就已确定。