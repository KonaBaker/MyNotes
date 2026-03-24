# Aggregate initialization

https://en.cppreference.com/w/cpp/language/aggregate_initialization.html

```c++
T object = { .des1 = arg1 , .des2 { arg2 } ... };
T object { .des1 = arg1 , .des2 { arg2 } ... };
```

这种方式只适用于聚合类型。

聚合类型包括：

- 数组
- class types同时满足
  - 没有用户自定义的构造函数（包括继承的）
  - 没有虚基类，如有继承必须是公有继承。
  - 所有成员必须是public
  - 没有虚成员函数

假设我们有如下的一个类

```cpp
struct base {
   int x;
};

struct derived{
   int    a;
   base    b;
   char   c = 'a';
   double d;
};
```

如下的实例化是合法的

```cpp
derived d1{};                         
 derived d2{ .a = 4 };                
 derived d3{ .a = 5, .c = 'b' };      
 derived d4{ .a = 4, .b = {.x = 5} }; 
 derived d5{ .a = 4, .b = {5} };
```

如下的实例化是不合法的

```cpp
derived d6{ .d = 1, .a = 42 };       
derived d7{ .a = 42, true, 'b', 1 }; 
derived d8{ .a = 42, .a = 0 };       
derived d9{ .b.x = 42 };            
int arr[5] = { [0] = 42 };
```

designated initializers需要遵循如下的规则

-  designated initializers 必须是按照成员的声明顺序进行初始化的
-  designated initializers 仅仅用于初始化直接非静态数据成员
-  designated initializers 只能用于 aggregate 初始化
-  并不需要所有的成员出现在initializer list中
-  不能在初始化表达式中同时使用designated initializers和non-designated initializers
-  成员的designated initializers必须在initializer list中出现一次 
-  designated initializers不能够嵌套