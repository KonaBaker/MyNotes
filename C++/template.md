```
template<typename T>
T func(T a, T b) {}

int main()
{
	func<int>(a, b);
	func(a, b);
}
```

支持显式调用和自动推导。例如stl库就是通过模板编程来实现的。

在编译过程中，模板函数会被实例化，根据调用类型生成对应的实体。

#### 两阶段编译检查

模板定义阶段 与模板参数类型无关。语法检查等

模板实例化阶段 与模板参数类型有关。

#### 类型自动推导

- 按引用传递：传递的时候不允许任何类型转换
- 按值传递：**decay**
  - const和volatile会被忽略
  - 引用退化
  - array和函数被转换成指针类型

错误案例：

```
max(4, 7.2); // ERROR: 不确定 T 该被推断为 int 还是 double
std::string s;
foo("hello", s); //ERROR: 不确定 T 该被推断为 const[6] 还是 std::string
```

如果想要避免上述情形：

- 可以对部分类型做强制转换
- 显式指出T类型
- 使用多个模板参数

对于默认参数调用，如果外面没有传入参数，需要声明默认参数。

```
template<typename T = std::string>
void f(T = "");
f(); // OK
```

#### 模板函数和普通函数优先级

如果普通函数完全符合调用或模板函数无法自动推导类型，则会调用普通函数。

如果实例化后模板函数更接近调用，则调用模板函数。



### C++20模板

#### 使用auto关键字

```
auto max(auto x, auto y)
{
    return (x < y) ? y : x;
}
```

用来代替

```
template <typename T, typename U>
auto max(T x, U y)
{
    return (x < y) ? y : x;
}
```

（不强制要求相同的情况下有效）
#### 类模板

**特例化**

```
template<typename T>
struct Stack{};

template<>
struct Stack<std::string> {};//特例化，指定T为std::string

// --------------------------

template<typename T1, typename T2>
struct Stack{};

template<typename T>
struct Stack<T, T>{};//特化为一个模板参数

template<typename T>
struct Stack<T, int>

template<typename T3, typename T4>
struct Stack<T3*, T4*> {};
```

特例化后的模板会被优先使用。

**类型别名**

```
using intStack = Stack <int>;
```

还可以使用别名模板

```
template<typename T>
using dequeStack = Stack<T, std::deque<T>>
dequeStack<int> obj; // ez
```

**类型推断指引**

C++17 引入了自动类型推断,编译器可以自动推断(不写尖括号），但是在一些复杂情况下可以使用推断指引

```
Stack(char const*) -> Stack<std::string>;
```

ps:对于char数组类型，会将其自动推断为char*

```
Stack stringStack = "bottom";
```

这种复制初始化是不可以的，需要等号右边生成一个临时的```Stack<std:string>```对象.在使用这种隐式的构造函数(转换构造函数)时不允许再发生参数类型的隐式转换

#### 非类型模板函数 

非类型模板参数只能是

- `整形常量`（包含枚举）
- 指向 objects/functions/members 的指针
- objects 或者 functions 的左值引用
- std::nullptr_t（类型是 nullptr）。
- auto

**注意**：**(编译时确定，常量表达式）**需要保证模板实参必须是第二阶段编译的时候可以访问到的，例如一些非类型模板参数传入的实参，不能写在main函数里，要定义在全局。

- ```template<decltype(auto) N>```

推导出包括引用在内的精确类型。

- ```template<auto N>```

自动推导类型，但不会保留引用的性质。

#### 变参模板

```
#include <iostream>
void print ()
{}
template<typename T, typename... Types>
void print (T firstArg, Types... args)
{
  std::cout << firstArg << '\n'; // print first argument
  print(args...); // call print() for remaining arguments
}
```



### 其他一些事项

#### typename

可以多用typename,可以用来表明一个标识符代表的是某种类型，而不是其它。**随时可用**

```
template<typename T>
class MyClass {
  public:
    // ...
    void foo() {
    typename T::SubType* ptr;
  }
};
```

上例中`typename T::SubType* ptr;` 中的 typename 用于澄清 SubType 是定义在 class T 内的一个**类型**(而不是成员)，且 ptr 是一个 SubType 类型指针。



### concept和requires子句

**concept**

在编译器检查模板实参是否满足指定的约束。

```
template<typename T>
concept require_name = requires {

};

template <require_name T>
//这里才写模板类或者函数，正常你要写的东西
```

另一种写法：
```
template<typename T> requires xxxxxx
//正常写
```







**requires**

`requires ( parameter-list(optional) ) { requirement-seq }`

**`requires`表达式的判定标准:对`requires`表达式进行模板实参的替换,如果替换之后出现无效类型,或者违反约束条件,则值为`false`,反之为`true`**

```
 template <class T>
 concept Check = requires {
     T().clear();
 };
 
 template <Check T>
 struct G {};
 
 G<std::vector<char>> x;      // 成功
 G<std::string> y;            // 成功
 G<std::array<char, 10>> z;   // 失败
```

要求序列以分号分隔可以有多个
