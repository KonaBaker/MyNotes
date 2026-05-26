## chapter 5 implementations

### 26 尽可能延后变量定义式出现的时间

当程序运行到定义式的时候，就会承担一个构造成本，当其离开作用域的时候，就会承担析构成本。即使这个变量最终并未被使用。

例如程序中间可能会抛出异常，或者由于分支选择等原因导致某个定义的变量没被完全使用。

同时在定义的时候最好使用直接初始化。先默认初始化后赋值的效率较低。

“尽可能延后”：不只延后变量的定义，甚至延后定义直到能够给他初值实参。 C++17中延迟实质化也是这一种思想的体现，直到最后一刻才进行构造。

**对于循环**

还是在体外，赋值成本小于构造。

### 27 尽量少做cast

cast在某种程度上破坏了C++ 的type system。

**c-style**

```c++
(T)expression
T(expression)
```

避免假设“对象在C++中如何布局”，随着编译器实现他们的布局也会改变，基于此的一些行为会导致ub。

```cpp
class Window {
public:
    virtual void OnResize() { ... }
    ...
};

class SpecialWindow : public Window {
public:
    virtual void OnResize() {
        static_cast<Window>(*this).OnResize();
        ...
    }
    ...
};
```

这段代码试图通过转型`*this`来调用基类的虚函数，然而这是严重错误的，这样做会得到一个新的`Window`副本并在该副本上调用函数，而非在原本的对象上调用函数。应该如下使用：

```c++
class SpecialWindow : public Window {
public:
    virtual void OnResize() {
        Window::OnResize();
        ...
    }
    ...
};
```

对于dynamic_cast也应该尽少使用，例如：

```c++
struct Animal  { virtual ~Animal() {} };
struct Dog     : Animal { void bark() {} };
struct Cat     : Animal { void meow() {} };
struct Labrador: Dog    { void fetch() {} };

Animal* a = new Labrador;
if (Dog* d = dynamic_cast<Dog*>(a)) {
    d->bark();          
}
```

最好是在Animal声明一个virtual的bark()函数，但是什么都不做，利用虚函数的性质来进行调用。

### 28 避免返回handles指向对象内部成分

避免返回一个references/指针/迭代器指向对象内部：

- 破坏封装性、可修改权限

  ```c++
  struct Rectangle {
  private:
  	Point point;
  public:
      Point& getPoint() const { return point; }
  }
  ```

  私有成员暴露在外，且一个const成员函数返回了一个可以修改的成员。

  可以返回const& 来配合const成员函数的语义

- “handle比其所指对象更长寿”的风险降到最低

  即使是返回const，传出去的handle可能在Rectangle析构之后仍然存在，这就导致了handle悬垂。

**Notes：**

不是禁止使用，而是使得cosnt成员函数的行为符合常量性，并将发生handle悬垂的可能性降到最低。例如一些容器的opertor[]运算符重载，其实也是向外传递了一种handle

### 29 为异常安全而努力是值得的

异常安全函数提供以下三个保证之一：

- 基本承诺：如果异常被抛出，保证数据不被破坏，但是不保证恢复到之前状态，可能处于一种半更新的状态，需要额外检查。

- 强烈保证：如果异常被抛出，程序状态不改变：如果函数成功就是完全成功，如果函数失败程序会恢复到调用函数之前的状态。

- nothrow保证：承诺绝对不会抛出异常

  ```c++
  int DoSomething() noexcept;
  ```

异常安全有两个条件：当异常抛出的时候

- 不泄漏任何资源
- 不允许数据败坏：比如某些对象没有被创建，但是却增加了计数，或者被其他变量引用。

```c++
class PrettyMenu {
public:
    ...
    void ChangeBackground(std::vector<uint8_t>& imgSrc);
    ...
private:
    Mutex mutex;        // 互斥锁
    Image* bgImage;     // 目前的背景图像
    int imageChanges;   // 背景图像被改变的次数
};

void PrettyMenu::ChangeBackground(std::vector<uint8_t>& imgSrc) {
    lock(&mutex);
    delete bgImage;
    ++imageChanges;
    bgImage = new Image(imgSrc);
    unlock(&mutex);
}
```

若在函数中发生异常，mutex会发生资源泄露，bgImage/imageChanges会发生数据败坏。

资源泄露可以通过RAII来解决。

调整语序使得在bgimage创建出来以后才会进行计数增加。并使用智能指针管理image

```c++
std::shared_ptr<Image> bgImage;
void PrettyMenu::ChangeBackground(std::vector<uint8_t>& imgSrc) {
    locakRAII lock(&mutex);
    bgImage = std::make_shared<Image>(imgSrc);
    ++imageChanges;
}
```

或者是利用pimpl修改副本，然后再进行swap，这样发生异常的都是副本。**copy and swap**,全有或者全无。但是会更加耗时。

“强烈保证”带来时间和空间的开销，当不切实际的时候就需要提供“基本保证”

30 inlining

【详细见inline】

31 将文件间的编译依存关系降至最低

C++并没有把“将接口从实现中分离”这件事做得很好，一个class可能需要另一个class的详细定义，就会在头文件中包含另一个头文件，当一个头文件修改过后可能导致一连串的class/文件重新编译。

**Why?**：编译器需要在编译期间知道对象的大小。所以会include完整的定义。

- 能用引用或指针完成的，就不要用对象本身，使用对象本身（by value）要求编译器看到该类的**完整定义**（需要知道其大小）；使用引用或指针只需要**前向声明**。

- 尽量以类声明式替换类定义式。声明一个函数时，即使参数或返回值是某个类，也**不需要**该类的完整定义——只有在调用该函数、或者访问成员时才需要。

- 为声明式和定义式提供不同的头文件

  ```c++
  project/
    include/
      datefwd.h      ← 只有前向声明，超级轻量
      date.h         ← 完整定义，包含所有实现细节
    src/
      date.cpp
  ```

**解决办法：**

1.**pointer to implementation**

头文件

```c++
// Person.h —— 用户只需包含这一个文件
#include <memory>
#include <string>

class Person {
public:
    Person(const std::string& name, int age);
    ~Person();              // 必须在 .cpp 中定义（Impl 需要完整类型才能析构）
    std::string name() const;
    int age() const;

private:
    struct Impl;            // 前向声明，不需要 Date.h / Address.h
    std::unique_ptr<Impl> pImpl;
};
```

实现文件

```c++
// Person.cpp —— 只有这里需要 #include 重型头文件
#include "Person.h"
#include "Date.h"
#include "Address.h"

struct Person::Impl {
    std::string name;
    int         age;
    Date        birthDate;   // 完整类型，藏在这里
    Address     address;
};

Person::Person(const std::string& name, int age)
    : pImpl(std::make_unique<Impl>()) {
    pImpl->name = name;
    pImpl->age  = age;
}

Person::~Person() = default;  // 必须在 Impl 完整类型可见处定义

std::string Person::name() const { return pImpl->name; }
int         Person::age()  const { return pImpl->age;  }
```

调用方：

```c++
#include "Person.h"   // 只有这一行，不会被 Date.h/Address.h 的改动影响

Person p("Alice", 30);
```

cons:

- 多一次指针的间接寻址
- pimpl的析构函数必须在cpp中进行定义

2.**接口类**

```c++
// IPerson.h —— 零依赖，只有声明
#include <string>
#include <memory>

class IPerson {
public:
    virtual ~IPerson() = default;
    virtual std::string name() const = 0;
    virtual int         age()  const = 0;

    // 工厂函数：返回接口指针，调用方不需要知道具体类
    static std::shared_ptr<IPerson> create(const std::string& name, int age);
};
```

```c++
// RealPerson.h —— 内部实现，不对外暴露
#include "IPerson.h"
#include "Date.h"
#include "Address.h"

class RealPerson : public IPerson {
public:
    RealPerson(const std::string& name, int age);
    std::string name() const override;
    int         age()  const override;
private:
    std::string name_;
    int         age_;
    Date        birthDate_;
    Address     address_;
};
```

```c++
// RealPerson.cpp
#include "RealPerson.h"

RealPerson::RealPerson(const std::string& n, int a) : name_(n), age_(a) {}
std::string RealPerson::name() const { return name_; }
int         RealPerson::age()  const { return age_;  }

// 工厂函数的实现也在这里
std::shared_ptr<IPerson> IPerson::create(const std::string& n, int a) {
    return std::make_shared<RealPerson>(n, a);
}
```

```c++
#include "IPerson.h"   // 只依赖接口，完全不知道 RealPerson 存在

auto p = IPerson::create("Bob", 25);
std::cout << p->name();
```

cons:

- 每次调用都经过虚函数表，有间接调用开销

**现代C++及工程做法**

- 在C++20中import从语义上消除了头文件传递依赖的问题。
- 例如raysengine以及QT，将pimpl作为核心的设计模式
- 构建系统层面的隔离：CMake 的target_include_directories + PRIVATE,这样cmake可以阻挡路径传播，比如对一些实现文件做了private，那么在预处理器去按照include路径去找的时候会发现被隔离了。系统层面只是隔离并不能独立解决这个问题，仍然需要pimpl。
