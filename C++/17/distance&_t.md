**std::distance**

```c++
template <class Iterator>
typename std::iterator_traits<Iterator>::difference_type // 迭代器的距离类型
distance(Iterator first, Iterator last);
```

接收两个迭代器参数，并返回他们之间的距离。



大部分容器迭代器的difference_type的实际类型是`std::ptrdiff_t`：

一个有符号整型，64位系统一般是long或者long long专门用于表示两个指针差值的结果。

---

**C/C++里不同整数类型的出现，是为了表达“这个数到底表示什么”**。

`size_t`

非负整数

- 内存地址
- 数组大小
- 容器大小

`ptrdiff_t`

专门表示两个指针/迭代器的差，偏移量、相对距离。可能为负。

```c++
using ptrdiff_t = decltype(static_cast<int*>(nullptr) - static_cast<int*>(nullptr));
```

```c++
int a[10];
ptrdiff_t d = &a[7] - &a[2];   // 5
ptrdiff_t e = &a[2] - &a[7];   // -5
```

---

对于short\int\long\long long来说，它们的位数在不同的平台上可能不同，那么在某些场景下为了保证位数的一致性，就有了**精确位宽**的设计：

- int8_t
- uint8_t
- uint32_t
- 等等

例如ip协议，要求某部分数据就必须是多少位。某些hash算法要求位数。等等。
