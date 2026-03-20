UBO是一种buffer objects，

- 用于存储uniform data, for a shader program。存储的数据量更多。

- 用于在不同的programs之间共享uniforms

- 或者用于在相同的program中快速切换一组uniform。

uniform buffer object -> opengl buffer obejct

uniform blocks -> glsl, grouping of uniforms come from **buffer objects**

### opengl usage

buffer objects 和 uniform block类似于texture objects和sampler uniforms

binding location也类似于image binding unit

> `GLuint glGetUniformBlockIndex( GLuint program, const char *uniformBlockName );`
>
> block index是glsl中的概念，类似于uniform的location。我们需要在程序中获取他的位置
>
> `void glUniformBlockBinding( GLuint program, GLuint uniformBlockIndex, GLuint uniformBlockBinding );`
>
> binding ： 0 ~ GL_MAX_UNIFORM_BUFFER_BINDINGS - 1
>
> 现在binding上有了uniformblock，我们还需要在binding上绑上我们的buffer objects

**DSA**

上面两个都用不到了，直接在glsl中显式写binding

```c++
layout(std140, binding = 0) uniform Matrices {
    mat4 projection;
    mat4 view;
};
```

```c++
glBindBufferBase(GL_UNIFORM_BUFFER, 0, uboID);
```

### limiations

`GL_MAX_UNIFORM_BUFFER_BINDINGS`限制整个context的绑定数量。

对于每个shader stage也是有限制的：
`GL_MAX_VERTEX_UNIFORM_BLOCKS`, `GL_MAX_GEOMETRY_UNIFORM_BLOCKS`, or` GL_MAX_FRAGMENT_UNIFORM_BLOCKS.`

SSBO的限制通常比UBO要宽松许多



UBO不能使用std430的内存布局。
