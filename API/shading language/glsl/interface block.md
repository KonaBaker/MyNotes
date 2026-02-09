### interface block

```c++
storage_qualifier block_name
{
  <define members here>
} instance_name;
```

**storage_qualifier**可以是以下几个：决定了是哪种block, interface block **包括 uniform block**

- uniform
- in or out
- buffer

**block name**：在**opengl**中使用（DSA一般用不到）

**instance name** : 在**glsl**中使用，optional. .访问成员需要`instance_name.member`.如果没有声明，意味着是全局的，那么可以直接访问成员`member`，此时如果在block外声明同名member就会编译错误。

instance name更像是一个**名字空间**。**注意：不能类比结构体和实例化对象这一概念**

也就是说对于相同的定义，不同阶段的不同instance name是指向同一块显存的，他们都通过block name绑定在opengl程序的一个binding point(**context级别槽位**）上。

只不过dsa省略了使用block name的过程。

**Block数组**

```c++
layout(std140, binding = 0) uniform Matrices {
    mat4 view;
    mat4 proj;
} mats[3];
```

这样的数组会在opengl程序中展开成三个不同的uniform block，他们的block name分别为`Matrices[0]` `Matrices[1]` `Matrices[2]`

mats只是在glsl用于访问。

相应的，这里声明的binding点也会自动递增。

在c++中要这样写：

```c++
GLuint ubo[3]; 
glCreateBuffers(3, ubo);

glBindBufferBase(GL_UNIFORM_BUFFER, 5, ubo[0]);
glBindBufferBase(GL_UNIFORM_BUFFER, 6, ubo[1]);
glBindBufferBase(GL_UNIFORM_BUFFER, 7, ubo[2]);
```

对于UBO和SSBO访问的时候的索引必须是**动态统一**的，在同一个draw call并行绘制的线程必须访问同一个数组索引

```
lights[0].color // ✅
lights[gl_VertexID % 4].color // ❌
```

**接口匹配**
两个块具有相同的名字才能匹配。

除了名字匹配以外，限定符，成员顺序，成员限定符，块数组计数，还有binding点都必须一致，且要么都有实例名称，要么都没有实例名称。

只要名字相同就匹配，如果出现不一致，就会触发link error。

匹配成功，也就是链接到同一程序，就会呈现为**单个接口块**

**输入与输出**

## Buffer Backed

这部分UB和SSB是相似的，所以加下来介绍得是通用的

> buffer backed 表示他们是来自于 buffer object

**矩阵存储顺序**

`layout(row_major/column_major) uniform MatrixBlock`

但是这并不会改变glsl的处理方式，glsl**永远是**列主序的，它只会影响glsl从buffer中获取数据的方式。

**内存布局**

默认是shared

编译器说了算：需要openglAPI查询偏移量。

- packed

为了节省空间，尽可能紧凑的挤压变量，把一些不用的变量优化掉。不同驱动程序结果可能不同。

不同shader之间也不能共享，每个shader编译出来的布局可能也不同。

- shared

和packed一样，除了以下两点：

1.不会优化掉变量。

2.在不同program之间的相同定义，保证相同的布局，也就是可以共享。

同时也会要求

标准说了算：

- std140

比较浪费，强制对齐单元N

- std430

仅SSBO，比std430更紧凑，类似c++struct中的对齐方式。SSBO一般采用这个。

- 

