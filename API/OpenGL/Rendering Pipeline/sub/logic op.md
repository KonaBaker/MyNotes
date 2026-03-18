# Logical Operation

fragment output color和framebuffer color的逻辑运算操作。

## Activation

启用`GL_COLOR_LOGIC_OP`.启用之后blend就会被禁用。

按位的bool运算，需要满足以下条件：

- framebuffer的image需要时整数，无论是否normalized
- srgb渲染被禁用，或者启用的情况下，framebuffer 的image也不在srgb中。（语义使然）

## operations

```c++
void glLogicOp(GLenum opcode);
```

默认是`GL_COPY`

片段颜色的分量值记为 S；帧缓冲图像的分量值记为 D

opcode：

| **Opcode**       | **Resulting Operation** |
| ---------------- | ----------------------- |
| GL_CLEAR         | 0                       |
| GL_SET           | 1                       |
| GL_COPY          | **S**                   |
| GL_COPY_INVERTED | ~**S**                  |
| GL_NOOP          | **D**                   |
| GL_INVERT        | ~**D**                  |
| GL_AND           | **S** & **D**           |
| GL_NAND          | ~(**S** & **D**)        |
| GL_OR            | **S** \| **D**          |
| GL_NOR           | ~(**S** \| **D**)       |
| GL_XOR           | **S** ^ **D**           |
| GL_EQUIV         | ~(**S** ^ **D**)        |
| GL_AND_REVERSE   | **S** & ~**D**          |
| GL_AND_INVERTED  | ~**S** & **D**          |
| GL_OR_REVERSE    | **S** \| ~**D**         |
| GL_OR_INVERTED   | ~**S** \| **D**         |

---

**Notes**

现代引擎使用较少了，而且没有“颜色混合/加权”这种概念