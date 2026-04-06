# Copy Elision复制消除/RVO(Return Value Optimization)/NRVO

## Copy Elision

当满足特定条件的时候，从一个同类型的(忽略cv)的source object构建target object的时候，其中的构建/copy可以省略。这就是**copy elision**。

### explaination

如下情况会进行copy elision(同时可以结合使用消除多次copy)

- 一个函数如果返回的是一个class type，且这个operand是一个non-volatile & automatic storage duration的object的名字`obj`(不能是函数参数或者其他handler参数)，此时可以直接将obj构造到函数调用的那个对象中，来省略调用对象**copy-initialized**的copy。这就是**NRVO**。

  ```c++
  auto get_draw_command(Cube_Sphere const& io) -> Draw_Command
  {
      Draw_Command cmd; // 1. 局部变量创建
      // ... 对 cmd 进行操作 ...
      return cmd;       // 2. 返回
  }
  ```

  这样也不会有临时对象产生，编译器会进行优化，直接在栈上分配内存，将内存地址作为隐式参数传入，并在返回时直接在地址进行构造，cmd的变量地址会直接映射到函数外部接收返回值的地址。

- 当一个class type被一个prvalue **copy-initialized**，这时也会直接构造，而不产生临时对象，这就是**URVO**.

  ```c++
  std::string result = std::string("hello"); 
  std::string result = getValue();
  f(Foo(42)); // 避免参数本身的临时构造，而是直接在函数参数栈上分配空间，直接在参数栈上“接收数据”。
  ```

  **Notes**: **URVO**自c++17之后是强制的，不视为copy elision的一种。

- throw
- handler
- coroutines

当发生copy elision的时候，编译器会把source(初始化)和target(被初始化)两个object视为对某一个相同object的不同引用方式。也就是说Copy elision 的**本质**是把「源对象」和「目标对象」合并为同一个对象。

那么这时就需要规定这个对象的**销毁时刻**：（目的是为了符合move或者copy的语义）

- **规则一**：如果被选中的构造函数的第一个参数是**右值引用**（即选中了移动构造函数），销毁时刻 = **目标对象**原本应被销毁的时刻。

- **规则二**：否则（即选中了拷贝构造函数，参数是 `const T&`），销毁时刻 = 源和目标两者中**较晚**的那个销毁时刻。

```c++
struct CopyOnly {
    CopyOnly() {}
    CopyOnly(const CopyOnly&) {}  // 只有拷贝构造
};

struct Movable {
    Movable() {}
    Movable(Movable&&) {}         // 有移动构造
};

CopyOnly f1() {
    CopyOnly obj;
    return obj;  // selected constructor: CopyOnly(const CopyOnly&) → 规则二
}

Movable f2() {
    Movable obj;
    return obj;  // selected constructor: Movable(Movable&&) → 规则一
}
```

只不过在这个例子中 **目标对象**原本应被销毁的时刻 = 源和目标两者中**较晚**的那个销毁时刻。规则一和规则二的作用结果是相同的。这个规则主要体现在throw和catch的copy elision中



### prvaule semantics("guaranteed copy elision")

自c++17起，prvalue只有在需要的时候才会实质化，并且直接构造到其最终目标的存储空间中。这意味着即使语法上暗示了使用copy或者move操作（e.g. copy-initialization)，实际上也可能不会使用。同时也意味着，一个type不需要具有可以访问的复制/移动构造函数。

```c++
struct Immovable {
    Immovable() = default;
    
    // 删除了拷贝构造和移动构造
    Immovable(const Immovable&) = delete;
    Immovable(Immovable&&) = delete; 
};

// 函数返回一个 prvalue
Immovable make_it() {
    return Immovable(); // C++14: 错误！需要移动构造函数来从函数移出
                        // C++17: 合法！
}

int main() {
    // C++14: 错误！需要移动构造函数来初始化 x
    // C++17: 合法！
    Immovable x = make_it(); 
}
```

- 通过返回语句初始化返回对象的时候，如果operand是一个prvalue(忽略cv相同)

  ```c++
  T f()
  {
      return U(); // constructs a temporary of type U,
                  // then initializes the returned T from the temporary
  }
  T g()
  {
      return T(); // constructs the returned T directly; no move
  }
  ```

- 当初始化一个对象的时候，如果initializer是一个prvalue expression(忽略cv相同) （上面介绍的URVO就变成了这种）

  ```c++
  T x = T(T(f())); // x is initialized by the result of f() directly; no move
  f(Foo(42)); // 初始化函数参数的是Foo(42)这个prvalue expression，所以直接在参数位置上完成了构造。
  ```

这个规则不适用于可能包含subobject的情况：

1) 基类子对象：派生类中包含的基类部分
1) 用[[no_unique_address]]声明的非静态数据成员。

因为编译器可能会让它们共享内存空间，这样就无法保证能把prvalue直接安全的构造进去，例如：

```c++
struct C { /* ... */ };
C f();
 
struct D;
D g();
 
struct D : C
{
    D() : C(f()) {}    // no elision when initializing a base class subobject
    D(int) : D(g()) {} // no elision because the D object being initialized might
                       // be a base-class subobject of some other class
};

// maybe
// struct E : D {
//     E() : D(42) {}  // 这里 D 就是 E 的基类子对象
// };

D d = g(); // okay
```

**Notes**: 这种prvalue的机制并未正式描述为“copy elision"(上面所讲的针对函数返回值的copy elision可以看到是有限定条件的左值)，在c++ 17 以后纯右值的定义和临时对象的处理和之前有所不同，**不再存在需要move/copy的临时对象**。更贴切的可以将这种机制称之为**”延迟临时对象实质化“**



### example

```c++
#include <iostream>
 
struct Noisy
{
    Noisy() { std::cout << "constructed at " << this << '\n'; }
    Noisy(const Noisy&) { std::cout << "copy-constructed\n"; }
    Noisy(Noisy&&) { std::cout << "move-constructed\n"; }
    ~Noisy() { std::cout << "destructed at " << this << '\n'; }
};
 
Noisy f()
{
    Noisy v = Noisy(); // (until C++17) copy elision initializing v from a temporary;
                       //               the move constructor may be called
                       // (since C++17) "guaranteed copy elision"
    return v; // copy elision ("NRVO") from v to the result object;
              // the move constructor may be called
}
 
void g(Noisy arg)
{
    std::cout << "&arg = " << &arg << '\n';
}
 
int main()
{
    Noisy v = f(); // (until C++17) copy elision initializing v from the result of f()
                   // (since C++17) "guaranteed copy elision"
 
    std::cout << "&v = " << &v << '\n';
 
    g(f()); // (until C++17) copy elision initializing arg from the result of f()
            // (since C++17) "guaranteed copy elision"
}
```

```c++
constructed at 0x7fffd635fd4e
&v = 0x7fffd635fd4e
constructed at 0x7fffd635fd4f
&arg = 0x7fffd635fd4f
destructed at 0x7fffd635fd4f
destructed at 0x7fffd635fd4e
```

**Notes:**

- constexpr和const initialization永远不会执行copy elision

- 赋值不等于初始化，上述所说的copy elision的完美情况都是**限定了初始化**。但是无论是赋值还是初始化，都会避免从局部变量到result object的那一次copy/move 构造。但是赋值的时候，“调用方的内存地址”是临时开辟的，后续需要经过一次move赋值。但是这已经不是copy elision的范畴了。例如：

  ```C++
  #include<iostream>
  struct Foo {
      Foo() { std::cout << "default ctor\n"; }
      Foo(const Foo&) { std::cout << "copy ctor\n"; }
      Foo(Foo&&) { std::cout << "move ctor\n"; }
      Foo& operator=(Foo&&) { std::cout << "move assign\n"; return *this; }
      ~Foo() { std::cout << "dtor\n"; }
  };
  
  Foo f() {
      Foo local;
      return local;  // NRVO 候选
  }
  
  int main()
  {
      Foo x = f();
      std::cout << "=" << std::endl;
      Foo y;
      y = f(); // 这个f()的result object是临时对象，临时开辟的内存
  }
  
  // 输出：
  default ctor
  =
  default ctor // Foo y;
  default ctor // 在临时result object上构造;
  move assign  // 从临时result object移动到y;
  dtor
  dtor
  dtor

## push_back&emplace_back

对于push_back和emplace_back

```emplace_back(move(x))```和```push_back(move(x))```没有区别，都会调用移动构造函数。

真正区别如下：

```c++
// 写法 A: 产生临时对象 -> 移动构造到vector -> 析构临时对象
vec.push_back(BigData(1, 3.14));  //一次构造，一次移动构造

// 写法 B: 直接在vector内存里调用 BigData(1, 3.14),可以直接调用参数，而不是临时对象
vec.emplace_back(1, 3.14); // 0次移动，0次复制 ，只有一次构造
```





