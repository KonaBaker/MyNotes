## chapter 4 设计与声明

### 18 interface

好的接口应该很容易被正确使用，不容易被误用。

- 首先考虑客户可能会犯什么样的错误

例如一个date的设计：
```c++
class Date {
public:
	Date(int month, int day, int year);
}
```

可以新增Day Month Year的新类型。

比如月份只有十二个月，可以通过enum class表现月份，限制输入。

比如对某些成员函数加上const。

- 让types的行为和内置types一致
- 提供行为一致的接口，比如STL中的容器，大多数都有size()函数
- 不要让客户必须记得做某些事情：比如释放资源。可以接口返回的时候使用智能指针，或者设计RAII类。

### 19 设计class = 设计type

- 如何被创建和销毁？如何写构造、析构，operator new/[] ,operator delete/[]内存分配。

- 初始化和赋值应该有什么样的差别？

- 值传递。拷贝构造函数定义了一个type的pass-by-value如何实现

- 合法值。需要维护约束条件，限定构造函数、赋值操作符和可能的setter函数必须进行一些错误检查工作。

- 考虑继承。

- 需要什么样的转换。需要和哪些types之间有转换行为？需要写转换函数.get()显式或者operator T()隐式。

  补充：转换函数operator T()没有返回类型，没有参数，函数名就是目标类型。
  
- 哪些函数应该被声明为private？

- 什么operator以及函数对此新type是合理的？见条款23.24.46

- 未声明接口。条款29

- 你的新type有多么一般化。可能需要定义一整个types家族，一个新的class template

### 20 以pass-by-reference-to-const替换pass-by-value

值传递会调用拷贝构造函数。建议使用const&的方式传递参数。const能保证不会对传入的参数进行改变。

**object slicing**:对基类和派生类。如果以值传递的方式，将一个派生类传递给一个基类参数，那么那么参数会被构造成基类对象，派生的特化信息都会被切除。在这种情况下调用构造对象的虚函数，不会再有多态性质。如果使用const&,引用的是整个对象，这时候特化信息还没有被切除。

对于内置类型、STL的迭代器(**迭代器本身而不是容器**，容器千万不要值传递）、函数对象，大部分时候值传递是更好的选择，因为它们本身就被设计为pass-by-value。这正是条款1“规则的改变取决于你使用哪一部分C++”。

### 21 必须返回对象的时候，不要返回reference

reference是某个既有对象的另一个名称。如果“期望本来存在某一个对象”不合理，那么就要返回值而不是reference。

```c++
Rational a(1, 2);
Rational b(3, 5);
Rational c = a * b; // 对于c来说本来就应该是一个新对象，而不是某个别的对象的引用。
// 那么对于重载运算符的返回值就应该是一个值
const Rational operator* (const Rational& lhs, const Rational& rhs); // const避免返回值被无意义的当作一个左值，见条款3
```

除此之外，还有函数内部的在栈上的局部变量，如果返回引用，会导致引用悬垂。

如果在heap上构造一个对象并返回reference指向它，但是无法找到这个区域的指针，无法delete，会导致资源泄露

### 22 将成员变量声明为private

利用封装性，尽可能的隐藏泪中的成员变量，通过getter/setter函数来时先对成员变量的访问

### 23 以non-member\non-friend替换member函数

假设有这样一个类：

```cpp
class WebBrowser {
public:e
    ...
    void ClearCache();
    void ClearHistory();
    void RemoveCookies();
    ...
};
```

如果想要一次性调用这三个函数，那么需要额外提供一个新的函数：

```cpp
void ClearEverything(WebBrowser& wb) {
    wb.ClearCache();
    wb.ClearHistory();
    wb.RemoveCookies();
}
```

注意，虽然成员函数和非成员函数都可以完成我们的目标，但此处更建议使用非成员函数，这是为了遵守一个原则：**越少的代码可以访问数据，数据的封装性就越强**。此处的`ClearEverything`函数仅仅是调用了`WebBrowser`的三个public成员函数，而并没有使用到`WebBrowser`内部的private成员，因此没有必要让其也拥有访问类中private成员的能力。

这个原则对于友元函数也是相同的，因为友元函数和成员函数拥有相同的权力，所以在能使用非成员函数完成任务的情况下，就不要使用友元函数和成员函数。

如果你觉得一个全局函数并不自然，也可以考虑将`ClearEverything`函数放在工具类中充当静态成员函数，或与`WebBrowser`放在同一个命名空间中：

```cpp
namespace WebBrowserStuff {
    class WebBrowser { ... };
    void ClearEverything(WebBrowser& wb) { ... }
}
```

### 24 如果所有参数都需要类型转换，要采用non-member函数

```c++
class Rational {
public:
	const Rational operator* (const Rational& rhs) const;   
}
```

此时如果尝试混合式算数(和int相乘)
```c++
result = rational * 2;   // v = rational.operator*(2); 允许从int构造(non-explicit)
result = 2 * rational;  // x = 2.operator*(rational);
```

2没有operator*的成员函数，编译器会寻找non-member的`operator*(2, rational)`。

此时就需要声明一个non-member函数

```c++
const Rational operator*(const Rational& lhs, const Rational& rhs);
```

### 25 不抛异常的swap

已被`std::move`替代

>C++ 名称查找法则：编译器会从使用名字的地方开始向上查找，由内向外查找各级作用域（命名空间）直到全局作用域（命名空间），找到同名的声明即停止，若最终没找到则报错。 函数匹配优先级：普通函数 > 特化函数 > 模板函数

















