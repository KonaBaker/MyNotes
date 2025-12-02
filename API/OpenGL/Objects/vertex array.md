### vertex array

``` glenablevertexarrayattrib(gluint vao, gluint index)```

使用dsa直接启用属性数组。

``` glVertexArrayVertexBuffer```

将一个vbo绑定到一个buffer binding point（其取值范围为 0 到 GL_MAX_VERTEX_ATTRIB_BINDINGS - 1，通常该值为 16）。并指定stride和offset

> 不是GL_MAX_VERTEX_ATTRIB，不是顶点属性

``` glVertexArrayAttribFormat```

规定顶点数组的组织方式。这里是attribindex，是属性索引（范围从 0 到 GL_MAX_VERTEX_ATTRIBS-1）

最后一个参数relativeoffset，是一个**新增概念**。为了不同attrib使用同一个buffer(共享了stride和offset)，但是想实现**属性交错**表示从绑定的顶点缓冲区的起始位置到需要的第一个元素的距离（offset + relativeoffset）。

``` glVertexArrayAttribBinding```

将一个顶点属性和buffer binding关联（即一个attribindex和一个bindingindex）

``` glvertexarrayelemnetbuffer(vao, ebo)```

绑定索引缓冲区到vao。



**buffer binding point**: 聚合了以下数据：

- buffer objects
- 该绑定点所有顶点属性的基础字节偏移量
- 该绑定点所有顶点属性的字节步长
- 该绑定点所有顶点属性的instance divisor

**format**:

- 哪些属性处于开启状态（但仍由```glenablevertexarrayattrib```控制)
- 顶点属性数据的大小、类型以及归一化设置
- 关联的buffer binding point
- 从其关联缓冲区绑定点基址偏移到顶点数据起始位置的字节偏移量



例子：

```
struct Vertex
{
  GLfloat position[3];
  GLfloat normal[3];
  Glubyte color[4];
};
 
Vertex vertices[VERTEX_COUNT];
```

```c++
// 将buff这个buffer object 绑定到vao上的binding point 0,步长是Vertex结构体的大小。
glVertexArrayVertexBuffer(vao, 0, buff, baseOffset, sizeof(Vertex));

// 开启vao中顶点属性索引0
glEnableVertexArrayAttrib(vao, 0);
// 顶点属性索引0 的大小类型。relativeoffset是成员的偏移。
glVertexArrayAttribFormat(vao, 0, 3, GL_FLOAT, GL_FALSE, offsetof(Vertex, position));
// 将顶点属性索引和buffer binding point相关联。
glVertexArrayAttribBinding(vao, 0, 0);
glEnableVertexArrayAttrib(vao, 1);
glVertexArrayAttribFormat(vao, 1, 3, GL_FLOAT, GL_FALSE, offsetof(Vertex, normal));
glVertexArrayAttribBinding(vao, 1, 0);
glEnableVertexArrayAttrib(vao, 2);
glVertexArrayAttribFormat(vao, 2, 4, GL_UNSIGNED_BYTE, GL_TRUE, offsetof(Vertex, color));
glVertexArrayAttribBinding(vao, 2, 0);
```

上述函数对于buffer binding point以及format的操作以及数据都是在vao的状态范畴，被封装在

vertices就是顶点流。buff就是承载顶点的buffer,是一个数据源。vertex array就是一个包含format和buffer引用的object。
