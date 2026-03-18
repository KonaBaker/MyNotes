# Write Mask

allows or prevents color,depth,stencil components from being written to the current framebuffer.

fragments可以包含多个颜色值、一个深度值、一个模板值。除了stencil,其他都可以由fs生成。

Masking state会影响对current framebuffer的操作：

- All DCs
- framebuffer clearing

**notes**：影响的是通过framebuffer写入image的操作，这不包括image load/store(虽然同时写入一个image是ub0)

write mask不属于framebuffer的一部分。

## color mask

```c++
void glColorMaski(GLuint buf, GLboolean red, GLboolean green, GLboolean blue, GLboolean alpha);
```

GL_TRUE 以启用对应分量的写入，设置为 GL_FALSE 以禁用写入。

`glColorMask`

## depth mask

```c++
 void glDepthMask(GLboolean flag);
```

将 flag 参数设置为 GL_TRUE 表示允许深度写入。

## stencil mask

```c++
void glStencilMaskSeparate(GLenum face, GLuint mask);
```

这个mask是控制写入的mask和 stencil test中func指定的计算的mask不同。
