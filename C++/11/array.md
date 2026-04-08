**std::array**

```c++
template<
    class T,
    std::size_t N
> struct array;
```

固定尺寸大小。

不会自动退化为`T*`

可以使用聚合初始化：`std::array<int, 3> a = {1, 2, 3};`

`a.data()`相当于`&a[0]`,但是前者更好