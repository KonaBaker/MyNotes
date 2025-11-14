**const_cast**

可用于添加或者移除const.

但是对原始变量使用是ub。

**static_cast**

安全的类型转换。编译时进行类型检查。

用于处理类型之间的隐式转换（int->float等)

**reinterpret_cast**

不安全,应当尽量避免使用。

**dynamic_cast**
专门用于处理多态性。可以进行各种转型（向上、向下和横向）





