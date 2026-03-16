# scissor test

启用`GL_SCISSOR_TEST`

使用

```c++
void glScissor(GLint x, GLint y, GLsizei width, GLsizei height);
```

定义裁剪框。

x,y是左下角位置，width,height是尺寸。

## scissor array

对于多viewport的情况使用

`glEnablei`以及

```c++
void glScissorIndexed(GLuint index, GLint left, GLint bottom, GLsizei width, GLsizei height);
void glScissorIndexedv(GLuint index, const GLint *v);
void glScissorArrayv(GLuint first, Glsizei count, const GLint *v);
```

数组v中，每4个元素对应一个viewport

## 受影响的命令

只影响向current draw framebuffer （绑定到`GL_DRAW_FRAMEBUFFER`）写值的rendering commands。例如gldraw或者glclear。

computer shader 的 dispatch不受影响。