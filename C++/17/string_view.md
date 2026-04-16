https://zhxilin.github.io/post/tech_stack/1_programming_language/modern_cpp/cpp17/string_view/

**std::string_view**

```C++
string_view 对象本身（栈上，16字节）
┌─────────────────┬──────────┐
│  const char* ptr │ size_t n │
└────────┬────────┴──────────┘
         │ 只读引用，不拥有数据
         ▼
[ 某处内存中的字符数组，string_view 不负责其生命周期 ]
```

获取一个字符串（既可以是std::string也可以是c风格字符串）的视图，并不真正创建或者拷贝字符串，不own任何字符串内存。性能比std::string要高很多。

本质是std::basic_string_view模板的一种实现。

```c++
constexpr basic_string_view() noexcept;                        // (1) 默认
constexpr basic_string_view(const basic_string_view&) noexcept = default; // (2) 拷贝
constexpr basic_string_view(const CharT* str, size_type count); // (3) 指针+长度。不会被\0截断
constexpr basic_string_view(const CharT* str);                  // (4) 以 \0 结尾的 C 字符串。会被\0截断。
constexpr basic_string_view(nullptr_t) = delete;                // (5) 禁止 nullptr（C++23）
```



- 通过字符串字面量构造

```c++
std::string_view sv = "../models/viking_room.obj";
// 或
constexpr std::string_view sv = "../models/viking_room.obj";
```

```c++
只读数据段（程序运行期间永久存在）
┌──────────────────────────────────┐
│ "../models/viking_room.obj\0"    │ ← 字面量
└──────────────┬───────────────────┘
               │
sv.ptr ────────┘   sv.n = 25
```

- 从std::string构造

```C++
std::string s = "Hello, world!";
std::string_view sv(s);
```

```c++
堆内存（std::string 管理）
┌───────────────────┐
│ "Hello, world!\0" │ ← s 拥有并管理这块内存
└──────────┬────────┘
           │
sv.ptr ────┘   sv.n = 13
```

要注意sv和s的生命周期问题，小心出现悬空。

std::string构造是通过类型转换构造了一个string_view的临时对象，再调用string_view的拷贝构造函数。

- 从const char*构造/长度

```c++
const char* cstr = "Foo";
std::string_view sv(cstr);
const char* data = "One\0Two";
std::string_view sv(data, 7); // 包含内嵌的 \0！不会被\0截断。
```

**注意事项**

- data()返回的是起始位置的字符指针，但此时要注意string_view被初始化的时候是否有\0结束符。
- 注意string_view所“观察”对象的声明周期，例如一些局部变量会在函数结束内存释放，string_view出现悬垂。
- string_view的相关函数被声明为constexpr。提供了其在编译期处理一些字面量字符串的能力，但不是表明其必须在编译期处理(不是consteval)。对于一些```std::string str = "1"```这种运行时数据，也是可以处理的。对于函数本身，只是有条件的减小了运行时开销。