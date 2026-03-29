**std::invoke**

### Parameters

| f    | -    | [*Callable*](https://en.cppreference.com/w/cpp/named_req/Callable.html) object to be invoked |
| ---- | ---- | ------------------------------------------------------------ |
| args | -    | arguments to pass to f                                       |

###  Return value

1) The value returned by f.
2) The value returned by f, implicitly converted to `R`, if `R` is not (possibly [cv-qualified](https://en.cppreference.com/w/cpp/language/cv.html)) void. None otherwise.

```C++
#include <functional>
#include <iostream>
#include <type_traits>
 
struct Foo
{
    Foo(int num) : num_(num) {}
    void print_add(int i) const { std::cout << num_ + i << '\n'; }
    int num_;
};
 
void print_num(int i)
{
    std::cout << i << '\n';
}
 
struct PrintNum
{
    void operator()(int i) const
    {
        std::cout << i << '\n';
    }
};
 
int main()
{
    std::cout << "invoke a free function: ";
    std::invoke(print_num, -9);
 
    std::cout << "invoke a lambda: ";
    std::invoke([](){ print_num(42); });
 
    std::cout << "invoke a member function: ";
    const Foo foo(314159);
    std::invoke(&Foo::print_add, foo, 1);
 
    std::cout << "invoke (i.e., access) a data member num_: "
              << std::invoke(&Foo::num_, foo) << '\n';
 
    std::cout << "invoke a function object: ";
    std::invoke(PrintNum(), 18);
 
#if defined(__cpp_lib_invoke_r)
    auto add = [](int x, int y){ return x + y; };
    std::cout << "invoke a lambda converting result to float: ";
    auto ret = std::invoke_r<float>(add, 11, 22);
    static_assert(std::is_same<decltype(ret), float>());
    std::cout << std::fixed << ret << "\ninvoke print_num: ";
    std::invoke_r<void>(print_num, 44);
#endif
}
```

