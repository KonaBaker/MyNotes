**lambda**

lambda expression是一个纯右值。是一个匿名函数对象。

```c++
[capture](params) -> return_type {
    body
}
```

各部分含义：

- `[capture]`：捕获外部变量
- `(params)`：参数列表
- `-> return_type`：返回类型，可省略
- `{ body }`：函数体

capture就是依赖的外部变量。

- 值捕获

```c++
int a = 10;
auto f = [a]() {
    return a;
};
```

拷贝进lambda对象里面，值传递。

```c++
int x = 10;

auto f = [x]() mutable {
    x += 1;
    return x;
};
```

mutable可以修改值捕获的值，修改的是保存的副本。

- 引用捕获

```c++
int a = 10;
auto f = [&a]() {
    a += 1;
};
```

- 默认捕获

```c++
[a, b]
[=]   // 默认按值捕获用到的外部变量
[&]   // 默认按引用捕获用到的外部变量

int a = 1, b = 2;
auto f = [=]() {
    return a + b;
};

int a = 1, b = 2;
auto f = [a, &b]() {
    return a + b;
};
```

参数不是外部变量。