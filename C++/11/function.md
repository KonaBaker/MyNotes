**std::function**

存储、复制并调用任何callable对象。

- 普通函数、函数指针
- lambda表达式
- `std::bind`返回值
- 函数对象（重载了operator()的类）
- 成员函数指针、成员数据指针

**type erasure**不同类型的可调用对象，只要签名兼容，都可以装进统一个`std::function`

```c++
// 模板形式：std::function<返回类型(参数类型列表)>
std::function<int(int, int)> f;   // 接受两个 int 参数、返回 int 的可调用对象
std::function<void()>        g;   // 无参、无返回值
std::function<bool(const std::string&)> h;
```

1）普通函数/指针

```c++
int add(int a, int b) { return a + b; }

std::function<int(int, int)> f = add;    // ✅ 正确：隐式转换为函数指针
std::cout << f(3, 4);                    // 输出 7
```

2）lambda

```c++
std::function<int(int, int)> f = [](int a, int b) { return a - b; };
std::cout << f(10, 3);   // 输出 7

// 带捕获的 lambda 也可以（这是 std::function 相比函数指针的优势之一）
int base = 100;
std::function<int(int)> g = [base](int x) { return base + x; };
std::cout << g(5);       // 输出 105

// ---
int n = 1;
int (*fp)(int) = [n](int x) { return n + x; };   // ❌ 编译错误
std::function<int(int)> ok = [n](int x) { return n + x; };  // ✅
```

3）函数对象

```c++
struct Multiplier {
    int factor;
    int operator()(int x) const { return x * factor; }
};

std::function<int(int)> f = Multiplier{3};
std::cout << f(10);   // 输出 30
```

4）成员函数指针

成员函数隐含一个 `this` 参数，所以 `std::function` 的签名必须把它列出来，或者用 `std::bind` / lambda 把对象绑进去。

```c++
struct Foo {
    int value = 42;
    int add(int x) const { return value + x; }
};

// 方式 A：签名里显式带上对象参数
std::function<int(const Foo&, int)> f1 = &Foo::add;
Foo obj;
std::cout << f1(obj, 8);   // 输出 50

// 方式 B：用 std::bind 绑定 this
std::function<int(int)> f2 = std::bind(&Foo::add, &obj, std::placeholders::_1);
std::cout << f2(8);        // 输出 50

// 方式 C：用 lambda 捕获对象（推荐，最清晰）
std::function<int(int)> f3 = [&obj](int x) { return obj.add(x); };
std::cout << f3(8);        // 输出 50
```

5）成员数据指针

```c++
struct Point { int x, y; };

std::function<int(const Point&)> getX = &Point::x;
Point p{3, 4};
std::cout << getX(p);   // 输出 3
```

### common op

- bool 判断

```c++
if(f)
```

- 赋值/重置 `operator=`

```c++
std::function<int(int)> f = [](int x) { return x + 1; };
f = [](int x) { return x * 2; };   // ✅ 重新赋值
f = nullptr;                       // ✅ 清空，之后 f 为空
f = add_one_function;              // ✅ 换成普通函数（假设签名匹配）
```

### 内存

- std::function是值语义，是拥有callable的关系，但并不拥有引用捕获。可以使用std::move更高效的构造：但是前提要求callable也是可以move的。
- 存储的callable必须是可拷贝构造的（因为其本身是可拷贝的）

c++23引入`std::move_only_function`放弃了自身的可拷贝性

- 对于小对象有优化，放在内部缓冲区(自身对象的一部分，在栈上)里，超出大小限制的时候就会动态在堆中分配内存，比如捕获大数据的lambda

其本身是一个类 ，大致如下：MSVC这个buffer通常为64字节。

```c++
class function {
    // 一小块固定大小的原地存储空间
    alignas(...) unsigned char buffer[SBO_SIZE];
    // 一个函数指针表（或类似机制），知道怎么调用/拷贝/销毁里面的东西
    vtable* vptr;
};
```



```c++
std::array<int, 100> big{};
std::function<void()> f = [big]{ /* ... */ };
```

- 递归调用自己，lambda不能按值捕获，应该按引用捕获，因为初始化未完成。

```c++
// ❌ 错误：lambda 在初始化时 f 还未构造完，且按值捕获拿到的是空的副本
std::function<int(int)> f = [f](int n) {
    return n <= 1 ? 1 : n * f(n - 1);
};

// ✅ 正确：按引用捕获 f 本身
std::function<int(int)> fac = [&fac](int n) {
    return n <= 1 ? 1 : n * fac(n - 1);
};
std::cout << fac(5);   // 输出 120
```



