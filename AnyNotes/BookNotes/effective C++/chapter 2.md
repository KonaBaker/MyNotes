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

