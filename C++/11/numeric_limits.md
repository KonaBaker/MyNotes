**std::numeric_limits<T>**

在limits的头文件中。用于在**编译时**查询基本算数类型的**各种属性和限制**

类型有long \ char \ float \ bool \ uint32_t 等等。

常用：

- min() 返回最小的有限值，float返回最小的positive value
- max()
- lowest() 最小值，或者0 for unsigned
- is_integer 
- 等等

**关于lowest和min的区别**

主要在于浮点类型。

min返回的是最小表示的正数。

lowest返回的是最小值。