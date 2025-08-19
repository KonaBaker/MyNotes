https://zhxilin.github.io/post/tech_stack/1_programming_language/modern_cpp/cpp17/string_view/

**std::string_view**

获取一个字符串（既可以是std::string也可以是c风格字符串）的试图，并不真正创建或者拷贝字符串。性能比std::string要高很多。

本质是std::basic_string_view模板的一种实现。

可以通过字符数组指针、std::string构造。但是后者是通过类型转换构造了一个string_view的临时对象，再调用string_view的拷贝构造函数。

**注意事项**

- data()返回的是起始位置的字符指针，但此时要注意string_view被初始化的时候是否有\0结束符。
- 注意string_view所“观察”对象的声明周期，例如一些局部变量会在函数结束内存释放，string_view出现悬垂。
- string_view的相关函数被声明为constexpr。提供了其在编译期处理一些字面量字符串的能力，但不是表明其必须在编译期处理(不是consteval)。对于一些```std::string str = "1"```这种运行时数据，也是可以处理的。对于函数本身，只是有条件的减小了运行时开销。