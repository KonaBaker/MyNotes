## invocation frequency

如果opengl检测到某个顶点着色器调用与之前的调用具有相同的输入，则可以重用之前的调用结果。

但是opengl实现通常不会通过实际比较输入值来进行优化，它只会在使用**索引渲染**的时候才会优化。

例如在**实例化**渲染中，多次指定某个相同的索引。



顶点着色器的调用次数是可能少于指定的顶点数量的。

### post transform cache

https://wikis.khronos.org/opengl/Post_Transform_Cache

是一个内存缓冲区，存储已通过顶点处理阶段但尚未转换为图元的顶点数据。

判断方法：若两个顶点的索引和实例计数相同gl_VertexID gl_InstanceID则被视为相等顶点。

