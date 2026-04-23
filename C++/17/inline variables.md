**inline variables**

允许我们在头文件中定义变量，而无需担心多重定义的错误

```c++
// file1.cpp
#include <iostream>

inline int myVariable = 42;

void function1() {
    std::cout << "myVariable in function1: " << myVariable << std::endl;
}

// file2.cpp
#include <iostream>

extern inline int myVariable;  // 外部声明

void function2() {
    std::cout << "myVariable in function2: " << myVariable << std::endl;
}


// main.cpp
void function1();
void function2();

int main() {
    function1();  // 输出: myVariable in function1: 42
    function2();  // 输出: myVariable in function2: 42
    return 0;
}
```

内联变量的定义和声明必须在同一个作用域中。