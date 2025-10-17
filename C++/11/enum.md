参考：https://zhuanlan.zhihu.com/p/1953830474251206879

## enum

- ```enum``` C++ 98
- ```enum class/struct``` C++ 11

默认的枚举值从0开始。

区别/优缺点：

- 全局作用域/class作用域

  ```c++
  // 对于enum,会有全局命名的污染。
  // 而对于enum class需要通过解析运算符进行访问。
  enum struct Color {Red};
  Color red = Color::Red;
  ```

- enum可隐式转换，enum class是类型安全的必须显式转换。

  ```c++
  int red = static_cast<int>(Color::Red);
  ```

- enum无法前置声明（除非制定底层类型），而enum class编译器可以预知大小。（先声明后定义）

  ```c++
  enum Color:int; // okay
  ```
