# std::fill

给范围内的所有元素赋上给定的值。复杂度是线性的。这个fill的本质就是赋值。

```c++
constexpr void fill( ForwardIt first, ForwardIt last, const T& value );
void fill( ExecutionPolicy&& policy, ForwardIt first, ForwardIt last, const T& value )
```

```c++
std::vector<int> v{0, 1, 2, 3, 4, 5, 6, 7, 8};
std::fill(v.begin(), v.end(), 8);
```

对于POD类型编译器通常会优化成`memset`或`memcpy`

```c++
struct Bigdata {
    int a;
    std::string b;
    std::vector<int> c;
};

std::vector<Bigdata> v;
Bigdata bigdata(1, "a long string that exceeds SSO", {1,2,3,4,5,6,7,8});

// 1 N 次默认构造（0初始化，可能会优化掉） + N 次拷贝赋值
v.resize(N); // 分配内存且构造对象（默认）
std::fill(v.begin(), v.end(), bigdata); // 深拷贝了。

// 2 会出现错误，bigdata内容已经被移动走了
v.reserve(N); 
for (size_t i = 0; i < N; i++) {
	v.emplace_back(std::move(bigdata)); // ❌
    v.emplace_back(bigdata); // 拷贝构造。
}

// 3  N 次直接构造
v.reserve(N);
for (size_t i = 0; i < N; i++) {
	 v.emplace_back(1, "a long string that exceeds SSO", std::vector<int>{1,2,3,4,5,6,7,8});
    // 没有move 没有拷贝构造，直接原地构造
}

// 4 fill 临时对象
v.resize(N);
std::fill(v.begin(), v.end(), Bigdata(1, "a long string that exceeds SSO", std::vector<int>{1,2,3,4,5,6,7,8}));
// 分析原本函数即可，其按const T&接收，会在参数这里实质化，产生临时对象。之后就是拷贝赋值。
```

- resize分配内存的同时也会构造对象。
- reserve只会分配内存。
