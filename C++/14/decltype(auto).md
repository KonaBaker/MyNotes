让编译器**使用decltype的推导规则**来推导类型。

它会保持引用、const、volatile的推导。

```c++
const int& get_const_ref() { return x; };
decltype(auto) d = get_const_ref();
```
