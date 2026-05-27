std::span

连续对象存储(不一定是数组）的观察者类似string_view。其不指向单个对象，而是指向一段连续的内存，包含两个核心成员：

- 指向序列开头的指针
- 序列的长度

```c++
template<
    class T,
    std::size_t Extent = std::dynamic_extent // 要么编译期能确定的大小，要么是std::dynamic_extent（运行期确定）
> class span;
```

可以有两种范围：

- 静态：编译期确定大小
- 动态：由指向第一个对象的指针和连续对象的大小组成。

### usage

**create**

```c++
#include <span>
#include <vector>
#include <array>

int c_array[] = {1, 2, 3, 4, 5};
std::vector<int> vec = {1, 2, 3, 4, 5};
std::array<int, 5> arr = {1, 2, 3, 4, 5};

// 1. 从 C 数组创建
std::span<int> s1(c_array); // 自动推导大小

// 2. 从 std::vector 创建
std::span<int> s2(vec);

// 3. 从 std::array 创建
std::span<int> s3(arr);

// 4. 从指针和长度创建 (与 C API 交互时常用)
std::span<int> s4(c_array, 3); // 指向 c_array 的前 3 个元素

// 5. 从迭代器创建
std::span<int> s5(vec.begin() + 1, vec.begin() + 4); // 指向 vec 的 [1, 2, 3]

```

**operator**

```c++
void inspect_span(std::span<const int> data) {
    if (data.empty()) return;

    // 访问大小
    std::cout << "Size: " << data.size() << std::endl;
    std::cout << "Size in bytes: " << data.size_bytes() << std::endl;

    // 访问元素
    std::cout << "First element: " << data.front() << std::endl;
    std::cout << "Last element: " << data.back() << std::endl;
    std::cout << "Element at index 1: " << data[1] << std::endl; // 不进行边界检查

    // 获取底层指针 (与 C API 交互)
    const int* p_data = data.data();

    // 迭代
    for(int val : data) { /* ... */ }
}
```

**slicing**

```c++
// 假设 network_packet 是一个包含头部和载荷的缓冲区
std::vector<std::byte> network_packet = get_packet();
std::span<const std::byte> packet_view(network_packet);

// 假设头部是 8 字节
constexpr size_t header_size = 8;
std::span<const std::byte> header = packet_view.subspan(0, header_size);
std::span<const std::byte> payload = packet_view.subspan(header_size); // 从第8字节到末尾

// process_header 和 process_payload 函数可以安全地处理各自的数据视图
process_header(header);
process_payload(payload);
```

### pros

**API接口不统一**

编写一个可以处理任何连续数据序列的函数，可以统一接口

```c++
void process_data(const std::vector<int>& data);
void process_data(const std::array<int, 10>& data);
void process_data(const int* data, std::size_t size); // C-style
```

```c++
#include <span>
#include <vector>
#include <array>

// With C++20 std::span
void process_data(std::span<const int> data) { // 一个函数，接受所有！
    for (int val : data) {
        // ... process val
    }
}

void test() {
    std::vector<int> v = {1, 2, 3};
    std::array<int, 4> a = {4, 5, 6, 7};
    int c_array[] = {8, 9, 10};

    process_data(v);
    process_data(a);
    process_data(c_array); // 隐式转换为 span
}
```

**C风格接口安全性差**

```c++
void process_data(const int* data, std::size_t size); // C-style
```

size可能越界，span同时封装了指针和大小。

**不必要的性能开销**

当需要传递数据的一部分给一个函数的时候，vector可能需要创建一个新的子副本。

`std::span`可以通过`subspan`零开销获得一个切片。



**Notes:**

span并不负责指向内存的生命周期，且只能用于操作内存地址**连续**的数据结构，例如c-style array `std::array`,`std::vector`不能用于`std::list`等。
