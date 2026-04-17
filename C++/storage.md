https://en.cppreference.com/w/cpp/language/storage_duration.html#Automatic_storage_duration
待完善

# storage class specifiers

## Storage duration

存储周期是object的一个属性，定义了该object存储的生命周期。

- static
- automatic
- thread
- dynamic

static\automatic\thread 和 声明的object以及临时object 关联。

dynamic 则是和 new 关联。

对于subobject、引用成员，它们的存储周期和完整对象相同。

### static duration

静态存储期，需要同时满足以下条件：

- namespace scope或者首次以static/extern声明
- 不具有线程存储周期

在整个程序运行期间持续。

### Thread duration

- 以thread_local声明的变量

和创建它的线程的生命周期相同

### Automatic duration

以下变量属于automatic

- 块作用域，且未显式声明为static、thread_local、extern的变量。
- 参数作用域的变量。

存储期持续到退出块或者函数。

### dynamic duration

通过以下方法创建的object：

- new
- 其他隐式方法
- exception objects

## linkage