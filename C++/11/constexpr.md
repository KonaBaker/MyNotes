#### constexpr

常量表达式，可以作用在变量和函数上，一个 constexpr 变量是一个**编译时**完全确定的常数。一个 constexpr 函数至少对于某一组实参可以在编译期间产生一个**编译期**常数。**包含只读语义**

对于函数：在满足成为常量表达式的条件时可在编译期执行；否则在运行时执行。

函数体内只能包含编译时可执行的语句。**解释：c++20之后，函数体能包含更多语句（例如分支/循环等在更晚的标准中逐步放宽）**

**template的非类型模板参数**以及**数组大小值**都是需要常量表达式的地方

**指针**

constexpr只修饰对象本身。隐含const语义。

```constexpr int* p``` 修饰的是”指针p“这个对象。= ```int* const p```



#### consteval（C++20）

只能参与函数的声明。

使用`constexpr`声明的函数，其返回值可以被用于常量表达式中。但是，`constexpr`没有限定函数*只能*被用于常量表达式中。 `constexpr`函数仍然可以用于一般表达式中。

对于某些编译器（例如 clang 以及不带优化选项的 gcc），调用以`constexpr`声明的函数只有在常量表达式中才会被展开（其他情况仍然会在运行时调用）。例如：

```
constexpr int sqr(int x) {
  return x * x;
}

int foo() {
  int x = doSomething();
  return sqr(x);  // OK, sqr will be called during runtime
}

int foo() {
  return sqr(5);  // runtime
}
```

`consteval`则可以看作是**更加严格**的`constexpr`，它只能用于函数的声明。当某个函数使用`consteval`声明后，则所有**带有求值动作**调用这个函数的表达式必须为常量表达式(声明constexpr)。

**不带有求值动作**的调用`consteval`函数的表达式不需要为常量表达式

如：```decltype(sqr(y))```



#### const

关于const的报错是在编译期的。无运行时保证，但是可能受限与实现细节：

通过 `const_cast` 强行去掉 `const` 后修改 `const` 对象 **会导致未定义行为**（如果对象确实是以 `const` 声明的），在某些实现/平台上，因为把只读常量放在只读段，确实可能引起运行时崩溃。

> 默认修饰左边，如果左边什么都没有才修饰右边

```const A& a;```以及```A const& a```

两者等价，修饰的都是A。a 是一个reference to ```const A```，不能通过这个引用对a这个对象进行修改。

因为“引用本身”本来就不能修改，所以没有const修饰“引用本身”这一说法。例如：

```A& const a``` 

编译错误。

```const int*```和```int const*```

两者等价，const修饰int,表示一个pointer to ```const int```

```int* const```

“指针本身”不能修改



#### constinit (C++20)

强制变量必须在编译期完成初始化。**无只读语义**。

只能修饰静态存储期的变量（static,全局）

```c++
const char * g() { return "dynamic initialization"; }
constexpr const char * f(bool p) { return p ? "constant initializer" : g(); }
constinit const char * c = f(true);     // OK
constinit const char * d = f(false);    // ill-formed
```

调用g,g是不同函数，无法在编译期初始化。

























