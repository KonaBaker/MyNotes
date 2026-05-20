## chapter 3 - resource management

### 13 以对象管理资源

利用析构函数的自动调用机制，RAII。**在构造函数中获得资源，并在析构函数中释放资源**。

通过专一所有权来管理RAII对象可以使用`std::unique_ptr`，通过引用计数来管理RAII对象可以使用`std::shared_ptr`。

```cpp
// Investment* CreateInvestment();

std::unique_ptr<Investment> pUniqueInv1(CreateInvestment());
std::unique_ptr<Investment> pUniqueInv2(std::move(pUniqueInv1));    // 转移资源所有权

std::shared_ptr<Investment> pSharedInv1(CreateInvestment());
std::shared_ptr<Investment> pSharedInv2(pSharedInv1);               // 引用计数+1
```

智能指针默认会自动delete所持有的对象，我们也可以为智能指针指定所管理对象的释放方式（删除器deleter）：

```c++
// void GetRidOfInvestment(Investment*) {}

std::unique_ptr<Investment, decltype(GetRidOfInvestment)*> pUniqueInv(CreateInvestment(), GetRidOfInvestment);
std::shared_ptr<Investment> pSharedInv(CreateInvestment(), GetRidOfInvestment);

```

### 14 在RAII中小心copy

智能指针一般适用与heap-based资源，其他资源可以自己创建资源管理类来进行管理。

RAII copy有以下几个选择：

- 禁止复制。如果一个RAII对象被复制并不合理，比如锁，那么就明确禁止复制行为，具体做法可以见条款06
- 底层资源使用“引用计数法”。类似shared_ptr。
- 复制底层资源。对RAII进行深拷贝。
- 转移底层资源的所有权。类似unique_ptr。

### 15 在RAII中提供对原始资源的访问

就像只能指针一样：

```c++
Investment* pRaw = pSharedInv.get();    // 显式访问原始资源
Investment raw = *pSharedInv;           // 隐式访问原始资源
```

自己设计的时候，也需要提供get()或者operator*/operator->

```c++
class Font {
public:
    FontHandle Get() const { return handle; }       // 显式转换函数
    operator FontHandle() const { return handle; }  // 隐式转换函数

private:
    FontHandle handle;
};

```

### 16 成对使用new / delete 要采用相同的形式

使用`new`来分配单一对象，使用`new[]`来分配对象数组，必须明确它们的行为并不一致，分配对象数组时会额外在内存中记录“数组大小”，而使用`delete[]`会根据记录的数组大小多次调用析构函数，使用`delete`则仅仅只会调用一次析构函数。对于单一对象使用`delete[]`其结果也是未定义的，程序可能会读取若干内存并将其错误地解释为数组大小。

```cpp
int* array = new int[10];
int* object = new int;

delete[] array;
delete object;
```

如果在调用new的时候使用[]，你必须在对应delete的时候也使用[]

需要注意的是，使用`typedef`定义数组类型也是这样的。

```cpp
typedef std::string AddressLines[4];

std::string* pal = new AddressLines;    // pal 是一个对象数组，而非单一对象

delete pal;                             // 行为未定义
delete[] pal;                           // 正确
```

### 17 以独立语句将newed对象置入智能指针

 ```c++
 auto pUniqueInv = std::make_unique<Investment>();    // since C++14
 auto pSharedInv = std::make_shared<Investment>();    // since C++11
 ```

