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
constexpr auto type_photo = ^^int;        
constexpr auto var_photo = ^^my_variable; 

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

不同info之间的比较规则：`std::meta::info` 是一个**标量类型**，支持相等比较（`==`、`!=`），但**不支持排序**（没有 `<`、`>`等）：

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





### Meta Function

获取元信息，主要还是为了基于info做一些操作，C++26在std::meta这个头文件中提供了一系列进行操作的元函数。