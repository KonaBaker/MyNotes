# Initialization



## Copy-initialization

从一个object初始化另一个object。

### explanation

以下情况会执行 复制初始化 ：

```c++
T object = other;
f(other);
return other;
throw / catch;
T array[N] = {};
```

- 非引用带名字的变量声明的时候使用 等号+initializer 初始化。
- 按值传参。
- 按值返回。
- 按值抛出或捕获异常。
- 作为aggregate initialization的一部分。

复制初始化的effect:

- 如果T是class type，且initializer是一个 prvalue 表达式（忽略cv类型相同），则不会产生临时对象。