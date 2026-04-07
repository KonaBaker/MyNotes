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

对于push_back和emplace_back的区别先介绍完美转发的概念。

### 完美转发

参考链接：

- https://zhuanlan.zhihu.com/p/369203981
- https://zhuanlan.zhihu.com/p/260508149

完美转发 = 引用折叠 + 万能引用(T &&) + std::forward。先介绍一些概念。

**引用折叠与右值引用参数**

```c++
template <typename T> void f(T&&);
```

对于这样的一个模板函数，如果有`int i;`那么我们可能会认为`f(i)`这样的调用是不合法的，因为右值引用不能接左值。但是c++规定了两个例外规则。

1) 影响右值引用参数的推断如何进行。当将一个左值传递给一个右值引用（T的）的函数参数，**且该右值引用是一个模板类型参数时**，编译器会推断模板类型参数为实参的左值引用类型。例如: `i`就推断为`int&`, 如果有一个`const int`类型的实参就推断为`const int&`.

2) 引用折叠。**只应用于间接创建引用的引用，如类型别名或者模板参数**。这里的折叠**不是**模板推导的T,**而是**T&&这个参数进行折叠。

   - `X& &` `X& &&` `X&& &` 都折叠为 `X&`
   - `X&& &&`折叠成 `x&&` 

   例如：`int& ci` `f(ci)`就会折叠为`int&`

上述两个规则组合在一起，就意味着我们可以在模板中对一个左值调用`f`。这也就意味这在模板成员函数中的参数`Args &&`是一个**万能引用**既可以接受左值，又可以接受右值。

**推断举例**

**1. `int i = 1; f(i);`**

`i` 是左值，T 推断为 `int&`。

引用折叠：`int& &&` → `int&`，所以参数类型为 `int&`。

**2. `int& refi = i; f(refi);`**

`refi` 也是左值（具名引用就是左值），T 推断为 `int&`。

参数类型同样折叠为 `int&`。

**3. `int&& rrefi = std::move(i); f(rrefi);`**

关键点：虽然 `rrefi` 的类型是 `int&&`，但 **`rrefi` 本身作为表达式是左值**（有名字的右值引用是左值）。

因此 T 推断为 `int&`，参数类型为 `int&`。

**4. `f(42);`**

`42` 是纯右值（prvalue），T 推断为 `int`（非引用类型）。

参数类型为 `int&&`。

**std::forward**

详见【C++11/move&forward】

**动机**：

此时对于某一种函数我们想实现一种功能即为，传入左值在函数内部就调用左值函数，传入右值在函数内部就调用右值函数。例如下面的`testForward`

```c++
template<typename T>
void print(T & t){
    std::cout << "Lvalue ref" << std::endl;
}

template<typename T>
void print(T && t){
    std::cout << "Rvalue ref" << std::endl;
}

template<typename T>
void testForward(T && v){
    print(v);
    print(std::forward<T>(v));
    print(std::move(v));

    std::cout << "======================" << std::endl;
}

int main(int argc, char * argv[])
{
    int x = 1;
    testForward(x);
    testForward(std::move(x));
}
```

```c++
Lvalue ref
Lvalue ref
Rvalue ref
======================
Lvalue ref
Rvalue ref
Rvalue ref
======================
```

对于传入的`v`这个表达式本身是个左值，所以使用其本身或者`std::move`并不能实现目的。

根据例外规则一，对于`testForward`的参数这样一个万能引用，在接收一个左值实参时，T类型都会推断为一个左值引用，接收一个右值实参的时候， `T`类型就是其本身类型。然后函数参数再根据例外规则二，进行引用折叠。这时`testForward`的实例化就完成了。

此时再将其传入`std::forward`，

```c++
// 左值调用下面这个函数，T的类型是param的左值引用，引用折叠完以后，返回的也是左值引用。相当于是对param做了一个强制转换成左值引用。
template <typename T>
constexpr T&& forward(typename std::remove_reference<T>::type& param)
{
    return static_cast<T&&>(param);
}

// 对于右值调用下面这个函数，T的类型就是param本身，相当于强制转换成右值引用。
template <typename T>
constexpr T&& forward(typename std::remove_reference<T>::type&& param)
{
    return static_cast<T&&>(param);
}
```

经过`forward`的转换过后，就可以完美匹配`print`的左值右值版本了。

整个这样一个流程就实现了**完美转发**。

**push_back与emplace_back**

回过头来再看push_back和emplace_back。

- `push_back`是有两个重载函数的：

  ```c++
  void push_back( const T& value );
  void push_back( T&& value );
  ```

  他是这样根据参数左右值不同来匹配不同函数。

- `emplace_back` 使用的是万能引用

  ```c++
  template< class... Args >
  reference emplace_back( Args&&... args );
  ```

因为emplace_back即可以接受左值，又可以接受右值，所以转调用其他函数(比如构造函数)时，要进行完美转发。

appends a new element to the end of the container.这个element是通过placement new/`std::allocator_traits::construct`的方式创建的。其中每个args都进行了完美转发`std::forward<Args>(args)`。这个construct在c++20以后不叫placement new了，最终调用

```c++
a.construct(p, std::forward<Args>(args)...)
```

p是指向为初始化storage的指针。

```c++
template <class T, class... Args>
constexpr T* construct_at(T* p, Args&&... args) {
    return ::new (voidify(p)) T(std::forward<Args>(args)...);
    //                          ^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //                          仍然是圆括号直接初始化
}
```

本质还是调用new。

在c++20以后引入了圆括号的聚合初始化，也就是说上述代码中的`T(std::forward<Args>(args)...);`可以不被当作构造函数，而是初始化。我们在c++20以后完全不用写复制或者移动构造函数。

---

**临时对象**

所以对于emplace_back和push_back的优势差别就在临时对象的appends。

```c++
// 写法 A: 产生临时对象 -> 移动构造到vector -> 析构临时对象
vec.push_back(BigData(1, 3.14));  //一次构造，一次移动构造

// 写法 B: 直接在vector内存里调用 BigData(1, 3.14),可以直接调用参数，而不是临时对象
vec.emplace_back(1, 3.14); // 0次移动，0次复制 ，只有一次构造
```

对于写法A: BigData(1, 3.14)为什么还会有临时对象产生，而没有copy elision? 其实是有的，它的实质化最后阶段就是参数接收的阶段`T&& value`，这个右值引用本身就是左值，有内存，有地址，这里就要实质化了。而copy elision的存在与否决定的是，先产生临时对象再传参（因为参数本身就是右值引用，所以没有开销），还是直接在参数处产生临时对象。

对于写法B: 这**不是**copy elision**,而是**完美转发+placement new/construct。只是emplace_back允许了一种新方式。他的传递过程都是args参数，没到最后时刻，都没有设计构造/新对象产生。

**左值**

```c++
T obj();
v.push_back(obj);
v.emplace_back(obj);
```

`push_back`会匹配`void push_back( const T& value );`并在内部调用拷贝构造函数，进行append。

`emplace_back`根据引用折叠以及完美转发规则，最后forward出来的是`T&`类型，同样调用拷贝构造函数，进行append。

所以二者没有区别。

**右值**

```c++
T obj();
v.push_back(std::move(obj));
v.emplace_back(std::move(obj));
```

`push_back`会匹配`void push_back( T&& value );`并在内部调用移动构造函数，进行append。

`emplace_back`根据之前讲的规则，最后forward出来的是`T&&`类型，同样调用移动构造函数，进行append。

所以二者没有区别。

**Notes**: 上述说的构造/移动 等等都是针对这个object整体，这个object本身，对于其内部成员是如何初始化的，要具体看成员表达式的值类型。例如：

```c++
struct Bigdata {
    int a;
    std::string b;
    std::vector<int> c;
};

v.emplace_back(1, std::string("..."), std::vector<int>{1,2,3});
```

0次移动，0次复制，直接在对应位置进行构造。

单就成员来看,`std::string`以及`std::vector`都被转发为右值引用类型，在聚合初始化的时候，会移动到对应成员。

```c++
std::string s = "...";
std::vector<int> vi = {1,2,3};
v.emplace_back(1, s, vi);   // s 和 vi 是左值
```

0次移动，0次复制，直接在对应位置进行构造。

单就成员来看，s,vi被转发为左值引用类型。这两个成员的初始化都变成了拷贝构造。

**emplace_back的零拷贝优势，完全依赖于实参是右值（临时对象以及其内部成员的临时性）**

