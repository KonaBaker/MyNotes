## chapter 5 implementations

26 尽可能延后变量定义式出现的时间

当程序运行到定义式的时候，就会承担一个构造成本，当其离开作用域的时候，就会承担析构成本。即使这个变量最终并未被使用。

例如程序中间可能会抛出异常，或者由于分支选择等原因导致某个定义的变量没被完全使用。

同时在定义的时候最好使用直接初始化。先默认初始化后赋值的效率较低。

“尽可能延后”：不只延后变量的定义，甚至延后定义直到能够给他初值实参。 C++17中延迟实质化也是这一种思想的体现，直到最后一刻才进行构造。

**对于循环**

还是在体外，赋值成本小于构造。

27 尽量少做cast

cast在某种程度上破坏了C++ 的type system。

**c-style**

```c++
(T)expression
T(expression)
```

避免假设“对象在C++中如何布局”，随着编译器实现他们的布局也会改变，基于此的一些行为会导致ub。

```cpp
class Window {
public:
    virtual void OnResize() { ... }
    ...
};

class SpecialWindow : public Window {
public:
    virtual void OnResize() {
        static_cast<Window>(*this).OnResize();
        ...
    }
    ...
};
```

这段代码试图通过转型`*this`来调用基类的虚函数，然而这是严重错误的，这样做会得到一个新的`Window`副本并在该副本上调用函数，而非在原本的对象上调用函数。应该如下使用：

```c++
class SpecialWindow : public Window {
public:
    virtual void OnResize() {
        Window::OnResize();
        ...
    }
    ...
};
```

