### 顶点规范 vertex specification

顶点规范是指为特定着色器程序设置必要渲染对象（VAO\VBO等）的过程，以及使用这些对象进行渲染的过程（发起draw/call)。

下面就是介绍，有哪些对象，以及如何设置他们的属性展开。

---

#### 理论基础

**顶点流 vertex stream**

**顶点着色器中的属性列表定义了顶点流中必须提供的数据**

每个属性，都必须提供对应的数据数组，所有这些数组必须具有相同数量的元素。(每个属性都必须在每个顶点中存在)

顶点流是有顺序的。顶点数组有两种渲染方式，一种是按照数组的顺序生成数据流，另一种是使用索引列表。

在opengl中无论有几种属性，都只能有一个索引数组，每个属性都使用它。 

> 例：
>
> ``` { {1, 1, 1}, {0, 0, 0}, {0, 0, 1} }``` 顶点三维数据数组
>
> ``` { {0, 0}, {0.5, 0}, {0, 1} }```纹理数组
>
> ```{2, 1, 0, 2, 1, 2}```
>
> 生成stream ->
>
> ```  { [{0, 0, 1}, {0, 1}], [{0, 0, 0}, {0.5, 0}], [{1, 1, 1}, {0, 0}], [{0, 0, 1}, {0, 1}], [{0, 0, 0}, {0.5, 0}], [{0, 0, 1}, {0, 1}] }```

**图元 primitives**

**将数据流解释为何种图元类型。**

---

#### 顶点数组对象 vertex array object

> 见vertex array

 存储顶点数据format以及buffer objects（引用，并不是复制和冻结）。

顶点属性编号从0到GL_MAX_VERTEX_ATTRIBS - 1。当某个属性的数组访问被禁用，则获得一个常量值，而不是从数组中提取值。

``` glenablevertexarrayattrib(gluint vao, gluint index)```中index就是顶点属性编号。

---

#### 顶点缓冲对象 vertex buffer object

本质就是一个普通的buffer object。是顶点数据源。

---

#### 顶点格式 vertex format

```glVertexArrayAttribFormat(vao, 0, 3, GL_FLOAT, GL_FALSE, offsetof(Vertex, position));```

上述代码定义了解析这些数据的方式。

每个属性索引代表某种类型的向量，其分量长度只能为1~4,也就是上述例子中的size(3)。不必完全匹配vs使用的尺寸 (双精度除外）。vs少多余被忽略，vs多自动补全为（0, 0, 0, 1）。

**分量类型**

GL_FLOAT GL_UNSIGNED_BYTE等。

对于normalize:

GL_FALSE 浮点类型必须为这个，对于整数类型，按c语言风格直接转换， 如：255 -> 255.0f

GL_TRUE 整数类型进行归一化，如： 255 - > 1.0f

**矩阵**

对于矩阵，上面说了分量长度最大为4,所以矩阵会被拆分，占用多个顶点属性索引。

m行n列矩阵，占用n个顶点属性索引，每个索引大小为m。

---

#### 顶点缓冲区偏移量和步长

```glVertexArrayAttribFormat(vao, 0, 3, GL_FLOAT, GL_FALSE, offsetof(Vertex, position));```

offsetof(Vertex, position)是**relativeoffset**

**baseoffset** 是binding point 在buffer中的起始点。

累加的部分是 **vertexindex * stride** 。
$$
Address=BufferAddress+baseoffset+(i×stride)+relativeoffset
$$
stride和baseoffset在binding point设置

relativeoffset在format设置

---

#### index buffer

``` glvertexarrayelemnetbuffer(vao, ebo)```

绑定索引缓冲区到vao。

---

#### 实例化数组

> 除了让属性随着“顶点”变化，还可以让属性随着“实例”变化。

```
glEnableVertexArrayAttrib(vao, attrindex);
glVertexArrayBindingDivisor(GLuint vaobj, GLuint bindingindex, GLuint divisor)
```

你需要画一百个实例的“草丛”，每个草丛位置不一样。将100个位置存进普通的vbo,在读取的时候，根据instanceID来读。

通常情况下opengl读取的索引是```gl_VertexID```，设置Divisor后：index = gl_InstanceID / N

在vao设置并启用相关

由此对于实例数据也占用了一个顶点属性（占了一个vbo)。顶点属性opengl通常最多有16个。

---

### 顶点渲染 Vertex Rendering 

介绍顶点的绘制函数。这一过程是指数组中指定的顶点数据，并使用这些数据渲染图元的过程。

如上述，vao需要设置正确（使用索引需要绑定ebo)才能进行渲染。

非索引```gl*Draw*Arrays*```索引 ```gl*Draw*Elements*```

#### 图元重启

```c++
GLushort indices[] = {
    0, 1, 2, 3, 
    0xFFFF,      // 切断上面的 Strip，开始新的
    4, 5, 6, 7 
};
glEnable(GL_PRIMITIVE_RESTART);
glPrimitiveRestartIndex(0xFFFF);
glDrawElements(GL_TRIANGLE_STRIP, 9, GL_UNSIGNED_SHORT, 0);
```

一种```glMultiDrawElements```的替代方案

图元重启通常在使用STRIP图元时，用于打断当前的连续，开始新的连续。在draw call内部。

glmultiDrawElements相当于for循环里面调用draw call，减少调用次数。

```012 123 456 567```

#### 直接渲染

绘制命令将各种渲染参数直接作为函数参数提供。

##### Muti-Draw 多重渲染

**与上一次绘制命令使用不同的 VAO 进行渲染（绑定 VAO 或修改 VAO 状态），通常是一项开销较大的操作。**

>主要是cpu耗时：切换的时候，Driver会进行验证和生成命令等。
>
>gpu端：切换buffer,切换数据来源，vram->缓存

**注意**：dsa并不是bindless，不能消除硬件层面的状态切换开销，彻底解决的是bindless texture以及bindless graphics(gpu直接指针访问内存)。

```glMultiDrawElements```是一个原子操作，期间vao\vbo\ebo以及shader\uniform不更换。

相较于单次渲染的参数，其相关参数提供的是数组，并且在最后加了一个primcount用于指定渲染几次？

##### Base Index 基索引

```
void glDrawElementsBaseVertex( GLenum mode, GLsizei count,
   GLenum type, void *indices, GLint basevertex);
```

basevertex+索引。

**注意**：如果这时候有图元重启，重启测试发生在basevertex加之前

##### Instancing 实例化

渲染同一网格在不同位置的多个副本。

- 多次draw call并在期间更改着色器uniform❌
- 查一个表，根据当前顶点的实例编号进行索引。⭕
- 或者根据实例编号设计一个算法来计算位置。⭕ 
- 或者使用divisor，为每个实例提供不同的值。⭕ 实例化数组

```glDrawArraysInstanced``` 或者 ```glDrawElementsInstanced```

该调用会将相同的顶点数据发送instanceco unt次，上述所说的**实例编号**就是**gl_InstanceID**

**base instance**

仅在启用实例化数组的时候有用。

指定第一个实例。也就是读取实例化数组的**基础偏移量**。

**注意**：gl_InstanceID只和instancecount有关，不会受到base instance的影响。

#### Transform feedback

详情见 [transform feedback](./03Vertex Post-Processing.md)

#### 间接渲染（GPU Driven)

绘制命令的相关参数都存储在buffer object中

其目的是允许 GPU 进程（如下）来填充这些值。

- 计算着色器
- 一个专门设计并与变换反馈结合使用的几何着色器，
- 一个 OpenCL/CUDA  进程。

**其核心理念是避免 GPU->CPU->GPU 的往返过程；**

由 GPU 决定要渲染的顶点范围。CPU  所做的只是决定何时发出绘制命令，以及在该命令中使用哪种图元。

数据结构必须严格定义：

- 非索引渲染

```
typedef  struct {
   GLuint  count;
   GLuint  instanceCount;
   GLuint  first;
   GLuint  baseInstance;
} DrawArraysIndirectCommand;
```

- 索引渲染

```
typedef  struct {
    GLuint  count;
    GLuint  instanceCount;
    GLuint  firstIndex;
    GLuint  baseVertex;
    GLuint  baseInstance;
} DrawElementsIndirectCommand;
```

必须给默认赋值，否则会产生未定义数据。

如果使instanceCount或者count为0 ，则会跳过这一drawcall，可用于Culling。

**注意**：即使是DSA，也必须绑定GL_DRAW_INDIRECT_BUFFER。算是一个遗留问题。

```
glMultiDrawElementsIndirect(
    GLenum mode,
    GLenum type,
    const void *indirect,
    GLsizei drawcount,
    GLsizei stride
);
```

参数含义：

- stride 步长

相邻两条间接绘制命令之间的字节距离,必须是4的倍数，因为GLuint是4个字节，需要内存对齐。

$ Addr_{cmdi} = indirect + i * stride $

stride为0则默认紧密排列```stride == sizeof(DrawElementsIndirectCommand)```

例子：

```
#version 460 core
layout(local_size_x = 1) in;
layout(std430, binding = 0) buffer IndirectBuffer {
    DrawArraysCommand commands[]; 
};

void main() {
    uint idx = gl_GlobalInvocationID.x;

    commands[idx].count = 3;          // 画一个三角形 (3个点)
    commands[idx].instanceCount = 1;  // 画 1 个实例
    commands[idx].first = 0;          // 从第 0 个顶点开始
    commands[idx].baseInstance = idx; // 实例 ID 偏移
}
```

```c++
GLuint indirectBuffer;
glCreateBuffers(1, &indirectBuffer); // DSA: 直接创建，不需要先 bind

size_t bufferSize = 100 * sizeof(DrawArraysCommand);
// GL_DYNAMIC_STORAGE_BIT 因为我们会频繁写入
glNamedBufferStorage(indirectBuffer, bufferSize, nullptr, GL_DYNAMIC_STORAGE_BIT);

// --- loop ---
{
    glUseProgram(computeShaderID);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, indirectBuffer);
    glDispatchCompute(100, 1, 1);
}

glMemoryBarrier(GL_COMMAND_BARRIER_BIT | GL_SHADER_STORAGE_BARRIER_BIT);

{
    glUseProgram(renderShaderID);
    glBindVertexArray(vao); 
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, indirectBuffer);
    // 参数：模式, 偏移量(buffer中的字节偏移), 绘制次数(100个命令), 步长(0=紧密排列)
    glMultiDrawArraysIndirect(GL_TRIANGLES, 0, 100, 0);
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, 0);
}
```

##### indirect count 间接计数

```C++
void glMultiDrawArraysIndirectCount( GLenum mode, const void *indirect,
   GLintptr drawcount, GLsizei maxdrawcount, GLsizei stride );
```

```c++
void glMultiDrawElementsIndirectCount( GLenum mode, GLenum type,
   const void *indirect, GLintptr drawcount, GLsizei maxdrawcount, GLsizei stride );
```

drawcount定义了指向```GL_PARAMETER_BUFFER```的字节偏移量，4的倍数。

**stream compaction**

例子：

在culling中你有10000个物体，但是只有5个需要绘制，其余的instanceCount置为0.

cs里面设置一个计数器```index = atomicCounterIncrement(counter)```

把命令写在index位置。内存是紧凑的有效的。

外面不知道有几个命令，但是设定maxdrawcount 10000

```c++
const GLuint zero = 0;
glNamedBufferSubData(countBuffer, 0, sizeof(GLuint), &zero);

glUseProgram(computeShader);
glBindBufferBase(GL_ATOMIC_COUNTER_BUFFER, 0, countBuffer); // 绑定计数器
// ... 绑定其他 buffer ...
// glDispatchCompute(...);
glMemoryBarrier(GL_COMMAND_BARRIER_BIT | GL_ATOMIC_COUNTER_BARRIER_BIT);

glUseProgram(renderShader);
glBindVertexArray(vao);
glBindBuffer(GL_DRAW_INDIRECT_BUFFER, cmdBuffer);
glBindBuffer(GL_PARAMETER_BUFFER, countBuffer); //告诉GPU去读countBuffer的数量

glMultiDrawArraysIndirectCount(GL_TRIANGLES, 0, 0, 10000, 0);
```

#### 条件渲染

