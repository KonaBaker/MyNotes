参考：https://zhuanlan.zhihu.com/p/1953830474251206879

## enum

- ```enum``` C++ 98
- ```enum class/struct``` C++ 11

enum在C++中的本质是一个整型常量，编译器会把它直接替换成对应的字面量，不存在任何运行时的对象，不占用任何存储。例如：

```c++
enum Color { Red = 0, Green = 1, Blue = 2 };

Color c = Green;
// 编译后等价于int c = 1；
```

默认的枚举值从0开始。

enum class和enum一样，本身没有内存，是纯编译期的整型常量。

区别/优缺点：

- 全局作用域/class作用域

  ```c++
  // 传统 enum：枚举值泄漏到外层作用域
  enum Direction { Up, Down, Left, Right };
  int x = Up;       // 直接用，没问题（但也可能冲突）
  
  // enum class：枚举值被限定在枚举名内
  enum class Direction { Up, Down, Left, Right };
  int x = Up;                  // ❌ 编译错误
  int x = Direction::Up;       // ✅ 必须加限定
  ```

- enum可隐式转换，enum class是类型安全的必须显式转换。

  ```c++
  enum OldColor { Red, Green };
  int n = Red;        // ✅ 隐式转换为 int，传统 enum 允许
  
  enum class NewColor { Red, Green };
  int red = static_cast<int>(NewColor::Red); // 必须显式转换
  ```

- enum无法前置声明（除非制定底层类型），而enum class编译器可以预知大小。（先声明后定义）

  ```c++
  enum Color:int; // okay
  ```

- 底层类型。enum通常是int，由编译器决定但是不保证。enum class默认是int，但是可以显式指定

  ```c++
  enum class Flags : uint8_t { A, B, C };   // 明确指定为 uint8_t
  ```

  

