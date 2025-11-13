# contracts

契约是对于组件一种的正式的接口规范，它是一组条件，表达了关于组件如何在正确的程序中与其他组件互操作的期望。

**契约违规**发生在契约的某个条件在程序代码执行时不成立的情况下。

契约是一种断言机制，在运行时检测错误，和现有的assert宏类似，但是不是宏。

老的-> [assert](../11/assert.md)

新的-> 

### contract_assert替代assert

contract_assert是一个关键字。其工作原理相同。

同assert一样，检查失败，打印信息并且终止。



assert通过定义NDEBUG宏来关闭检查。

contract_assert通过选择“ignore”评估语义来关闭契约断言的检查。

```-fcontract-semantic=ignore```

 ### 四种评估语义

当`assert`宏被检查且检查失败时，打印消息并终止程序是唯一的选择，**缺乏灵活性**

- ignore 不检查断言

- enforce 检查失败，打印信息(调用handler)并终止程序。
- observe 检查失败，打印信息(调用handler)并继续执行。
- quick-enforce 检查失败，立即终止程序，不打印信息或执行任何其他操作。

```
double sqrt(double x)
    pre(x >= 0);

// 编译配置：-fcontracts=ignore
double sqrt(double x) {
    // pre(x >= 0) 被完全移除
}

sqrt(-1);
```



#### 自定义行为

handle_contract_violation用于更改“打印消息”这一行为，改成其他。

这是一个回调函数，其接收const contract_violation&参数，里面包含：

- 源码位置
- 评估语义
- 是否抛出异常

等信息。

**class** ```std::contracts::contract_violation```

>this object cannot be constructed, copied, moved, or mutated by the user. 



``const char* comment() const noexcept``

返回条件：

- “amount > 0"
- "amount>0"
- ""

提案中只给了建议形式，具体实现由编译器决定。

```contracts::detection_mode detection_mode() const noexcept```

```
enum class detection_mode : unspecified {
    predicate_false = 1,
    evaluation_exception = 2
};
```

- predicate_false 契约条件被成功求值了，但是结果是false

- evaluation_exception 在表达式求值的过程中发生了异常

```
void withdraw(Account& account, double amount)
    pre(amount > 0)                 
    pre(account.get_balance() >= amount)    
{
    account.balance -= amount;
}


withdraw(my_account, -100); // predicate_false
withdraw(locked_account, 1000); // evaluation_exception
```

```
class Account {
    double balance;
    bool locked;
    
public:
    double get_balance() const {
        if (locked) {
            throw std::runtime_error("Account is locked!");
        }
        return balance;
    }
};
```



```exception_ptr evaluation_exception() const noexcept```

如果是因为异常回调，则会返回一个指向异常的指针。否则返回一个空的exception_ptr

```
void my_handler(const std::contracts::contract_violation& v) {
if (v.detection_mode() == std::contracts::detection_mode::predicate_false) {
	std::cerr << v.comment() << std::endl;
}
else {
	auto ex_ptr = v.evaluation_exception();
    if (ex_ptr) {
        try {
            std::rethrow_exception(ex_ptr);
        } 
        catch (const std::exception& e) {
            std::cerr << e.what() << std::endl;
        }
    }
}
```



```bool is_terminating() const noexcept```

如果当前的评估语义是一个 terminating semantic 返回true,否则返回false。

什么是终止语义？

- std::abort()
- std::terminate()
- 其他终止执行行为

的语义。

不可以通过



```assertion_kind kind() const noexcept```

返回enum class std::contracts::assertion_kind::pre/post/assert

```
enum class assertion_kind : unspecified {
    pre = 1,
    post = 2,
    assert = 3
};
```

```
switch(v.kind()) {
    case std::contracts::assertion_kind::pre:
        std::cerr << "前置条件违规\n"; break;
    case std::contracts::assertion_kind::post:
        std::cerr << "后置条件违规\n"; break;
    case std::contracts::assertion_kind::assert:
        std::cerr << "断言失败\n"; break;
}
```



```source_location location() const noexcept```

返回std::source_location(c++20引入)



```evaluation_semantic semantic() const noexcept```

返回当前在使用哪种语义编译选项：

```
enum class evaluation_semantic : unspecified {
    ignore = 1,
    observe = 2,
    enforce = 3,
    quick_enforce = 4
};
```

编译器还可以自定义实现更多的枚举值

最后将该定义链接到程序中。（直接定义同名函数链接器zi dong

---

### precondition

函数调用时期望成立的条件。

使用传统assert宏以及contract_assert的主要缺陷：

```
double sqrt(double x); //调用方视角。
```

```
double sqrt(double x) {
	assert(x >= 0);  // 约束隐藏
	return std::sqrt(x);
}
```

前置声明可见。编译器或者其他一些工具可以进行静态分析或者警告。

可以同时声明多个前置条件（每个条件是独立的）
```
void resize(int* arr, size_t old_size, size_t new_size)
    pre(arr != nullptr)
    pre(old_size > 0)
    pre(new_size > 0);
```

但是不可以在一个pre中写多个条件：
```
void bad_example(int x, int y)
    pre(x > 0, y > 0);  // 编译错误！
void process_age(int age)
    pre(age >= 0 && age <= 150);
```



### postcondition

函数完成后保证这些条件。

**result**

```
// 错误：void 函数不能使用 result
void print(const char* msg)
    post(result != nullptr);  // 编译错误！void 没有返回值
```

```
// 正确：检查返回值
int* allocate(size_t size)
    pre(size > 0)
    post(result != nullptr);  // result 绑定到返回值
```

**访问参数的旧值**

非引用参数必须声明为 `const`。

> 由于`pre`和`post`被置于函数声明而非定义内部，它们可被写入共享头文件。



### 关于pre和post的一些注意事项：

- 避免副作用

```
// 错误
int counter = 0;
void process(int x)
    pre(++counter < 100)  // 错误！修改了 counter
    pre(x > 0);
    
// 错误
void log(const char* msg)
    pre(std::cout << msg, true);  // 错误！cout 有副作用
 
// 正确
void process(int x)
    pre(counter < 100)  // OK：只读取
    pre(x > 0);
```

- 构造函数和析构函数中

```
class Buffer {
    char* data;
    size_t size;
public:
    // 正确
    Buffer(size_t n)
        pre(n > 0)
        : data(new char[n]), size(n) {}
    
    // 错误
    Buffer(size_t n)
        pre(size == 0)  // 编译错误！成员还未初始化
        : data(new char[n]), size(n) {}
    
    // 正确
    Buffer(size_t n)
        pre(n > 0)
        post(size == n)
        post(data != nullptr)
        : data(new char[n]), size(n) {}
    
    ~Buffer()
        post(data == nullptr);  // 编译错误！成员已销毁
};
```

构造函数 `pre` 不能访问成员（还未初始化）

析构函数 `post` 不能访问成员（已经销毁）



|                          | 检查时机                          | 优点                                                         | 缺点                                                 |
| ------------------------ | :-------------------------------- | ------------------------------------------------------------ | ---------------------------------------------------- |
| assert                   | 运行时检查                        | 运行时检查任意的表达式                                       | 1.只能通过NDBUG控制开关<br />2.失败只能abort()<br /> |
| static_assert            | 编译时检查                        | 零运行时开销                                                 | 不能检查运行时值                                     |
| contract_assert/pre/post | 运行时检查/特殊情况下会编译时检查 | 1.多种行为的控制语义<br />2.可以自定义handler<br />3.更加灵活和清晰 | 1增加函数的复杂度<br />2.不可以在虚函数中使用        |

```
constexpr int safe_divide(int a, int b)
    pre(b != 0)  // 在constexpr中会被检查
{
    return a / b;
}

// 编译时求值
constexpr int result = safe_divide(10, 2);   // OK
constexpr int bad = safe_divide(10, 0);      // 编译错误
```

