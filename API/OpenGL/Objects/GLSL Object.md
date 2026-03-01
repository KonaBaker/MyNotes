# GLSL Object

是一种object。封装已编译或已链接的着色器。代表了用glsl所编写的代码。虽然object，但是大多数并不符合常规object的一些规则。

对于整个编译链接的过程【详见glsl】

## program objects

代表经过完全处理的可执行glsl代码(为多个shader stages编写的)。**不遵循标准的opengl对象模型**

### Creation

`GLuint glCreateProgram()`

创建之后就需要想起中填充可执行代码-通过编译链接shaders实现。

## shader objects

代表单个shader stage已编译的glsl代码。**不是opengl objects**

`GLuint glCreateShader(GLenum shadeType);`

shader object存储的信息非常有限。包括：

- shader source的字符串 `glGetShaderSource`
- 最近一次编译是否成功的信息 `glGetShader(GL_COMPILE_STATUS)`
- 编译失败的错误信息 `glGetShaderInfoLog`

**删除**：
1.显式调用删除

2.且此时没有被attach到任何program

> **orphaned:** 用户不再持有引用，但是仍然存活。

## program pipeline objects

包含可分离program objects的一种OpenGL object。当active的时候，在其中定义的shader stage code就会变成实际使用的。**遵循opengl对象规范**

决定每个shader stage要用哪个program的可执行体。不包含真正的代码，只”存储一个列表“.

**separable program**

`glProgramParameteri(prog, GL_PROGRAM_SEPARABLE, GL_TRUE);`需要将一个program设置为separable



`glBindProgramPipeline()` 绑定program pipeline

`glUseProgramStages()` 绑定某个program的某个stage



**关于uniform**

使用DSA的`glProgramUniform`

## program usage

`void glUseProgram(GLuint program);`

当program被绑定到上下文的时候，所有绘制命令都将使用链接到该程序的着色器以及相关状态进行渲染。

`glBindProgramPipeline(GLuint pipeline);` `glUseProgramStages()` 

用这个pipeline的shader以及状态。



**关于link**

1) 在使用monolithic program的时候。linker同时看到所有stage,分配uniform location、接口匹配等等。
2) 在使用program pipeline的时候。pipeline本身不link。pipeline组合的是已经link好的 separable program object。

```
glProgramParameteri(program, GL_PROGRAM_SEPARABLE, GL_TRUE);
glLinkProgram(program);
```

阶段间的匹配不是在link的时候发生，而是在validate的时候检查。

> `glProgramUniform` 设好的值不会因为进入 pipeline 而冲突，因为它们属于各自的 program；真正需要规划的是“全局绑定点资源”的编号与一致性（UBO/SSBO/image/texture unit）。

