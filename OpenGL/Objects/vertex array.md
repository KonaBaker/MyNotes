### vertex array

``` glenablevertexarrayattrib(gluint vao, gluint index)```

使用dsa直接启用属性数组。

``` glvertexarrayvertexbuffer```

将一个vao的索引点和对应的vbo联系起来 

``` glvertexarrayattribformat```

规定顶点数组的组织方式.最后一个参数relativeoffset，表示从绑定的顶点缓冲区的起始位置到需要的第一个元素的距离（也就是数据偏移）

``` glvertexarrayattribbinding```

associate a vertex attribute and a vertex buffer binding

``` glvertexarrayelemnetbuffer(vao, ebo)```

绑定索引缓冲区到vao。



可以分别的索引点联系不同的vbo

也可以只将0和一个大的vbo联系起来，通过format规定偏移和组织方式。

dsa只是让数据设置的时候无需再进行绑定，当进行渲染的时候，还是要调用``` glbindvertexarray``` 进行绑定后再调drawcall.



**注意**

attribute location（attribindex) != binding point(binding index)

attribute location是顶点属性的索引，对应layout(location = )

binding point 对应vao中的缓冲区绑定点

在``` glvertexarrayvertexbuffer```中绑定的“索引”（此索引非彼索引）是binding point 一般一个buffer对应一个，这里是缓冲区绑定点，或者叫缓冲区索引。

在``` glvertexarrayattribformat```中指定组织方式中，这里的索引是attribute point和着色器中的location对应。

在``` glvertexarrayattribbinding```将一个attribute location和一个binding point 联系起来。

总结来说，在glvavb中是将一系列buffer绑定到vao上，这时，每个buffer都有一个绑定点。

format是用来划分数据组织方式，并将其和着色器中location对应。

binding是指定哪个location从哪个buffer中读数据。
