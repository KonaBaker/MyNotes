## new / placement new / construct_at

### operator new

**new expression**: `new T(args)`这一整个被称作new expression不是operator。其背后调用operator new分配内存，之后再调用构造函数。

**operator new**: 是一个普通函数，分配原始内存。

 对于`T* p = new T(args)`大概会有编译器展开为：
```C++
// 伪代码
void* mem = ::operator new(sizeof(T), std::align_val_t{alignof(T)});  // 步骤 1：分配，相当于malloc，返回void*
try {
    T* p = ::new (mem) T(args);  // 步骤 2：构造。::new是new expression，但是指定了(mem)这个placement参数，所以是placement new
} catch (...) {
    ::operator delete(mem, std::align_val_t{alignof(T)});  // 构造失败则回收内存
    throw;
}
```

对于

```c++
T* p = ::new (mem) T(args);
```

相当于是：
```C++
T* p = static_cast<T*>(mem);
p->T::T(args); // 调用构造函数
```



### placement new

在头文件`<new>`中

```c++
void* operator new  (std::size_t, void* p) noexcept;
void* operator new[](std::size_t, void* p) noexcept;
```

实现就是简单地把传进来的指针 `p` 原样返回。严格来说**placement new是operator new**的一种特殊重载

**usage**

```c++
#include <new>
#include <cstddef>
#include <iostream>

struct Foo {
    int x;
    Foo(int v) : x(v) { std::cout << "Foo(" << v << ")\n"; }
    ~Foo()           { std::cout << "~Foo(" << x << ")\n"; }
};

int main() {
    alignas(Foo) std::byte buf[sizeof(Foo)];   // 1. 准备一块原始内存（注意对齐）
    Foo* p = new (buf) Foo(42);                 // 2. 在 buf 上构造对象
    std::cout << p->x << '\n';
    p->~Foo();                                  // 3. 必须手动调析构函数
}                                               // 4. buf 自身在这里随栈释放
```

- 对于大对象，先分配内存，之后反复构造、析构小的对象。
- 容器
- 共用内存，比如union，在同一块内存上切换不同类型。



### construct_at & destroy_at

```c++
#include <memory>

Foo* p = std::construct_at(reinterpret_cast<Foo*>(buf), 42);
// 等价于：::new (static_cast<void*>(reinterpret_cast<Foo*>(buf))) Foo(42)

std::destroy_at(p);
// 等价于：p->~Foo()
```

- 不支持构造数组类型。
- 只接收直接初始化，列表初始化不可以

```c++
struct P { int x, y; };

P* p = std::construct_at(addr, 1, 2);     // ❌ 编译错误：不是 P(1, 2) 这种构造
```



在constexpr中是可以使用的。