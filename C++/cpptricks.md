## 匿名名字空间

在匿名命名空间中声明的名称也将被编译器转换，与编译器为这个匿名命名空间生成的唯一内部名称(即这里的*_UNIQUE_NAME*)绑定在一起。还有一点很重要，就是这些名称具有internal链接属性，这和声明为static的全局名称的链接属性是相同的，即名称的作用域被限制在当前文件中，无法通过在另外的文件中使用extern声明来进行链接。如果不提倡使用全局static声明一个名称拥有internal链接属性，则匿名命名空间可以作为一种更好的达到相同效果的方法。

注意:命名空间都是具有external 连接属性的,只是匿名的命名空间产生的**UNIQUE_NAME**在别的文件中无法得到,这个唯一的名字是不可见的.

C++ 新的标准中提倡使用匿名命名空间，而不推荐使用static，因为static用在不同的地方，涵义不同容易造成混淆。比如：带static的类成员为类共享，而变量前的static又表示内部链接、存储范围。

另外，static不能修饰class定义，那样就可以将类定义放在匿名命名空间中达到同样的效果。\

```
// 文件路径：project-root/ext-foo-bar/source/ext-foo-bar/foo-bar.cpp
#include "foo-bar.hpp"
#include <nonstd/unique_ptr>

namespace ss::ext_foo_bar
{
    namespace
    {
        nonstd::unique_ptr<Foo_Bar> global_foo_bar{};
        // 如果是线程全局，则需要在类型前添加 `thread_local` 关键字
    }

    auto foo_bar() -> Foo_Bar&
    {
        if (!global_foo_bar) {
            global_foo_bar = nonstd::make_unique<Foo_Bar>{"name", 2333};
        }

        return *global_foo_bar;
    }

    auto try_foo_bar() -> Foo_Bar* { return global_foo_bar.get(); }
}
```



### static

- 对全局变量加static 将external变为internal

- 对局部变量加static 作用域不变，但是存储位置和生存周期发生变化

- 对函数加static 只能在本文件使用
- 静态数据成员，一份拷贝/不能在类中定义和初始化，只能在类中声明，在类外定义和初始化
- 静态成员函数，只能访问静态数据成员和静态成员函数。类外定义无需再加static

## constexpr

const表示在编译期已经确定无法通过语法进行修改

加在变量或者函数上被常量表达式初始化，在编译期把能算的算好。

```
constexpr int calc(int n)
{
  if (n % 2 == 0) { // C++11 compile error
    return n * n;
  }
  int a = 10; // C++11编译错误
  return n * n + a; // C++11编译错误
}
int main()
{
  constexpr int N = 123；
  constexpr int N_SQ = sq(N)；
  constexpr int N_CALC = calc(N)；
  printf("%d %d %d\n", N, N_SQ, N_CALC); // 123 15129 15139
  printf("%d\n", sq(4)); // 編譯期不會計算 sq(4)
}
```

##  emplace_back

push_back会先调用对象本身的构造函数然后在调用移动构造函数或拷贝构造函数，而emplace_back只会调用一次构造函数。在没有移动构造函数的情况下会调用拷贝构造函数  

move是一个强制类型转换，是将左值转换为右值引用。

## final

- 禁止继承类
- 禁止重载函数，例如虚函数



## 智能指针

https://www.cnblogs.com/DswCnblog/p/5628195.html

## abs

std是c++的标准库

std::abs是有float的重载的，而只使用abs会调用c的函数只能是整数类型，会默认做转换，可能导致错误。

## pimpl

全名: pointer to implementation　指向实现的指针。它通过将类的私有成员封装到一个实现类中，然后在接口类中只声明一个指向实现类的指针，从而实现“信息隐藏”。

引擎中在hpp中只声明

```
struct Impl;
```

在cpp中所有实现都在
```
struct Ocean_Pass::Impl: core::Pinned中
```

一些想在头文件中暴露的接口函数如：

```
auto update() -> void;
auto render() -> void;
```

需要调用

```
auto Ocean_Pass::update() -> void
{
    impl->update(*this);
}

auto Ocean_Pass::render() -> void
{
    impl->render(*this);
}
```

### 优点

1. **隐藏实现细节**：头文件不暴露私有成员。
2. **降低耦合**：头文件改动减少，避免连带其他类重新编译。
3. **提高 ABI 稳定性**：适合做动态链接库，接口改动较少时 ABI 不会变化。
4. **减少头文件依赖**：类成员使用前向声明即可，不需要完整包含。

## 宏

