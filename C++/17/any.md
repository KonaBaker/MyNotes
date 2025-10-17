**type safe&unsafe**

编译器是否帮你检查类型错误。

- 使用强制类型转换绕过类型检查是不安全的。
- 使用void*指针，类型擦除，转换成具体类型如果和数据不一致就崩溃

> 但好像也不止于此，更广义的来说，是保证你不会混淆type的一种能力，比如std::any是在运行时抛出异常告诉你错误（不直接崩溃），并不是编译期。

**std::any**

before:

```
class UnsafeContainer {
    void* data;
    int type;  // 手动记录类型
}
```

调用get()时使用static_cast强制类型转换（没有编译器检查，当然通过手动记录可以人工检查）

after:

```c++
#include <any>
#include <iostream>
 
int main()
{
    std::cout << std::boolalpha;
 
    // any type
    std::any a = 1;
    std::cout << a.type().name() << ": " << std::any_cast<int>(a) << '\n';
    a = 3.14;
    std::cout << a.type().name() << ": " << std::any_cast<double>(a) << '\n';
    a = true;
    std::cout << a.type().name() << ": " << std::any_cast<bool>(a) << '\n';
 
    // bad cast
    try
    {
        a = 1;
        std::cout << std::any_cast<float>(a) << '\n';
    }
    catch (const std::bad_any_cast& e)
    {
        std::cout << e.what() << '\n';
    }
 
    // has value
    a = 2;
    if (a.has_value())
        std::cout << a.type().name() << ": " << std::any_cast<int>(a) << '\n';
 
    // reset
    a.reset();
    if (!a.has_value())
        std::cout << "no value\n";
 
    // pointer
    a = 3;
    int* i = std::any_cast<int>(&a);
    std::cout << *i << '\n';
    
    // reference
    int& ref = std::any_cast<int&>(a);
    std::cout<< ref << std::endl;
}
```



