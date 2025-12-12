### Copy Elision复制消除/RVO(Return Value Optimization)/NRVO

**0次复制，0次移动，与c++11中介绍的move有所不同**

```c++
std::string result = std::string("hello"); 
std::string result = getValue();  
```

在move中介绍的临时对象和函数返回值，本身就是纯右值，他们本来就会匹配一些右值引用的一些参数。

```BigData a = createData();```

编译器会进行优化，直接在栈上分配内存，将内存地址作为隐式参数传入，并在返回时直接在地址进行构造。

move通常是对象已经存在，或者有一个左值需要转成右值。在move中需要调整指针（并置空）。



- **move**是有指针赋值的成本的
- **RVO**是0成本

对于push_back和emplace_back

```emplace_back(move(x))```和```push_back(move(x))```没有区别，都会调用移动构造函数。

真正区别如下：

```c++
// 写法 A: 产生临时对象 -> 移动构造到vector -> 析构临时对象
vec.push_back(BigData(1, 3.14)); 

// 写法 B: 直接在vector内存里调用 BigData(1, 3.14)
vec.emplace_back(1, 3.14); // 0次移动，0次复制
```



```c++
auto get_draw_command(Cube_Sphere const& io) -> Draw_Command
{
    Draw_Command cmd; // 1. 局部变量创建
    // ... 对 cmd 进行操作 ...
    return cmd;       // 2. 返回
}
```

这样也不会有临时对象产生，因为有**NRVO**的存在.

cmd的变量地址会直接映射到函数外部接收返回值的地址。



**RVO和NRVO只有在初始化的时候才会完美生效**。无论是赋值还是初始化，都会避免函数返回的那一次构造。他们的本质是编译器把”返回值的构造”直接延后到了“调用方提供的内存地址”上执行。但是赋值的时候，“调用方的内存地址”是临时开辟的，后续需要经过一次move赋值。但是这已经不是RVO和NRVO的范畴了。