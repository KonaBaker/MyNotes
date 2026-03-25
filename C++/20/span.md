# std::span

连续对象存储(不一定是数组）的观察者类似string_view.

可以有两种范围：静态：编译期确定大小 动态：由指向第一个对象的指针和连续对象的大小组成。

```
template<
    class T,
    std::size_t Extent = std::dynamic_extent
> class span;
```



引擎中的make_span是：

```
template <typename T>
inline auto make_span(T&& x) -> auto
{
    return span{nonstd::move<T>(x)};
}
```

