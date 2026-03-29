# C++ Ranges：View 与 Projection 精讲

---

## 一、Projection（投影）

### 1.1 是什么

Projection 是 C++20 ranges 算法中额外接受的一个 **callable 参数**，它在元素被传给谓词（pred）或比较器（comp）之前，先对元素做一次变换。

可以把它理解为一层"镜头"——算法看到的不是元素本身，而是元素经过这层镜头后的"像"。

所有 ranges 算法的 projection 默认值都是 `std::identity{}`，即"不变换，原样传递"。

### 1.2 基本语法

```cpp
// 签名（以 ranges::sort 为例）
constexpr auto sort(R&& r, Comp comp = {}, Proj proj = {});
//                          ↑ 默认 less     ↑ 默认 identity
```

`proj` 可以是：

| 传入形式 | 示例 | 效果 |
|---------|------|------|
| 成员指针 | `&User::age` | 提取成员，等价于 `elem.age` |
| 成员函数指针 | `&std::string::size` | 调用成员函数 |
| lambda | `[](const User& u){ return u.age; }` | 自定义变换 |
| 函数对象 | `std::negate<>{}` | 取反等 |

它们都通过 `std::invoke` 统一调用，这就是为什么成员指针也能当 projection 用。

### 1.3 例子：用 projection 代替自定义比较器

```cpp
struct Student {
    std::string name;
    int score;
};

std::vector<Student> students = {
    {"Alice", 88}, {"Bob", 95}, {"Carol", 72}
};

// ❌ 传统写法：需要写完整的比较器
std::sort(students.begin(), students.end(),
    [](const Student& a, const Student& b) {
        return a.score < b.score;
    });

// ✅ Ranges + projection：只说"按 score 看"
std::ranges::sort(students, {}, &Student::score);
// {} 代表默认比较器 ranges::less{}
```

两者效果相同：按分数升序排。但 projection 写法把"看哪个字段"和"怎么比"彻底分离了。

### 1.4 例子：projection + 谓词配合

```cpp
std::vector<Student> students = { /* ... */ };

// 找第一个不及格的（score < 60）
auto it = std::ranges::find_if(students,
    [](int s) { return s < 60; },   // pred：只关心 int
    &Student::score                  // proj：把 Student 投影为 int
);
```

注意 pred 的参数类型是 `int` 而不是 `Student&`——它接收的是 projection 的输出。

### 1.5 调用链路的拷贝分析

以 `ranges::find_if(range, pred, proj)` 为例，cppreference 说它对每个迭代器 `i` 求值：

```
std::invoke(pred, std::invoke(proj, *i))
```

分三步看：

```
*i                         → 对 vector<T>，返回 T&（引用，零拷贝）
std::invoke(proj, *i)      → 取决于 proj 的返回类型
std::invoke(pred, 上一步)   → 取决于 pred 的参数类型
```

**关键：projection 的返回类型决定了给 pred 的是引用还是值。**

```cpp
// 情况 A：成员指针做 projection → 返回引用
std::ranges::find_if(students,
    [](const std::string& name) { /*...*/ }, // 绑定到原始成员的引用
    &Student::name);                          // std::invoke 返回 string&

// 情况 B：lambda 返回值 → 产生拷贝
std::ranges::find_if(students,
    [](const std::string& s) { /*...*/ },     // 绑定到临时对象
    [](const Student& s) { return s.name; }); // 返回 string（值！）

// 情况 C：lambda 显式返回引用 → 无拷贝
std::ranges::find_if(students,
    [](const std::string& s) { /*...*/ },
    [](const Student& s) -> const std::string& { return s.name; }); // 引用
```

**易错点：** 情况 B 中，即使 pred 写了 `const std::string&`，它绑定的也是 projection
产生的临时对象，**不是**容器中的原始成员。如果你在 pred 里保存这个引用，它会悬空。

---

## 二、View（视图）

### 2.1 是什么

View 是一个**轻量的、非拥有的、惰性求值的** range 包装器。

三个关键词拆开理解：

- **非拥有**：view 不持有数据，它只是"看"底层数据的一种方式（类似数据库的视图）
- **轻量**：O(1) 拷贝/移动，本质上只存几个迭代器或指针
- **惰性**：在你真正遍历（for 循环、解引用）之前，不做任何计算

### 2.2 为什么需要 View

假设你想从 100 万个整数中，取出前 5 个偶数的平方。

```cpp
std::vector<int> vec(1'000'000);
std::iota(vec.begin(), vec.end(), 1);

// ❌ 传统写法：必须创建中间容器，处理全部元素
std::vector<int> evens;
std::copy_if(vec.begin(), vec.end(), std::back_inserter(evens),
    [](int x) { return x % 2 == 0; });       // 遍历100万，拷贝50万

std::vector<int> squares;
std::transform(evens.begin(), evens.end(), std::back_inserter(squares),
    [](int x) { return x * x; });             // 再遍历50万

squares.resize(5);                            // 扔掉49万9995个

// ✅ View 写法：零中间容器，只算 5 个
auto result = vec
    | std::views::filter([](int x) { return x % 2 == 0; })
    | std::views::transform([](int x) { return x * x; })
    | std::views::take(5);

// 此时什么都没算。下面遍历时才按需计算：
for (int x : result) {
    std::cout << x << '\n'; // 输出 4, 16, 36, 64, 100
}
// 总共只检查了 10 个元素（前 5 个偶数：2,4,6,8,10），而非 100 万
```

### 2.3 管道语法 `|`

`|` 是 view 的组合运算符，它把多个 view adaptor 串成管道：

```cpp
auto v = data | adaptor_A | adaptor_B | adaptor_C;
//              ↑ 先经过A    ↑ 再经过B    ↑ 再经过C
```

等价于嵌套调用 `adaptor_C(adaptor_B(adaptor_A(data)))`，但可读性好得多。

### 2.4 常用 View 速查

以下是最常用的几个，每个配一个最小例子。

#### `views::filter` — 过滤

```cpp
std::vector nums = {1, 2, 3, 4, 5, 6};

for (int x : nums | std::views::filter([](int x) { return x % 2 == 0; })) {
    // 依次得到 2, 4, 6
}
```

#### `views::transform` — 变换

```cpp
std::vector nums = {1, 2, 3};

for (int x : nums | std::views::transform([](int x) { return x * 10; })) {
    // 依次得到 10, 20, 30
}
```

#### `views::take` / `views::drop` — 取前 N 个 / 跳过前 N 个

```cpp
std::vector nums = {10, 20, 30, 40, 50};

// take(3) → 10, 20, 30
// drop(2) → 30, 40, 50
// drop(2) | take(2) → 30, 40
```

#### `views::enumerate` (C++23) — 带索引遍历

```cpp
std::vector<std::string> names = {"Alice", "Bob", "Carol"};

for (auto [i, name] : names | std::views::enumerate) {
    std::cout << i << ": " << name << '\n';
}
// 0: Alice
// 1: Bob
// 2: Carol
```

这个在你之前的 Vulkan queue family 代码中特别有用——再也不用手动算索引了。

#### `views::zip` (C++23) — 并行遍历多个容器

```cpp
std::vector a = {1, 2, 3};
std::vector b = {"x", "y", "z"};

for (auto [num, str] : std::views::zip(a, b)) {
    std::cout << num << str << '\n'; // 1x, 2y, 3z
}
```

#### `views::iota` — 生成序列

```cpp
// 生成 [0, 5)
for (int i : std::views::iota(0, 5)) {
    // 0, 1, 2, 3, 4
}

// 无穷序列 + take
for (int i : std::views::iota(0) | std::views::take(3)) {
    // 0, 1, 2
}
```

#### `views::split` / `views::join` — 拆分与拼接

```cpp
std::string csv = "alice,bob,carol";

for (auto word : csv | std::views::split(',')) {
    // 依次得到子 range: "alice", "bob", "carol"
    std::cout << std::string_view(word) << '\n';
}
```

#### `views::keys` / `views::values` — 提取 pair/tuple 的第一/二元素

```cpp
std::map<std::string, int> scores = {{"Alice", 90}, {"Bob", 85}};

for (auto& name : scores | std::views::keys) {
    // "Alice", "Bob"
}

for (int s : scores | std::views::values) {
    // 90, 85
}
```

#### `views::reverse` — 反转

```cpp
std::vector nums = {1, 2, 3};

for (int x : nums | std::views::reverse) {
    // 3, 2, 1
}
```

### 2.5 View 的拷贝/引用语义深入分析

这是最容易出错的地方。

#### 规则一：View 引用底层数据，不拷贝元素

```cpp
std::vector<int> vec = {3, 1, 2};
auto v = vec | std::views::transform([](int x) { return x * 2; });

vec[0] = 99; // 修改原始数据

// v 没有缓存任何东西，遍历 v 时会看到修改后的值：
// 198, 2, 4
```

#### 规则二：filter/transform 的回调里拿到的是引用还是值？

**`views::filter`** 的回调接收的是底层元素的引用，且 filter 产出的元素也是引用：

```cpp
std::vector<int> vec = {1, 2, 3, 4};

for (int& x : vec | std::views::filter([](int x) { return x % 2 == 0; })) {
    x *= 10; // ✅ 可以修改原始容器！
}
// vec 现在是 {1, 20, 3, 40}
```

**`views::transform`** 的输出是回调的返回值，所以：

```cpp
std::vector<Student> students = {{"Alice", 90}, {"Bob", 85}};

// 返回值类型 → 产出拷贝，不能修改原始数据
auto names_copy = students
    | std::views::transform([](const Student& s) { return s.name; });
// 每次解引用都执行 lambda，得到 string 的拷贝

// 返回引用类型 → 产出引用，可以修改
auto names_ref = students
    | std::views::transform([](Student& s) -> std::string& { return s.name; });
// 每次解引用得到的是原始 name 的引用
```

对于lambda参数的传入值同理，是值就拷贝，是引用就直接传递。

#### 规则三：不要让 View 的生命周期超过底层数据

```cpp
auto make_view() {
    std::vector<int> local = {1, 2, 3};
    return local | std::views::filter([](int x) { return x > 1; });
    // ❌ 返回后 local 被销毁，view 持有悬空引用！
}
```

`std::ranges::dangling` 机制可以在某些场景下帮你在编译期阻止这个错误（当你把
临时 range 传给返回迭代器的算法时），但 view 管道本身不受此保护。

#### 规则四：View 自身是轻量的，拷贝 View ≠ 拷贝数据

```cpp
std::vector<int> vec = {1, 2, 3, 4, 5};
auto v1 = vec | std::views::take(3);
auto v2 = v1; // O(1)，只拷贝了内部的迭代器/指针，不拷贝元素
```

#### 规则五：惰性意味着每次遍历都重新计算

```cpp
int call_count = 0;

std::vector<int> vec = {1, 2, 3};
auto v = vec | std::views::transform([&](int x) {
    ++call_count;
    return x * 2;
});

// 第一次遍历
for (int x : v) { /* ... */ }
// call_count == 3

// 第二次遍历
for (int x : v) { /* ... */ }
// call_count == 6（又算了一遍！）
```

如果变换开销大，且需要多次遍历，应该物化（materialize）到容器中：

```cpp
// C++23: ranges::to
auto concrete = v | std::ranges::to<std::vector>();

// C++20 手动物化
std::vector<int> concrete(std::ranges::begin(v), std::ranges::end(v));
```

---

## 三、View 与 Projection 的区别和选择

两者看起来类似（都是"变换元素"），但作用层面不同：

| | Projection | View (transform) |
|---|---|---|
| 作用于 | 单个算法内部 | range 本身，可脱离算法独立存在 |
| 可否组合 | 不能链式组合 | 可以 `\|` 管道组合 |
| 是否改变 range | 不改变，只影响算法看到的值 | 产生新的 view range |
| 适用场景 | 算法中"按某字段比较/查找" | 构建数据处理管道 |

一个实际对比：

```cpp
struct Task { std::string name; int priority; bool done; };
std::vector<Task> tasks = { /* ... */ };

// 场景：找优先级最高的未完成任务
// 方案 A：view + 算法
auto undone = tasks | std::views::filter([](const Task& t) { return !t.done; });
auto it = std::ranges::max_element(undone, {}, &Task::priority);
//                                              ↑ projection

// 方案 B：纯算法（但需要更复杂的比较器）
auto it2 = std::ranges::max_element(tasks, [](const Task& a, const Task& b) {
    if (a.done != b.done) return a.done; // 未完成的 > 已完成的
    return a.priority < b.priority;
});
```

方案 A 更清晰：filter 负责"哪些参与"，projection 负责"按什么比"。

---

## 四、易错点总结

### 4.1 悬空引用

```cpp
// ❌ 临时 vector 被销毁
auto v = std::vector{1,2,3} | std::views::take(2);
for (int x : v) { /* 未定义行为 */ }

// ✅ 先绑定到变量
std::vector vec = {1, 2, 3};
auto v = vec | std::views::take(2);
```

### 4.2 transform 的回调被重复调用

```cpp
auto v = vec | std::views::transform([](int x) {
    std::cout << "called\n"; // 如果你遍历两次，这里打印两倍的次数
    return expensive_compute(x);
});

// 如果你写 v[0] == v[0]，transform 的 lambda 被调用了两次
```

### 4.3 filter 会使 view 失去 random access

```cpp
std::vector<int> vec = {1, 2, 3, 4, 5};

auto v = vec | std::views::filter([](int x) { return x > 2; });
// v[0]; // ❌ 编译错误！filter_view 不是 random_access_range
//        // 因为不跑一遍 filter，无法知道第 N 个元素在哪

// 只能用 forward 方式遍历
for (int x : v) { /* OK */ }
```

### 4.4 Projection 中成员指针 vs lambda 的引用语义差异

```cpp
struct S { std::string data; };
std::vector<S> vec = {{"hello"}, {"world"}};

// 成员指针：std::invoke 返回 string&（引用）
std::ranges::sort(vec, {}, &S::data); // ✅ 零拷贝

// lambda 不写返回类型：返回 string（值），每次比较都拷贝
std::ranges::sort(vec, {}, [](const S& s) { return s.data; }); // 有拷贝开销

// lambda 显式返回引用：等同于成员指针
std::ranges::sort(vec, {}, [](const S& s) -> const std::string& { return s.data; });
```

### 4.5 `views::split` 产出的子 range 不是 string

```cpp
std::string csv = "a,b,c";

for (auto part : csv | std::views::split(',')) {
    // part 的类型不是 string，也不是 string_view
    // 它是一个 subrange，需要手动转换
    std::string s(part.begin(), part.end());       // OK
    std::string_view sv(part);                      // C++23 OK, C++20 不行
}
```

### 4.6 owning_view 与右值的微妙之处

C++20 中管道运算符对右值 range 有特殊处理——`std::views::all` 会将右值容器
包进 `owning_view`，使 view **拥有**该容器：

```cpp
// 这个是安全的（C++20 起）：
auto v = std::vector{1,2,3}
       | std::views::transform([](int x){ return x * 2; });
// owning_view 内部持有了 vector 的所有权

// 但注意：这只对通过 views::all 隐式包装的情况有效
// 直接手写 ref_view 包装临时对象仍然危险
```

不过依赖这个行为会让代码意图不清晰，建议还是显式绑定到变量。
