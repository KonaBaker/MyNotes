## chapter 2

### 05 c++默认编写的函数

 一个empty class，编译器会自动编写：

```c++
class Empty {
public:
    Empty() { ... }                           // 默认构造函数（没有任何构造函数时）
    Empty(const Empty&) { ... }               // 拷贝构造函数
    Empty(Empty&&) { ... }                    // 移动构造函数 (since C++11)
    ~Empty() { ... }                          // 析构函数
    
    Empty& operator=(const Empty&) { ... }    // 拷贝赋值运算符
    Empty& operator=(Empty&&) { ... }         // 移动赋值运算符 (since C++11)
};
```

只有当这些函数被需要（被调用）的时候，才会被编译器创建出来。

对于**拷贝构造函数**，相当于对每个成员执行**初始化**：

- 引用成员会被绑定到与源对象相同的对象上。
- const成员逐bit拷贝，是独立的一份。

对于**拷贝赋值运算符**，在以下情况下不会被自动创建：

- 包含引用类型，语义上不能重新绑定。
- 包含const成员，语义上不能修改。
- 基类中含有private的拷贝赋值运算符

### 06 不想使用编译器自动生成的函数，就应该明确拒绝

使用delete:

```c++
class Uncopyable {
public:
    Uncopyable(const Uncopyable&) = delete;
    Uncopyable& operator=(const Uncopyable&) = delete;
};
```

### 07 为多态base class声明virtual析构函数

当派生类对象经由一个基类指针被删除，而该基类指针带着一个非虚析构函数，其结果是未定义的，可能会无法完全销毁派生类的成员，造成内存泄漏。消除这个问题的方法就是对基类使用虚析构函数：

```c++
class Base {
public:
    Base();
    virtual ~Base();
};
```

只要基类的析构函数是虚函数，那么派生类的析构函数不论是否用virtual关键字声明，都自动成为虚析构函数。

反过来，如果你不想让一个类成为基类，那么在类中声明虚函数，会引入虚函数表，使得类的存储更大。



也需要注意，在继承的时候注意，基类是否带有virtual，例如：

```c++
class SpecialString: public std::string {
}
SpecialString* pss = new SpecialString("Impending Doom");
std::string* ps;
ps = pss;
delete ps; // ub
```



当你想让一个类成为抽象类，但**又没有其他合适的函数可以设为纯虚时**，就把析构函数设为纯虚，并且**提供一个定义**。

虚析构函数的运作方式是，最深层派生的那个类的析构函数最先被调用，然后是其上的基类的析构函数被依次调用。派生类的析构函数中会创建一个基类析构的调用动作，所以基类析构必须要有一份定义，否则会链接错误。

对于普通函数没有析构函数这样的调用链，所以普通纯虚函数无需提供定义。

```c++
class Foo {
    public:
    	virtual ~Foo() = 0;
}
Foo::~Foo() {};
```

**补充：**

**pure virtual function**:纯虚函数，表示声明一个接口但是不在本类实现，需要派生类传达一个要求：要覆盖它。

**abstract class**: 含有至少一个纯虚函数的类就是抽象类。其不能进行实例化。派生类必须实现所有纯虚函数，否则自己本身也是抽象类

```c++
class Base {
public:
    virtual void f1() = 0;
    virtual void f2() = 0;
};

class Mid : public Base {
public:
    void f1() override {}  // 只实现了一个
    // f2 仍是纯虚的
};
// Mid 仍然是抽象类！

class Derived : public Mid {
public:
    void f2() override {}  // 补全了剩余的纯虚函数
};
// Derived 是具体类，可以实例化
```

### 08 别让异常逃离析构函数

为了实现 RAII，我们通常会将对象的销毁方法封装在析构函数中，如下例子：

```cpp
class DBConn {
public:
    ...
    ~DBConn() {
        db.close();    // 该函数可能会抛出异常
    }

private:
    DBConnection db;
};
```

但这样我们就需要在析构函数中完成对异常的处理，以下是几种常见的做法：

第一种：杀死程序：

```cpp
DBConn::~DBConn() {
    try { db.close(); }
    catch (...) {
        // 记录运行日志，以便调试
        std::abort();
    }
}
```

第二种：重新设计接口，将异常的处理交给客户端完成：

```cpp
class DBConn {
public:
    ...
    void close() {
        db.close();
        closed = true;
    }

    ~DBConn() {
        if (!closed) {
            try {
                db.close();
            }
            catch(...) {
                // 处理异常
            }
        }
    }

private:
    DBConnection db;
    bool closed;
};
```

在这个新设计的接口中，我们提供了`close`函数供客户手动调用，这样客户也可以根据自己的意愿处理异常；若客户忘记手动调用，析构函数才会自动调用`close`函数。

当一个操作可能会抛出需要客户处理的异常时，将其暴露在普通函数而非析构函数中是一个更好的选择。析构函数没有上层可以捕获它的异常，

**补充：**

**1.异常传播**:

```C++
main() → f1() → f2() → f3()   // 调用链，栈一层层叠加
```

当 `f3()` 抛出异常，C++ 会**反向**逐层寻找能处理它的 `catch`：

```C++
f3() 抛出异常
  → 检查 f3() 有没有 catch？没有 → 退出 f3()，析构其局部变量
  → 检查 f2() 有没有 catch？没有 → 退出 f2()，析构其局部变量
  → 检查 f1() 有没有 catch？有！→ 进入 catch 块处理
```

这个**反向逐层退出、析构局部变量的过程**就叫做**栈展开（Stack Unwinding）**，异常在栈上"向上传播"。

如果有这样一个调用链条：

```c++
f1() -> f2()
```

```c++
void f1() {
    DB Conn conn;
    foo();
}
```

如果foo()抛出异常，那么这个异常将会向上传播，f1的局部对象就会被销毁，但是此时如果销毁过程中析构也出现了异常，此时就会同时出现两个正在传播的异常，而C++没有机制可以处理这种情况，所以程序会直接崩溃。

> 若在栈展开的过程中，析构函数抛出了异常，则调用std::terminate()

### 09 不在构造或者析构函数中调用virtual函数

在创建派生类对象时，基类的构造函数永远会早于派生类的构造函数被调用，而基类的析构函数永远会晚于派生类的析构函数被调用。在派生类对象的基类构造和析构期间，对象的类型是基类而非派生类，因此此时调用虚函数会被编译器解析至基类的虚函数版本，通常不会得到我们想要的结果。

同理在派生类的析构函数永远会早于基类的析构函数被调用，基类析构函数中包含的虚函数，无法调用已被析构的派生类的对应版本。

如果想要基类在构造时就得知派生类的构造信息，推荐的做法是在派生类的构造函数中将必要的信息向上传递给基类的构造函数：

```cpp
class Transaction {
public:
    explicit Transaction(const std::string& logInfo);
    void LogTransaction(const std::string& logInfo) const;
    ...
};

Transaction::Transaction(const std::string& logInfo) {
    LogTransaction(logInfo);                           // 更改为了非虚函数调用
}

class BuyTransaction : public Transaction {
public:
    BuyTransaction(...)
        : Transaction(CreateLogString(...)) { ... }    // 将信息传递给基类构造函数
    ...

private:
    static std::string CreateLogString(...);
}
```

这里`CreateLogString`是静态成员函数，没有this指针，确保了在构造的时候（此时成员变量还没有初始化），这个函数不会使用未初始化的成员。

### 10 operator= 返回一个*this的引用

```c++
class Widget {
public:
    Widget& operator+=(const Widget& rhs) {    // 这个条款适用于
        ...                                    // +=, -=, *= 等等运算符
        return *this;
    }
    Widget& operator=(int rhs) {               // 即使参数类型不是 Widget& 也适用
        ...
        return *this;
    }
};
```

为了实现连锁赋值

`x=y=z=5`

### 11 operator= 中处理自我赋值

````C++
w = w;
a[i] = a[j]; // i == j
*px = *py; // px py指向相同
````

如果不处理，下面的代码就会产生问题：

```c++
Widget& operator+=(const Widget& rhs) {
    delete pRes;                          // 删除当前持有的资源
    pRes = new Resource(*rhs.pRes);       // 复制传入的资源
    return *this;
}
```

解决办法：

- 证同测试

```c++
Widget& operator=(const Widget& rhs) {
    if (this == &rhs) return *this;        // 若是自我赋值，则不做任何事

    delete pRes;
    pRes = new Resource(*rhs.pRes);
    return *this;
}
```

- 更改设计，保存原来的指针

```c++
Widget& operator=(const Widget& rhs) {
    Resource* pOrigin = pRes;             // 先记住原来的pRes指针
    pRes = new Resource(*rhs.pRes);       // 复制传入的资源
    delete pOrigin;                       // 删除原来的资源
    return *this;
}

```

- copy&swap

利用了栈空间会自动释放的特性，通过析构函数来实现资源的释放：

```c++
Widget& operator=(Widget rhs) {
    std::swap(*this, rhs);
    return *this;
}
```

按值传参会自动析构。

**确保任何函数如果操作一个以上的对象，而其中多个对象是同一个对象的时候，其行为仍然正确。**

### 12 复制对象的时候不要遗漏每一个成分

如果自己声明copy构造函数或者copy assignment操作符。

尤其在继承中，所有的派生类，不能遗漏继承自基类的副本，这是需要调用所有基类的适当的copying函数。

```c++
class PriorityCustomer : public Customer {
public:
    PriorityCustomer(const PriorityCustomer& rhs);
    PriorityCustomer& operator=(const PriorityCustomer& rhs);
    ...

private:
    int priority;
}

PriorityCustomer::PriorityCustomer(const PriorityCustomer& rhs)
    : Customer(rhs),                // 调用基类的拷贝构造函数
      priority(rhs.priority) {
    ...
}

PriorityCustomer::PriorityCustomer& operator=(const PriorityCustomer& rhs) {
    Customer::operator=(rhs);       // 调用基类的拷贝赋值运算符
    priority = rhs.priority;
    return *this;
}
```



**不要尝试在拷贝构造函数中调用拷贝赋值运算符，或在拷贝赋值运算符的实现中调用拷贝构造函数，一个在初始化时，一个在初始化后，它们的语义是不同的。**

