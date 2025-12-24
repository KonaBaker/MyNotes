**std::optional<T>**

> 其他方法（例如 std::pair）相比， `optional` 能很好地处理构造成本高昂的对象，并且更具可读性，因为其意图被明确地表达出来。

表示一个可能有值的对象，没有值就是`std::nullopt`一个空类类型

**create**

```c++
std::optional<int> v = std::nullopt;
auto v = std::make_optional(3.0);
```

`.value`返回它的值

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

```

**ill-formed**:

不能创建存储“引用”、“函数”、“数组”、“void”以及特定标记类型的 `std::optional`

- `std::optional<int&>`
- `std::optional<int(int)>`
- `std::optional<int[10]>`
- `std::optional<void>`
- `std::optional<std::nullopt_t>`

原因：需要预分配内存，函数，void未知大小，关于引用改本身还是改地址？

**内存与传递开销**

没有堆分配，内部包含了一块足以容纳T的内存区域，不会在堆上new一个然后指向它。且optional和T的生命周期是一致的。

可以认为optional是这样定义的：

```c++
template <typename T>
struct optional {
    bool _has_value; // 标记位：表示当前是否存储了值
    alignas(T) byte _storage[sizeof(T)]; // 实际存储 T 的原始内存
};
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

**[关于传递](https://abseil.io/tips/163)**

optional本身作为**值语义**，应当避免使用`const std::optional&`作为函数参数，如果严格限制传入`const std::optional<T>&`是可以的，但是如果传入了T,那么会有隐式转换，会有临时std::optional的出现，无法避免的会复制，所以一般作为返回值使用而不是参数传递。

如果对象足够小，比如int\string_view等，可以直接作为值来传递

```c++
void MyFunc(std::optional<int> bar);
void MyFunc(std::optional<absl::string_view> baz);
```

对于其他情况，**不要滥用**optional，通过指针或者引用来进行传递是更好的选择。

适用情况：

- 类的成员变量
- 函数的返回值

使用的前提一定是，逻辑上确实可能为空

滥用会导致：

- 因optional被迫做冗余检查
- 破坏构造即有效原则
- 内存膨胀

**关于传递参数的构造问题**

对于函数`void func(std::optional<T> bar)`传入参数`T`

无论如何std::optional本身都是要构造的。构造之后在函数参数栈上就会分配内存 bool | padding | 预留T ----- 这一部也就是应用了[copy elision](./copyelision&RVO.md)的一步，没有optional的临时对象产生，直接在函数参数栈上进行构造。

- 对于右值调用 optional(T&&)  内部会调用T的移动构造函数

- 对于左值调用 optional(const T&)  内部会调用T的拷贝构造函数

以上两种构造由于optional的 copy elision,在被optional的构造函数调用时，也是直接在函数参数栈分配的预留T内存上构造







