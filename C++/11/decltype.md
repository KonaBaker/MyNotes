**decltype**

编译时类型推导关键字。返回的是类型本身。可以用于声明。

而typeid正好与上述相反。

在声明**难以或无法使用标准符号声明**的类型时非常有用

```c++
auto f = [i](int av, int bv) -> int { return av * bv + i; };
auto h = [i](int av, int bv) -> int { return av * bv + i; };
static_assert(!std::is_same_v<decltype(f), decltype(h)>,
    "The type of a lambda function is unique and unnamed");

decltype(f) g = f;
```

常用于模板编程，类型推导，声明等

1) 如果参数是一个**未加括号**的 id 表达式或**未加括号**的类成员访问表达式，那么 decltype 产生由**该表达式命名的实体**的类型。

```c++
int i = 4;
decltype(i) a; // 推导结果为int

struct A { double x; };
const A* a;
decltype(a->x) y;       // double
decltype((a->x)) z = y; // const double&
```

2)如果参数是其他类型的表达式T

- 如果是一个将亡值（xvalue)或右值引用。推导为右值引用`T&&`
- 如果是一个左值，推导为左值引用 `T&`
- 如果是一个纯右值，推导为 `T`

**notes**:

如果对象的名称被括号括起来，则被视为普通左值表达式。推导的是**表达式类型** **值类别（左右值）**（值类型其实是描述表达式的术语，而不是值的术语）

对于不加括号来说，编译器会只看这个变量最初是如何定义的。会忽略掉当前的上下文。推导的是**声明类型**