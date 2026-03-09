# Vertex Shader

负责单个顶点的处理工作。从**VAO**中获得**vertex attribute**

## invocation frequency

如果opengl检测到某个顶点着色器调用与之前的调用具有相同的输入，则可以重用之前的调用结果。

但是opengl实现通常不会通过实际比较输入值来进行优化，它只会在使用**索引渲染**的时候才会优化。

例如在**实例化**渲染中，多次指定某个相同的索引。



顶点着色器的调用次数是可能少于指定的顶点数量的。但是能保证使用的每一组特定的vertex arrtibute会有一次调用。

## inputs

用户输入的值被称作**vertex attribute**,通过drawcmd绑定VAO来提供。

通过loaction指定attribute index。

```
layout(location = 2) in vec4 a_vec;
```

**注意** 顶点着色器的输入不能被聚合到interface blocks

### multiple attributes

有些类型比较大，需要分配多个index,例如矩阵。

- 矩阵每列占用一个属性索引。

- 数组每个元素占用一个(即使数组元素为float类型)。

- double dvec只占用一个索引。但是implementations中可能会count两次，这取决于具体怎么实现。占用一次但是count两次也可能会导致链接失败。

```
layout(location = 3) in mat4 a_matrix;
```

a_matrix被分配3\4\5\6四个索引。

如果索引发生冲突，则链接失败。

### attribute limit

数量限制`GL_MAX_VERTEX_ATTRIBS`

### internal inputs

`in int gl_VertexID`

当前正在处理的顶点id

- 非索引渲染：已处理顶点 + `first`值 + basevertex
- 索引渲染：索引

`in int gl_InstanceID`

实例化渲染时候的实例ID。其余时候为0

[0, instancecount)， 不与baseinstance叠加。

`in int gl_DrawID`

multi-draw中绘制命令的索引。

`in int gl_BaseVertex`

drawcmd中的basevertex，如果没有则为0.

`in int gl_BaseInstance`

drawcmd中的baseinstance,如果没有则为0.

## outputs

-> tcs/tes -> gs -> vertex post-processing

user-defined的output可以使用interpolation qualifiers(到post process才生效)

output可以被聚合到interface blocks

预定义输出interface blocks：

```c++
out gl_PerVertex
{
  vec4 gl_Position;
  float gl_PointSize;
  float gl_ClipDistance[];
};
```

注意：只有在vs后面紧接着post-process也就是没有tes\gs等的时候，以及光栅化处于活动状态，以及`GL_RASTERIZER_DISCARD`未启用的时候，这些预定义输出才可以用。

`gl_Position`

输出clip_space的位置

`gl_PointSize`

渲染点图元的时候，光栅化中的点高度和宽度。

`gl_ClipDistance`

user-defined clipping half-space【详见user-defined clipping】





---

unarchived

### post transform cache

https://wikis.khronos.org/opengl/Post_Transform_Cache

是一个内存缓冲区，存储已通过顶点处理阶段但尚未转换为图元的顶点数据。

判断方法：若两个顶点的索引和实例计数相同gl_VertexID gl_InstanceID则被视为相等顶点。

