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
