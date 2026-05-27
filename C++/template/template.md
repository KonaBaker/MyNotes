template

我们提供足够的信息将蓝图转换为特定的类或者函数，这种转换发生在编译时。

# Define

## function template

`template <template args, ...>`  template后面跟一个模板参数列表。**模板参数列表不能为空**。

```
template<typename T>
T func(T a, T b) {}

int main()
{
	func<int>(a, b);
	func(a, b);
}
```

调用的时候，编译器通过函数实参来为我们推断模板实参，用它来为我们实例化一个特定版本的函数，在实例化的过程中它会用实际的实参来替代模板参数，创建出一个“新**实例**”。

### type parameters

模板类型参数前必须使用关键字class或typename（在模板参数列表中，这两周没有什么区别）

```c++
template<typename T, class U> T calc(const T&, const U&);
template<typename T, U> // x
```

### non-type parameters

模板中还可以定义nontype parameter表示一个值而非一个类型，通过一个特定类型名来指定。当一个模板实例化时，非类型参数被一个用户提供的或者编译器推断出的值所替代，这些值必须是constexpr。

- 编译器常量的整型

`int` `size_t` `bool` `enum`

```c++
// 用整型 N 描述一个编译期固定大小的数组
template <typename T, std::size_t N>
struct Array {
    T data[N];                 // N 在编译期已知，合法
    std::size_t size() const { return N; }
};

Array<int, 4> a;            // ✅ 字面量 4 是常量表达式
constexpr int N = 4;
Array<int, N> b;            // ✅ constexpr 变量也是常量表达式

int n = 4;
Array<int, n> c;            // ❌ 运行期变量，非常量表达式
```

- 指针（指向静态生存期的对象/函数）

```c++
// —— 指向全局对象的指针 ——
int global_val = 99;          // 全局变量，静态生存期

template <int* P>
struct Ref {
    int get() { return *P; }
};

Ref<&global_val> r;           // ✅ 全局变量地址，编译期已知

int local = 5;
Ref<&local> r2;              // ❌ 局部变量无静态生存期

// —— 指向函数的指针 ——
void greet() { /* ... */ }

template <void(*F)()>
struct Caller {
    void run() { F(); }       // 编译期绑定函数指针
};

Caller<greet> c;
c.run();                     // ✅ 调用 greet()
```

- 引用（指向静态生存期对象）

```c++
int global_x = 10;

template <int& R>
struct Modifier {
    void increment() { R++; }  // 直接操作引用对象
    int  value()     { return R; }
};

Modifier<global_x> m;
m.increment();               // ✅ global_x 变为 11

// 引用 vs 指针：语法更干净，无需解引用 *
// 但底层要求完全一样：对象必须有静态生存期

int local_y = 5;
Modifier<local_y> m2;        // ❌ 局部变量，生存期不够
```











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
