## struct & class

### C++ 中 `struct` 与 `class` 的区别

在目前现代C++中，只有两处语法差异，其余能力完全等价。

**区别一：成员的默认访问权限**

在 class/struct 的成员声明中，访问说明符决定了后续成员的可访问性。 [Cppreference](https://en.cppreference.com/w/cpp/language/access.html)

- `struct` 中，未显式指定访问说明符的成员默认为 **`public`**
- `class` 中，未显式指定访问说明符的成员默认为 **`private`**

cpp

```cpp
struct S {
    int x; // public（默认）
};

class C {
    int x; // private（默认）
};
```

**区别二：继承时的默认访问说明符**

如果继承时省略了访问说明符，对于用 `struct` 关键字声明的派生类，默认为 `public` 继承；对于用 `class` 关键字声明的派生类，默认为 `private` 继承。

```cpp
struct Base { int a; };

struct D1 : Base {};   // 等价于 public Base
class  D2 : Base {};   // 等价于 private Base
```

**区别三：关键字方面，模板类型参数只能使用class和typename声明，不能使用struct**

```c++
template<class T>    // ✅ 合法
template<typename T> // ✅ 合法
template<struct T>   // ❌ 非法
```

### 使用惯例

虽然语言层面两者几乎等价，但业界有约定俗成的用法：

- **用 `struct`**：表示纯数据聚合（POD-like），没有不变量（invariant）需要维护，成员均为 public。
- **用 `class`**：表示有封装、有行为、有不变量需要维护的抽象类型，通常含有 private 成员。



struct和class都不会默认生成operator == 等类似函数，需要手动写。

c++20之后可以手写 = default

```c++
struct Point {
    int x, y;
    auto operator<=>(const Point&) const = default; // 默认三路比较
    // 同时自动生成 operator== 和全套 < > <= >= 
};

// 或者只需要相等比较：
struct Point {
    int x, y;
    bool operator==(const Point&) const = default; // 仅生成 ==（和 !=）
};
```

