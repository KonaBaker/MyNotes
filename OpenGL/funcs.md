```glcreate*```

负责分配不同类型的opengl对象的名称，**注意是名称**类似于指针（但是不是指针），每一个名称代表一个初始化为默认状态的对象。立即分配存储空间。

允许直接修改对象状态，而不是先绑定，影响全局上下文。

> glgen*并不创建实际对象，只有在第一次bind的时候才会创建对象

```glbind*```

绑定一个对象到当前上下文对应的target

```gldelete*```

**总是断开binding** 若删除当前绑定的对象，将会执行```glbind*(0)```。对于未创建过的直接忽略掉。

**断开在上下文的attachment** 若该对象附加在一个容器对象上，只有绑定在当前上下文的容器对象上的被删除对象才会接触附加关系。

## Objects

常规对象：buffer, query, renderbuffer, sampler, texture

容器对象：framebuffer, program pipeline, transform feedback, vertex array

### Buffer

