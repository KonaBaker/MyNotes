**remove_cvref**
去除类型的引用和顶层的cv限定符（const和volatile)

``` std::remove_cvref<T>::type ```

```c++
template <typename T>
struct remove_cvref {
	using type = std::remove_cv_t<std::remove_reference<t>>;
}
```

