**std::optional<T>**

表示一个可能有值的对象，没有值就是`std::nullopt`一个空类类型

### usage

**create**

```c++
std::optional<int> v = std::nullopt;
auto v = std::make_optional(3.0);
opt.emplace(args...);    // 原地构造,避免一次额外的移动/拷贝
opt.reset();             // 等价于 opt = std::nullopt
```

`. value`返回它的值

`.has_value` 

**access**

```c++
// 跟指针的使用类似，访问没有 value 的 optional 的行为是未定义的，需要提前检查
cout << (*ret).out1 << endl; 
cout << ret->out1 << endl;

// 当没有 value 时调用该方法将 throws std::bad_optional_access 异常，安全的方法
cout << ret.value().out1 << endl;

// 当没有 value 调用该方法时将使用传入的默认值
Out defaultVal;
cout << ret.value_or(defaultVal).out1 << endl;

std::optional<bool> opt = false;
if (opt) {        // true!  (检查的是 has_value)
    if (*opt) {   // false (才是真正的值)
    }
}
```

**compare**

empty是小于任何值的

```
std::optional<int> a;             // empty
std::optional<int> b = 5;
a < b;          // true,empty 小于任何值
a == std::nullopt;  // true
b == 5;         // true,可以直接和 T 比
```

**assign**

- 对于原本为空的情况，需要placement new构造一个新的T
- 对于原本有值的情况，拷贝赋值。

**ill-formed**:

不能创建存储“引用”、“函数”、“数组”、“void”以及特定标记类型的 `std::optional`

- `std::optional<int&>`**(c++26已经支持)** rebind而非赋值给被引用对象
- `std::optional<int(int)>`
- `std::optional<int[10]>`
- `std::optional<void>`
- `std::optional<std::nullopt_t>`

原因：需要预分配内存，函数，void未知大小。

---

### 内存与传递开销

内部包含了一块足以容纳T的内存区域，不会额外的new一个然后指向它。**optional只承诺不额外申请内存**，如果optional本身在栈上，那么对象也会在栈上，如果optional通过unique分配在了堆上，那么其中的对象也会在堆上。

**生命周期**：

```
optional 生命周期:    [════════════════════════════════]
                      ↑                                ↑
                   构造 opt                         析构 opt

T 生命周期:                    [═══════════]
                               ↑           ↑
                          opt = "hi"   opt.reset()
```



可以认为optional是这样定义的：

```c++
template <typename T>
struct optional {
    union {
        char _dummy;     // 当 _has_value == false 时使用
        T _value;        // 当 _has_value == true 时使用,需要 placement new 显式构造
    };
    bool _has_value;
};
```

placement new并不等于堆分配，它可以是分配内存构造对象也可以只是构造对象，且无论这块内存在哪里。

union在任何时刻最多只有一个成员是active的，预留了一块对齐合适、大小足够的内存。但是其中没有对象：

```c++
std::optional<std::string> opt;       // 内存已存在,但里面没有 string 对象
opt = "hello";                         // 这一步必须在那块内存上构造一个 string
                                       // ↑ 实现内部就是 placement new
// 其他方式
void emplace(auto&&... args) {
    ::new (&_value) T(std::forward<decltype(args)>(args)...); // placement new
    _has_value = true;
}

void reset() {
    if (_has_value) {
        _value.~T();          // 显式调用析构(对应地)
        _has_value = false;
    }
}
```



额外内存开销来自两部分：

- bool 1byte
- padding

例：

`std::optional<int>`

bool: 1 + padding: 3 + int: 4 = 8  => 100% up

`std::optional<double>`

bool: 1 + padding: 7 + double: 8 = 16 => 100% up

内存开销会变大。

---

### [关于传递](https://abseil.io/tips/163)

optional本身作为**值语义**，对于value的调用，返回的都是值本身`T`。应当避免使用`const std::optional&`作为函数参数，如果严格限制传入`const std::optional<T>&`是可以的，但是如果传入了T,那么会有隐式转换，会有临时std::optional的出现，无法避免的会复制，所以一般作为返回值使用而不是参数传递。

**关于传递参数的构造问题**

对于函数`void func(std::optional<T> bar)`传入参数`T`

会在函数参数栈上提前预留好内存， bool | padding | 预留T 但是并没有实际的对象。

- 实参是**左值** `T`:匹配 `optional(const T&)`,内部用拷贝构造把 `T` 放进 storage,**T 拷贝 1 次**;
- 实参是**右值** `T`:匹配 `optional(T&&)`,内部用移动构造,**T 移动 1 次**;
- 实参是**纯右值**(如 `T{...}`):匹配`optional(T&&)`，这个要求有一个T参数存在，所以延迟初始化到构造一个临时对象T，所以仍然需要**一次构造加移动**
- 使用in_place可以直接内部构造，而减少了移动的的开销：`std::optional<std::string> opt(std::in_place, "world");`

以上两种构造由于optional的 copy elision,在被optional的构造函数调用时，也是直接在函数参数栈分配的预留T内存上构造。省略的是 "`optional` 这一层临时对象",**不省略 `T` 自身的拷贝/移动**。`T` 的那一次开销是值语义传参不可避免的代价。

**Notes**:

对于小类型比如`int`/`string_view`使用按值传递。

对于大类型比如`string`/`T`按值传递会至少造成一次拷贝构造或者移动构造，所以此时使用**const T***或者**const T&**是更好的选择。

---

### 与`std::pair`方法相比

`std::pair<bool, T>`在无值的时候（bool为false)的时候T仍然会被默认构造，且强制要求T可以默认构造。而`std::optional`在无值的时候不会进行构造，所以这是一种语义上的优势。

---

### 适用情况

**不要滥用**optional，通过指针或者引用来进行传递是更好的选择。例如`optional<T*>`，直接使用`T*`就行，因为指针的`nullptr`已经能够表达"无值"

适用情况：

- 类的成员变量
- 函数的返回值

使用的前提一定是，**逻辑上确实可能为空**

滥用会导致：

- 因optional被迫做冗余检查
- 破坏构造即有效原则
- 内存膨胀









