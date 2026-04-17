# std::ranges

旨在提供更高效、更易用的容器操作方式。

`std::ranges::any_of(...)`

对容器内部的元素逐个检查，只要一个元素满足条件就返回true.

`all_of` / `any_of` / `none_of` 是“判定型”算法，返回 `bool`

`find` / `find_if` / `find_if_not` 是“查找型”算法，返回迭代器。`find_if` 会找第一个让满足条件的的元素。

- `std::ranges::find(range, value);`

- `std::ranges::find_if(range, [](auto const& elem) { return /* 条件 */; });`

两种按值查找和按条件查找

`find_first_of` 是“在一组候选值里找第一个匹配项”，也就是在一个范围中找“是否出现过第二个范围里的任意元素”。

```c++
[](auto x) { ... }
T& elem = *it;
auto x = elem;   // 这里拷贝

[](auto const& x) { ... }
T& elem = *it;
auto const& x = elem;   // 这里只是绑定引用
```

无需写范围：

传统写法：

```
std::any_of(v.begin(), v.end(), pred);
```

ranges 写法：

```
std::ranges::any_of(v, pred);
```

**pros**:

- 书写便捷，提升可读性。
- 惰性求值的views管道
- projection减少lambda样板
