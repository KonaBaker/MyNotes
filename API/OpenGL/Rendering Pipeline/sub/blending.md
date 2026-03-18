# Blending

combine从fs输出的颜色with color buffer中的颜色。blending参数控制如何blend

blending只对output中的color有效。

如果dst的buffer的format是非归一化的UI则这个buffer的blend直接跳过。

`GL_RGB8` 这种就是归一化的unsigned integer sampler采样会映射到[0,1]

`GL_RGB8UI`这种就是非归一化的 不解释，直接拿整数。

## usage

`glEnablei(GL_BLEND, i)` 启用缓冲区i的blend

也可以使用`glEnable(GL_BLEND)`全部启用。

当启用混合时，将使用以下混合方程之一来确定写入该缓冲区的颜色。

**Notes:**请注意，仅当图像格式为某种浮点类型时，混合才对特定缓冲区有效。可以是常规浮点数或归一化整数。如果是未归一化整数，则该缓冲区的混合行为将如同禁用混合一样。

### equations

S是源颜色，D是buffer中的颜色，s是源参数，d是目标参数。

```c++
void glBlendEquationSeparate(GLenum modeRGB, GLenum modeAlpha);
```

- `GL_FUNC_ADD ` O = sS + dD
- `GL_FUNC_SUBTRACT`  O = sS - dD
- `GL_FUNC_REVERSE_SUBTRACT `O = dD - sS
- `GL_MIN` Or = min(Sr, Dr)，Og = min(Sg, Dg)   s,d被忽略
- `GL_MAX `输出颜色是源颜色和目标颜色各分量的最大值

### parameters

```
* Orgb = srgb * Srgb FUNC drgb * Drgb
* Oa = sa * Sa FUNC da * Da
```

用户可以为each drawbuffer声明不同的blending参数。

```C++
 void glBlendFuncSeparate(GLenum srcRGB, GLenum dstRGB, GLenum srcAlpha, GLenum dstAlpha);
 void glBlendFuncSeparatei(GLuint buf, GLenum srcRGB, GLenum dstRGB, GLenum srcAlpha, GLenum dstAlpha);
```

buf是drawbuffer的index.剩下的就是指定s,d参数

参数可以取：

- `GL_ONE `/`GL_ZERO `
- `GL_SRC_COLOR `/`GL_DST_COLOR `
- one minus之类的
- `GL_CONSTANT_COLOR`相关系列，通过`glBlendColor`设置，作为这个 参考/状态 颜色值，单次DC内无法更改

---

## 双源混合

## 半透明

【详见 graphics杂项 半透明渲染】
