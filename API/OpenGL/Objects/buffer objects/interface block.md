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

**矩阵存储顺序**

**内存布局**

