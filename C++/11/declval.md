## ODR

单一定义规则，每个实体在整个程序中只能有一个定义。

ODR-used

就是说你需要它真实存在于内存中，而不只是它的值。一旦某个实体被ODR-used，是常量折叠（编译期常量且只使用了值并没有使用地址）的补集

```cpp
// math_utils.h
struct MathUtils {
    static constexpr int kMax = 100;  // 类内声明
};
```

```cpp
// a.cpp
#include "math_utils.h"
void foo(const int& v) { ... }
foo(MathUtils::kMax);   // ODR-used！需要 kMax 有定义
```

```cpp
// b.cpp
#include "math_utils.h"
void bar(const int& v) { ... }
bar(MathUtils::kMax);   // ODR-used！也需要 kMax 有定义
```

链接时报错：

```
undefined reference to `MathUtils::kMax`
// 或者
multiple definition of `MathUtils::kMax`
```

类内的 `static constexpr` 在 C++17 前只是"声明"，不是"定义"。被 ODR-used 时，需要在某个 `.cpp` 里补一行：

```cpp
constexpr int MathUtils::kMax; 
```

C++17 之后规定：**类内 `static constexpr` 自动是 `inline` 的**，`inline` 变量允许在多个翻译单元中有定义，链接器会自动合并成一份。
