**零抽象成本 zero-cost-abstraction**

高级语言特性 如：类、模板、反射在运行时不会引入额外的开销。

> 这意味着开发者可以编写高可读性、高维护性的代码，同时享受与手写底层代码相同的性能

**一些例子**：

- 函数inline直接嵌入调用处，减少运行时调用开销
- 模板实例化在编译器完成，无运行时开销。
- RAII资源获取即初始化：构造时分配内存，析构时自动释放内存，没有垃圾回收机制
- move
- 静态多态

# 反射

反射机制允许程序在运行时借助reflection api取得任何类的内部信息，并能直接操作对象的内部属性。

- C++不支持反射

- rpc、webmvc、对象序列化

对类对象、类成员数据、类成员函数进行反射。

通过全局定义宏，使其在类初始化前进行展开注册。 

## 类对象反射

程序运行的时候读进来一个字符串，然后创建出对应的类对象。

- 通过条件判断类名字（过于丑陋）
- 通过map存储字符串和函数指针的映射

通过一个辅助类来进行注册（加入到map中），这里面要写一个宏（里面有函数和注册），到时候类里面写这个直接宏展开。

更规范，还需要设置一个反射基类，让所有需要反射类继承自他。

## 类成员反射

**涉及一个关键问题**：内存布局

```
// 获取成员变量偏移量
#define OFFSET_OF(class_name, member) \
    ((size_t)&((class_name*)0)->member)
```

编译时计算偏移。

在C++11以后可以使用cstddef中的offsetof(class, member),返回sizet类型



获得想要成员的偏移，通过偏移获得相应的指针，并且解引用，得到想要的成员。

和对象反射一样，需要使用一个map维护类名称和他成员的vector信息数组。

成员信息包括，所在类名、成员名、偏移等。

这里同样也需要辅助类。

**辅助类**主要是通过构造函数去调用其他函数（相当于一个入口接口）。然后再通过宏定义展开。

#### 对于成员函数使用std::function进行封装。

对于std::function包装成员函数有两种办法：

- 使用std::bind```std::function<int(int, int)> func1 = std::bind(&Calculator::add, &calc, std::placeholders::_1, std::placeholders::_2);```

这里的placeholders是一个参数占位，表示是将会传给func1的参数的第n个参数（_n)

- 使用lambda再包装一层```std::function<int(int, int)> func2 = [&calc](int a, int b) {        return calc.multiply(a, b);    };```
- 直接存储成员函数指针需要对象指针作为第一个参数```std::function<int(Calculator*, int, int)> func3 = &Calculator::add;```

**std::bind**

**接受一个可调用对象，生成一个新的可调用对象来适应原对象的参数列表**。

```
auto newCallable = bind(callable, arg_list);
```

当调用`newCallable`时，会调用`callable`，并传给它`arg_list`中的参数。

callable是函数类型，会隐式转换为函数指针，一般情况下f和&f是等价的。

**uintptr_t**

存储指针的数值表示

```
uintptr_t addr = reinterpret_cast<uintptr_t>(&f);
```

&f是函数指针类型。

---



