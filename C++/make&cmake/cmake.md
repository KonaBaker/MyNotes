```c++
myproject/
├── CMakeLists.txt          ← 根
├── mathlib/
│   ├── CMakeLists.txt
│   ├── include/
│   │   └── mathlib/
│   │       └── math.h      ← 公开接口头文件（用户需要）
│   ├── src/
│   │   ├── math.cpp
│   │   └── internal.h      ← 内部实现头文件（用户不需要）
│   └── third_party/
│       └── fast_sqrt.h     ← 第三方库头文件（内部实现细节）
└── app/
    ├── CMakeLists.txt
    └── main.cpp
```

`target_include_directories`是告诉编译器去哪些目录找到include文件(找.h)

`target_link_libraries`是告诉链接器把这个库拼起来（找二进制库.a/.so/.lib)