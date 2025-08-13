## 新的语法

**```^^```反射运算符**

从它的操作数生成一个返回值（反射值）。

我们后续可以对这个元信息（包含名字、成员等等）进行操作

操作数支持：

- `::`：全局命名空间
- `namespace-name`：普通命名空间
- `type-id`：类型
- `id-expression`：绝大多数具有名字的东西，比如变量，静态成员变量，字段，函数，模板，枚举等

**```[: :]```Splicer运算符**

```
constexpr auto type = ^^int;        
constexpr auto var = ^^my_variable; 

[: type_photo :] x = 42;        // 相当于 int x = 42;
auto value = [: var_photo :];   // 相当于 auto value = my_variable;
```

对变量、函数、模板以及一个类/结构体的部分成员都是可以的。

```
struct Person {
    std::string name;
    int age;
    double salary;
};

template<typename T>
void print_first_member(const T& obj) {
    // 获取结构体的所有成员
    constexpr auto members = std::meta::nonstatic_data_members_of(^^T);
    
    // 获取第一个成员的反射
    constexpr auto first_member = members[0];
    
    // 拼接访问第一个成员
    std::cout << "第一个成员的值: " << obj.[: first_member :] << std::endl;
}

int main() {
    Person p{"张三", 25, 5000.0};
    print_first_member(p);  // 输出: 第一个成员的值: 张三
}
```

### std::meta:info

```
namespace std {
  namespace meta {
    using info = decltype(^^::);
  }
}
```

其实是一个编译器内部类型的一个别名。只能存在于编译期。

不同info之间的比较规则：`std::meta::info` ，支持相等比较（`==`、`!=`），但**不支持排序**（没有 `<`、`>`等）：

```
static_assert(^^int == ^^int);        // 相同类型，相等
static_assert(^^int != ^^double);     // 不同类型，不等

static_assert(^^int != ^^const int);  // const 修饰的是不同类型
static_assert(^^int != ^^int&);       // 引用类型也不同
static_assert(^^int != ^^int*);       // 指针类型也不同

using MyInt = int;

static_assert(^^int != ^^MyInt);              // 别名和原类型不同！
static_assert(^^int == dealias(^^MyInt));     // 但去别名后相同

namespace MyStd = ::std;

static_assert(^^::std != ^^MyStd);                    // 别名和原命名空间不同
static_assert(^^:: == parent_of(^^::std));           // 全局是std的父命名空间

int x;
int y;
struct S { 
    static int z; 
};

static_assert(^^x == ^^x);                           // 同一个变量
static_assert(^^x != ^^y);                           // 不同变量，即使类型相同
static_assert(^^x != ^^S::z);                        // 不同变量
static_assert(^^S::z == static_data_members_of(^^S)[0]); // 通过不同方式获得同一实体
```

对于**别名**

要求：

都是别名

别名相同的类型

有相同的名称

在相同的作用域

```
using Alias1 = int;
using Alias2 = int;  // 相同类型，但名称不同

consteval std::meta::info fn() {
    using Alias1 = int;  // 相同名称和类型，但作用域不同
    return ^^Alias1;
}

static_assert(^^Alias1 == ^^Alias1);  // 同一个别名
static_assert(^^Alias1 != ^^int);     // 别名和原类型
static_assert(^^Alias1 != ^^Alias2);  // 不同名称
static_assert(^^Alias1 != fn());	  // 不同作用域
```

通过is_consteval_only_type判断是不是只能存在于编译期的类型。

反射代表的是**实体**，不是**声明**。

```
int f(int = 1);
constexpr auto f_refl = ^^f;

int g() {
    int f(int = 2);           // 这个声明"毒化"了默认参数
    return [: f_refl :]();    // ❌ 编译错误！不能使用默认参数
}

int r = [: f_refl :]();       // ❌ 编译错误！默认参数被"毒化"了
```

**如果块作用域声明为函数的第N个参数引入了默认参数，那么通过拼接调用该函数时不能使用任何默认参数**。

### Meta Function

获取元信息，主要还是为了基于info做一些操作，C++26在std::meta这个头文件中提供了一系列进行操作的元函数。

**members**

访问成员

```
namespace std::meta {
  consteval auto members_of(info r) -> vector<info>;
  consteval auto bases_of(info type_class) -> vector<info>;

  consteval auto static_data_members_of(info type_class) -> vector<info>;
  consteval auto nonstatic_data_members_of(info type_class) -> vector<info>;

  consteval auto enumerators_of(info type_enum) -> vector<info>;
}
```

```
struct Point {
    int x;
    int y;
};

int main() {
    Point p = {1, 2};
    constexpr auto no_check = meta::access_context::unchecked();
    constexpr auto rx = meta::nonstatic_data_members_of(^^Point, no_check)[0];
    constexpr auto ry = meta::nonstatic_data_members_of(^^Point, no_check)[1];

    p.[:rx:] = 3;
    p.[:ry:] = 4;

    std::println("p: {}, {}", p.x, p.y);
}
```

`enumerators_of` 按照声明顺序返回指定枚举类型的枚举器常量。

**identifiers**

访问变量名、函数名、字段名。

```
namespace std::meta {
  consteval auto identifier_of(info) -> string_view;
  consteval auto u8identifier_of(info) -> u8string_view;

  consteval auto display_string_of(info) -> string_view;
  consteval auto u8display_string_of(info) -> u8string_view;

  consteval auto has_identifier(info) -> bool;

  consteval auto source_location_of(info r) -> source_location;
}
```

`identifier_of` 一般**只能用于**拥有简单名字的 entity，并且直接返回这个 named entity 的不带**限定符 (qualifier)** 的名字。而 `display_string_of` 则可能更倾向于返回带全称限定的名字，比如它的命名空间前缀，也可以用于处理 `vector<int>` 这样的模板特化。`source_location_of` 则进一步突破了 C++20 加的 `std::source_location::current()` 只能获取当前源码位置的限制

```
constexpr auto rx = meta::nonstatic_data_members_of(^^Point, no_check)[0];
constexpr auto ry = meta::nonstatic_data_members_of(^^Point, no_check)[1];

static_assert(meta::identifier_of(rx) == "x");
static_assert(meta::identifier_of(ry) == "y");
```

**typeof**

```
namespace std::meta {
  consteval auto type_of(info r) -> info;
  consteval auto parent_of(info r) -> info;
  consteval auto dealias(info r) -> info;
}
```

- 如果r是一个指定了类型实体的反射 type_of(r)究竟是它指定的类型的一个反射。

- 如果r已经是一个类型，那么type_of(r)，type_of(r)不是一个常量表达式。

parent_of 获取**直接**包围它的类、函数或者是命名空间。

dealias 底层实体、递归的，逐层玻璃所有的别名。

```
struct Point {
    int x;
    int y;
};

int main() {
    Point p = {1, 2};
    constexpr auto no_check = std::meta::access_context::unchecked();
    constexpr auto rx = std::meta::nonstatic_data_members_of(^^Point, no_check)[0];
    constexpr auto ry = std::meta::nonstatic_data_members_of(^^Point, no_check)[1];

    constexpr auto rx_type = std::meta::type_of(rx);
    static_assert(std::meta::display_string_of(rx_type) == "int");
    
    constexpr auto rx_class = std::meta::parent_of(rx);
    static_assert(std::meta::display_string_of(rx_class) == "Point");
}
```

```
using X = int;
using Y = X;
static_assert(dealias(^^int) == ^^int);
static_assert(dealias(^^X) == ^^int);
static_assert(dealias(^^Y) == ^^int);
```

**object_of constant_of**

```
namespace std::meta {
  consteval auto object_of(info r) -> info;
  consteval auto constant_of(info r) -> info;
}
```

object_of从**变量**处获取对象的反射，只能用于**静态存储期**的变量

constant_of获取枚举值或常量对象的值的反射（更多详细的可以看后面的reflect_constant)

```
static int x = 1;
int& y = x;
constexpr int i = 1;
constexpr int j = 1;

int main() {
    constexpr auto rx = ^^x;

    static_assert(^^x != ^^y);
    static_assert(std::meta::object_of(^^x) == std::meta::object_of(^^y));
    constexpr auto rx_obj = std::meta::object_of(^^x);
    static_assert(std::meta::object_of(^^x) == std::meta::object_of(rx_obj));

    static_assert(^^i != ^^j); //变量反射
    static_assert(std::meta::constant_of(^^i) == std::meta::constant_of(^^j)); //常量值反射
    static_assert(std::meta::object_of(^^i) != std::meta::object_of(^^j)); //对象反射
}
```



**template_of template_atguments_of** ****

```
namespace std::meta {
  consteval auto template_of(info r) -> info;
  consteval auto template_arguments_of(info r) -> vector<info>;
  
  template <reflection_range R = initializer_list<info>>
  consteval auto can_substitute(info templ, R&& args) -> bool;
  template <reflection_range R = initializer_list<info>>
  consteval auto substitute(info templ, R&& args) -> info;
}
```

假设 `r` 是一个**模板特化 (template specialization)**，`template_of` 返回它的模板，`template_arguments_of` 返回它的模板参数。`substitute` 则是根据给定的模板和参数，返回替换结果的模板特化的反射（不触发实例化）。通过这组函数，我们不再需要通过偏特化的方式来萃取模板特化的模板参数，轻而易举就可以拿到参数列表了。

```
std::vector<int> v = {1, 2, 3};
static_assert(template_of(type_of(^^v)) == ^^std::vector);
static_assert(template_arguments_of(type_of(^^v))[0] == ^^int);
```

```
int main() {

    std::vector<int> v = {1, 2, 3};
    std::array<int, 5> a = {1, 2, 3, 4, 5};
    static_assert(template_of(type_of(^^v)) == ^^std::vector);
    static_assert(template_arguments_of(type_of(^^v))[0] == ^^int);   

    static_assert(template_of(type_of(^^a)) == ^^std::array);
    constexpr auto args1 = template_arguments_of(type_of(^^a))[1];
    constexpr auto n = display_string_of(args1);
    static_assert(n == "5");
}
```

还可以通过它们编写一个 `is_specialization_of` 用来判断某个类型是不是某个模板的特化

```
consteval bool is_specialization_of(info templ, info type) {
    return templ == template_of(dealias(type));
}
```

**substitude** 模板替换

```
namespace std::meta {
  template <reflection_range R = initializer_list<info>>
  consteval auto can_substitute(info templ, R&& args) -> bool;
  template <reflection_range R = initializer_list<info>>
  consteval auto substitute(info templ, R&& args) -> info;
}
```



```
constexpr auto r = substitute(^^std::vector, std::vector{^^int});
using T = [:r:]; // Ok, T is std::vector<int>
template<typename T> struct S { typename T::X x; };

constexpr auto r = substitute(^^S, std::vector{^^int});  // Okay.
typename[:r:] si;  // Error: T::X is invalid for T = int.
```

**define aggregate**

```
consteval auto data_member_spec(info type,
                                  data_member_options options) -> info;
                                  
template <reflection_range R = initializer_list<info>>
consteval auto define_aggregate(info type_class, R&&) -> info;
```

`define_aggregate` 获取一个不完整类/结构体/联合体类型的反射，以及一系列数据成员描述的反射，并按照给定的顺序，使用这些数据成员来补全给定的类类型。返回的是给定的反射。目前，仅支持数据成员的反射（通过 `data_member_spec` ），但该 API 接受一个 `info` 的范围，这是为了预见在不久的将来进行扩展。

可以用 `define_aggregate` 给一个不完整的类型生成成员定义，这对于实现 `tuple` 或者 `variant` 这样的可变成员数量的类型很有用，例如

```cpp
union U;
consteval {
    define_aggregate(^^U, {
        data_member_spec(^^int),
        data_member_spec(^^char),
        data_member_spec(^^double),
    });
}
union tuple_storage;
consteval {
    vector<data_member_spec> members;
    for (int i = 0; i < type_count; ++i) {
        members.push_back(data_member_spec(types[i]));
    }
    define_aggregate(^^tuple_storage, members);
}
```

相当于

```cpp
union U {
    int _0;
    char _1;
    double _2;
};
```

这样就可以方便的实现一个 `variant` 类型而无需任何模板递归实例化了。

传统实现：编译时开销大：

```

tuple_impl<A, B, C, D, E>
tuple_impl<B, C, D, E>      // 递归层1
tuple_impl<C, D, E>         // 递归层2  
tuple_impl<D, E>            // 递归层3
tuple_impl<E>               // 递归层4
tuple_impl<>                // 递归层5（空）

get_helper<0, A, B, C, D, E>
get_helper<1, A, B, C, D, E> → get_helper<0, B, C, D, E>
get_helper<2, A, B, C, D, E> → get_helper<1, B, C, D, E> → get_helper<0, C, D, E>

```

```

template<typename T> struct S;
constexpr auto s_int_refl = define_aggregate(^^S<int>, {
  data_member_spec(^^int, {.name="i", .alignment=64}),
  data_member_spec(^^int, {.name=u8"こんにち"}),
});

// S<int> is now defined to the equivalent of
// template<> struct S<int> {
//   alignas(64) int i;
//               int こんにち;
// };
```



### Annotations

```
namespace std::meta {
    consteval bool is_annotation(info);
    consteval vector<info> annotations_of(info item);
    consteval vector<info> annotations_of_with_type(info item, info type);
}
```



在别的语言中，可以通过 `attribute` 或 `annotation` 来附加元数据，然后在代码中读取这些元数据。C++ 也加入了 `attribute`，语法为 `[[...]]`，比如 `[[nodiscard]]`。但它主要的设计意图是为编译器提供额外的信息，而不是让用户附加额外的元数据并获取。

为了解决这个问题，P3394R4(Annotations for Reflection) 提案为 C++26 引入了可反射的**注解 (annotation)**。它的语法非常直观，使用 `[[=...]]` 为某个 entity 添加注解，**任意的可以作为模板参数的常量表达式**都可以作为注解的内容。

基础类型的常量 自定义字面量类型字符串字面量

```
// 性能标记
[[=1]] void low_priority_task();
[[=10]] void high_priority_task();

// 版本信息
[[="v1.2.3"]] struct DatabaseAPI {};
[[="experimental"]] void new_feature();

// 配置参数
[[=Point{640, 480}]] void render_at_resolution();
[[=Color::RED]] void error_handler();

// 复杂元数据
struct Config {
    int threads;
    bool debug_mode;
    constexpr Config(int t, bool d) : threads(t), debug_mode(d) {}
};

[[=Config{4, true}]] void multi_threaded_debug();
```

`is_annotation` 判断一个反射是不是注解的反射。`annotations_of` 获取给定 entity 上的所有注解的反射，`annotations_of_with_type` 则是获取给定 entity 上所有类型为 `type` 的注解的反射。获取到注解后再使用前面提到的 `extract` 解开值然后使用就行了。

// 传统attribute：只能是预定义的标识符

```
struct Info {
    int a;
    int b;
};

[[=Info(1, 2)]] int x = 1;
constexpr auto rs = annotations_of(^^x)[0];
constexpr auto info = std::meta::extract<Info>(rs);
static_assert(info.a == 1 && info.b == 2);
```





## example

```
#include <meta>
#include <print>
#include <string>
#include <vector>

namespace meta = std::meta;

namespace print_utility {

struct skip_t {};

constexpr inline static skip_t skip;

struct rename_t {
    const char* name;
};

consteval rename_t rename(std::string_view name) {
    return rename_t(std::define_static_string(name));
}

}  // namespace print_utility

/// annotations_of => annotations_of_with_type
consteval std::optional<std::meta::info> get_annotation(std::meta::info entity,
                                                        std::meta::info type) {
    auto annotations = meta::annotations_of(entity, type);
    if (annotations.empty()) {
        return {};
    } else if (annotations.size() == 1) {
        return annotations.front();
    } else {
        throw "too many annotations!";
    }
}

consteval auto fields_of(std::meta::info type) {
    return std::define_static_array(
        meta::nonstatic_data_members_of(type, meta::access_context::unchecked()));
}

template <typename T>
auto to_string(const T& value) -> std::string {
    constexpr auto type = meta::remove_cvref(^^T);
    if constexpr (!meta::is_class_type(type)) {
        return std::format("{}", value);
    } else if constexpr (meta::is_same_type(type, ^^std::string)) {
        return value;
    } else {
        std::string result;

        result += meta::identifier_of(type);
        result += " { ";

        bool first = true;

        template for (constexpr auto member : fields_of(type)) {
            if constexpr (get_annotation(member, ^^print_utility::skip_t)){
                continue;
            }

            if (!first) {
                result += ", ";
            }
            first = false;

            std::string_view field_name = meta::identifier_of(member);
            constexpr auto rename = get_annotation(member, ^^print_utility::rename_t);
            if constexpr (rename) {
                constexpr auto annotation = *rename;
                field_name = meta::extract<print_utility::rename_t>(annotation).name;
            }

            result += std::format("{}: {}", field_name, to_string(value.[:member:]));
        }

        result += " }";
        return result;
    }
}

struct User {
    int id;
    std::string username;

    [[= print_utility::skip]] 
    std::string password_hash;
};

struct Order {
    int order_id;

    [[= print_utility::rename("buyer")]] 
    User user_info;
};

int main() {
    User u = {101, "Alice", "abcdefg"};
    Order o = {20240621, u};

    std::println("{}", to_string(u));
    std::println("{}", to_string(o));
}
// output
// User { id: 101, username: Alice }
// Order { order_id: 20240621, buyer: User { id: 101, username: Alice } }

```

```cpp
template for (constexpr auto e : meta::nonstatic_data_members_of(info, no_check)) {
```

C++20 允许了编译期的动态内存分配，于是你可以在 `constexpr/consteval` 函数中使用 `vector` 来处理中间状态了。但限制是编译期分配的内存必须在同一段编译期求值上下文中释放，如果在**一次编译期求值**中，有未释放的内存，则会导致编译错误。

template for 的初始化表达式都视为**一次单独的常量求值**。

```
namespace std {
    template <ranges::input_range R>
    consteval const ranges::range_value_t<R>* define_static_string(R&& r);

    template <ranges::input_range R>
    consteval span<const ranges::range_value_t<R>> define_static_array(R&& r);//ranges::range_value_t<R>类型萃取。

    template <class T>
    consteval const remove_cvref_t<T>* define_static_object(T&& r);
}
```

它们可以将编译期分配的内存**提升**到**静态储存期**，也就是说和全局变量的储存期相同，并返回该静态储存期的指针或者引用，从而解决这个问题，所以上面的代码只需要额外在获取 `members` 的时候使用 `std::define_static_array` 把 `vector` 转成 `span` 就行了
