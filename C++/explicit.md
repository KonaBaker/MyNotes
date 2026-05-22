## explicit

### usage

- **禁止隐式单参数构造转换**

```
class MyStr {
public:
    explicit MyStr(int size);  // ← 必须显式构造
};

void print(MyStr s) {}

print(42);          // ❌ 编译错误（没有 explicit 则隐式转换成功）
MyStr s = 42;       // ❌ 拷贝初始化也会失败
print(MyStr(42));   // ✅ 显式构造，OK
```

关于初始化：

```c++
struct A { explicit A(int); };

A a1(1);    // ✅ 直接初始化，OK
A a2{1};    // ✅ 直接列表初始化，OK
A a3 = 1;  // ❌ 拷贝初始化，被 explicit 阻断
A a4 = {1}; // ❌ 拷贝列表初始化，同样被阻断
A a5 = A(1); // ✅ 显式构造后拷贝（通常被优化消除），OK
```

对于聚合初始化，其可以绕过构造函数，聚合类（无用户自定义构造函数，没有private\protected成员）不受explicit影响。

```c++
struct C {
    explicit C(int x, int y = 0);  // 用户构造 → 非聚合
};

C c1 = {1, 2};  // ❌ 非聚合 + explicit，拷贝列表初始化失败
C c2{1, 2};     // ✅ 直接列表初始化，OK
```

对于函数返回值同理：

```c++
struct B { explicit B(int); };

B foo() {
    return 42;     // ❌ 等价于 B b = 42，被 explicit 阻断
    return B(42);  // ✅ 显式构造，OK
    return B{42};  // ✅ 同上
}
```

- **禁止多参数构造的列表初始化转换**

```
class Vec2 {
public:
    explicit Vec2(double x, double y);
};

void draw(Vec2 v) {}

draw({1.0, 2.0});   // ❌ 编译错误，explicit 阻断列表初始化隐式转换
draw(Vec2{1.0, 2.0}); // ✅ 显式构造
```

- **控制operator T()的隐式调用**

```c++
class SafeBool {
    bool val;
public:
    explicit operator bool() const { return val; }
};

SafeBool sb{true};

if (sb) {}          // ✅ 上下文转换（contextual conversion），允许
bool b = sb;        // ❌ 隐式转换，编译错误
bool b2 = (bool)sb; // ✅ 显式 cast，OK
int n = sb;         // ❌ 更不行，double-implicit
```

**上下文特例**：if while ! && || ？等场景会自动除法explicit bool的转换

- **条件控制（C++20以后）**

```c++
template <typename T>
class Wrapper {
public:
    // 只有当 T 不可隐式从 int 构造时，才加 explicit
    explicit(!std::is_convertible_v<int, T>)
    Wrapper(T val);
};

Wrapper<double> a = 3;   // ✅ double 可从 int 隐式转换，explicit(false)
Wrapper<MyType> b = 3;   // ❌ MyType 不能隐式从 int 转换，explicit(true)
```

### Notes about initalizer

```c++
Foo foo = Foo(1);
Foo foo = 1;
```

这两者的开销是一样，无论显式还是隐式都会产生prvalue，那么C++17之后延迟临时量实质化，就会在foo上直接构造