动态内存与智能指针

程序使用heap来存储动态分配的对象。动态对象的生存期由程序来进行控制，需要进行显式的销毁。

智能指针

定义在memory中，用来管理动态对象，shared_ptr允许多个指针指向同一个对象，unique_ptr独占所指向的对象。除此之外，有一个伴随类，weak_ptr。

## shared_ptr

同vector一样也是一个模板，需要提供类型。

### usage

```c++
std::shared_ptr<std::string> p1;
if(p1 && p1->empty())
    *p1 = "hi"
std::string* p2 = p1.get();
std::shared_ptr<std::string> p3(p1); // 增加计数器
std::shared_ptr<std::string> p4;
p4 = p1; // p4减，p1加
if(p.unique()) {
    assert(p.use_count() == 1);
}
```

**make_shared**

是一种分配和使用动态内存的方法。可以在动态内存中分配一个对象并初始化它，返回指向此对象的shared_ptr。

```c++
auto p = std::make_shared<int>(42);
```

和emplace的直接构造一样，这里接收的也是参数。调用operator new分配内存 -> placement new  完美转发参数 -> 调用对应构造函数。

**copy&assignment**

拷贝或赋值，会造成引用计数器的增减。当引用计数器归零的时候，会通过析构函数自动销毁对象，释放内存。

```c++
std::shared_ptr<Foo> f(){
    auto p = std::make_shared<Foo>();
    return p;
}
```

返回的时候会进行拷贝，p销毁的时候，还有其他引用者。

如果将shared_ptr存放在一个容器之中，当不再需要某个元素的时候，需要调用erase删除，否则会浪费内存。

### circumstance

在以下情况会使用动态内存：

- 程序不知道自己需要使用多少对象

  例如容器类，就是出于这个原因需要使用动态内存。

- 程序不知道所需对象的准确类型

  例如多态。

- 程序需要在多个对象间共享数据/状态

  自己销毁的时候，其他还能用，就是shared_ptr。


## new/delete

### new

在heap分配的内存是无名的，new无法为分配的对象命名，而是返回一个指向该对象的指针。

usage

```c++
// 默认初始化
int* pi = new int;
string* ps = new string;
// 直接初始化
int* pi = new int(1024); 
std::vector<int>* pv = new vector<int>(0, 1);
// 值初始化
int* pi = new int();
string* ps = new string();
```

**补充**：

对于定义了自己的构造函数的类类型，默认初始化和值初始化都会通过默认构造函数来进行初始化，但是对于内置类型，值初始化会有默认定义值，而默认初始化是未定义的（对于依赖默认构造函数初始化的类内内置类型成员，如果没有在类内被初始化，那么他们的值也是未定义的）

```c++
void foo() {
    int a;    // 默认初始化 → 值未定义！读取是 UB
    int b{};  // 值初始化  → 零初始化，b == 0，安全
    int c = int(); // 值初始化，c == 0
}
```

```c++
struct Trivial {
    int x;
    double y;
};

Trivial t1;    // 默认初始化 → x, y 值未定义！
Trivial t2{};  // 值初始化  → x==0, y==0.0，安全
```

```c++
struct MyClass {
    int id;
    double value;

    // 用户定义了默认构造函数，但没有初始化成员！
    MyClass() {
        // id 和 value 在这里没有被初始化
    }
};

MyClass a;    // 默认初始化 → 调用 MyClass()，id/value 未定义
MyClass b{};  // 值初始化  → 也调用 MyClass()，id/value 依然未定义！
```

**const对象**

```c++
const int *pci = new const int(1024);
const string *pcs = new const string;
```

和其他任何const对象一样，动态分配的const对象必须进行初始化。其次，还必须保证值有定义。

```c++
const int* p1 = new int;   // 编译错误
```

对于默认初始化，需要有默认构造函数，否则必须显式初始化。

### delete

delete expression。

delete的指针必须指向动态分配的内存或者一个空指针。释放一个非new分配的内存，或者将相同的内存释放多次,是ub。

```c++
int i, *pi1 = &i, *pi2 = nullptr;
double *pd = new double(33), *pd2 = pd;
delete i; // x
delete pi1; // ub 编译器无法分辨指向的是静态还是动态分配的对象。
delete pd; // v
delete pd2; // ub 编译器无法分辨一个内存是否已经释放过了
delete pi2; // v
const int *pci = new const int(1024);
delete pci;
```

## shared_ptr和new结合使用

如果不初始化一个智能指针，就会被初始化为一个空指针。除此之外，还可以**使用new返回的指针**来初始化智能指针。**这个内置指针只能指向动态内存，因为智能指针默认使用delete释放它所关联的对象。

```c++
std::shared_ptr<T> p(q); // q是指向new分配的内存，且能够转换为T*类型。
std::shared_ptr<T> p(u); // u是unique_ptr,接管资源并置为空。
std::shared_ptr<t> p(q, d); // 额外指定了删除器。
std::shared_ptr<T> p(p2, d); // p2为智能指针（非上面的内置指针），额外指定了删除器。

// reset释放对象之后，（如果有）再指向新的内置指针。不可以直接等号赋值
p.reset();
p.reset(q);
p.reset(q, d);
```

接受指针参数的构造函数都是explicit的，无法进行隐式转换，必须使用直接初始化的方式：

```c++
std::shared_ptr<int> p1 = new int(1024); // x
std::shared_ptr<int> p2(new int(1024));
```

同样对于explicit的规则，我们不能在返回值的时候直接返回内置指针，需要显式构造一个智能指针。

### Notes

**不要混合使用普通指针和智能指针**

在使用shared_ptr的时候，推荐使用make_shared而不是new，避免无意中将同一块内存绑定到多个独立创建的shared_ptr上。（引用计数不会增长）

```C++
Foo* foo = new Foo();
std::shared_ptr<Foo> sp1(foo);
assert(sp1.use_count() == 1);
std::shared_ptr<Foo> sp2(foo);
assert(sp2.use_count() == 1);
assert(sp1.use_count() == 1);
```

当将一个shared_ptr绑定到一个内置指针的时候，就意味着所有权的转移，这个时候就不应该再继续使用内置指针访问这块内存。

**不要使用get初始化另一个智能指针或者对其进行赋值**

明确.get()是用于向不能使用智能指针的代码传递一个内置类型。其不能被delete也不能用于绑定到其他智能指针。

同样的，使用get内置类型指针绑定到多个独立创建的shared_ptr上仍然不会增加引用计数。这样可能会导致内存被错误的提前释放，产生ub。

## unique_ptr

unique拥有它所指向的对象：

### usage

定义一个unique_ptr的时候，需要将其绑定到一个new返回的指针上。初始化必须采用**直接初始化**。

且禁止从另一个unique_ptr进行拷贝和赋值。

```c++
std::unique_ptr<int> p2(new int(42));
```

```c++
std::unique_ptr<T> u1;
std::unique_ptr<T, D> u2;
std::unique_ptr<T, D> u(d); // d是D类型的删除器

u = nullptr; // 释放u指向的对象，并置空。

u.release(); // 放弃u对指针的控制权。同时返回指针，将u置空,返回值通常被用来初始化另一个智能指针或者给另一智能指针赋值
u.reset(); // 释放u指向的对象。
u.reset(q); // 重新指向内置指针q
u.reset(nullptr);
```

reset的执行顺序是先构造临时shared_ptr(分配控制块)，然后进行swap，然后利用临时变量的析构进行释放：

```c++
std::share_ptr<T> tmp(q);
p.swap(tmp);
```

**copy&assign**

```c++
std::unique_ptr<int> p(new int(42));
std::unique_ptr<int> p2;
p2.reset(p.release());

// 可以进行移动拷贝(可以拷贝或赋值一个将要销毁的unique_ptr)
unique_ptr<int> p1 = make_unique<int>(42);
unique_ptr<int> p2;
p2 = std::move(p1);

// NRVO优化。无须std::move
unique_ptr<int> createInt() {
    auto p = make_unique<int>(42);
    return p;
}
```

**release不会释放对象**

```C++
p2.release(); // 不会释放内存，而且丢失了指针
auto nativeP = p2.release() // v
```

**注意**：这里移动的是unique_ptr本身，并不是其包含的对象，移动是指针。

## weak_ptr

不控制所指向对象生存期的智能指针，指向一个由shared_ptr进行管理的对象。不增加引用计数，指向对象仍然可以释放，**弱共享**。

适用于**一切应该不具有对象所有权，又想安全访问对象的情况。**

```C++
std::weak_ptr<T> w;
std::weak_ptr<T> w(sp);
w = p;
w.reset();
w.use_count();
w.expired(); // use_count为0,返回true,否则返回false
w.lock(); // expired为true,返回一个空的shared_ptr,否则返回一个指向w的对象的shared_ptr
```

由于对象可能不存在，我们不能使用weak_ptr直接访问对象，必须调用lock。同时lock还是一个原子操作。

## 动态数组

在动态内存中分配一块连续的内存。

### new

对于new T[n]是动态分配能容纳n个T对象的连续内存，并立即对每个元素调用构造函数，分配和构造是同时发生的。使用delete[]

**初始化**

```c++
// 默认初始化：内置类型值不确定
int* p1 = new int[10];        // 值未定义

// 值初始化：加 ()，内置类型初始化为 0
int* p2 = new int[10]();      // 全部为 0

// 列表初始化（C++11 起）
int* p3 = new int[5]{1,2,3};  // 1,2,3,0,0

delete[] p1; delete[] p2; delete[] p3;
```

**cons**

- 无法使用范围for(`for (int num : nums) `)，编译器不知道大小
- 可能资源泄露
- 分配即构造，无法在位置元素数量的时候推迟构造。

### 使用smart ptr管理动态数组

**unique_ptr**

```c++
std::unique_ptr<string[]> up = std::make_unique<string[]>(10);
up[0] = "hello";
string* raw = up.get();
```

析构的时候自动调用delete[]

**shared_ptr**

```C++
// C++17：shared_ptr 原生支持 T[]
shared_ptr<int[]> sp = std::make_shared<int[]>(10);

// C++20：也可以值初始化
shared_ptr<int[]> sp2 = std::make_shared<int[]>(10, 0);
sp[0] = 42;
```

### allocator

```c++
std::allocator<T> a;
a.allocate(n); // 分配能容纳n个T的原始内存，返回T*
a.deallocate(p, n); // 释放p开始的n个对象的内存 
auto* p = std::construct_at(p, args); // 在p处构造，支持范围
std::destroy_at(p); // 在p处销毁，支持范围
```

**allocator_traits**

是支持泛型容器的一个接口，比如要写一个泛型容器`MyVec<T, Alloc>` Alloc可以是任意的allocator，来自std或者开源库，甚至是自己写的。allocator_traits统一了不同行为，对于缺失成员有自动补全的默认行为。

除此之外还统一了一套类型：
`allocator_traits<A>::`

`value_type `元素类型 ,默认为`A::value_type`（必须有）

`pointer`指针类型 默认为`value_type*` 

`size_type`大小类型 默认为`std::size_t`

`difference_type`差值类型 默认为`std::ptrdiff_t`

`propagate_on_container_copy_assignment`容器拷贝赋值时是否传播 alloc 默认为`false_type`

**例子**

```c++
SimpleVec — C++20 风格完整实现

#include <memory>
#include <algorithm>
#include <initializer_list>

template<typename T>
class SimpleVec {
    using Alloc  = std::allocator<T>;
    using Traits = std::allocator_traits<Alloc>;

    Alloc   _alloc;
    T*      _begin = nullptr;   // 内存起点
    T*      _end   = nullptr;   // 已构造元素的尾后
    T*      _cap   = nullptr;   // 内存尾后

public:
    SimpleVec() = default;

    SimpleVec(std::initializer_list<T> il) {
        reallocate(il.size());
        for (const auto& v : il)
            Traits::construct(_alloc, _end++, v);
    }

    void push_back(T val) {
        if (_end == _cap)
            reallocate(_begin ? (size_t)(_cap-_begin)*2 : 1);
        Traits::construct(_alloc, _end++, std::move(val));
    }
    
    // 也可以这样写：
    // ----------
    template<typename U>
    	requires std::is_constructible_v<T, U>   // C++20 概念约束
    void push_back(U&& val) {
        if (_end == _cap)
            reallocate(_begin ? (size_t)(_cap - _begin) * 2 : 1);
        Traits::construct(_alloc, _end++, std::forward<U>(val));
    }
    // ----------

    void pop_back() {
        Traits::destroy(_alloc, --_end);  // 析构，不释放内存
    }

    T& operator[](size_t i) { return _begin[i]; }
    size_t size()     const { return (size_t)(_end - _begin); }
    size_t capacity() const { return (size_t)(_cap - _begin); }

    ~SimpleVec() {
        std::destroy(_begin, _end);            // ① 析构所有元素
        Traits::deallocate(_alloc, _begin,     // ② 释放内存
            (size_t)(_cap - _begin));
    }

private:
    void reallocate(size_t new_cap) {
        T* new_mem = Traits::allocate(_alloc, new_cap);
        T* new_end = new_mem;

        // move 已有元素到新内存
        for (T* p = _begin; p != _end; ++p, ++new_end)
            Traits::construct(_alloc, new_end, std::move(*p));

        // 清理旧内存
        std::destroy(_begin, _end);
        if (_begin) Traits::deallocate(_alloc, _begin,
            (size_t)(_cap - _begin));

        _begin = new_mem; _end = new_end;
        _cap   = new_mem + new_cap;
    }
};
```

**Notes:**

绝大部分情况直接使用STL提供的容器即可，无需自己管理动态数组。一般写容器内部的时候才会用裸allocator。































