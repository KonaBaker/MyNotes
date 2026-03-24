# setup

## base code

## instance

是vulkan的handle,用于连接application与vulkan library/loader/driver。在其中指定application的详细信息，以及上下文等等。

vulkan中大量信息是通过**结构体而非函数参数**传递的。

instance的createinfo中包括：

- application信息
- 验证层
- 需要使用的全局扩展（适用于整个程序，而非特定设备）。

- 其他

一般对象创建的函数的参数包括：

- createinfo
- allocator callbacks
- 依赖（需要）的device/instance/context

返回一个vk::raii接收。

```c++
instance = vk::raii::Instance(context, createInfo);
```

关于createinfo：

```c++
vk::InstanceCreateInfo createInfo{
    .pApplicationInfo = &appInfo
};
```

它本身是一个普通对象，离开作用域自动销毁，所以不需要资源释放和管理，所以这里使用的是vulkan-hpp而不是RAII。

这种初始化方式是**指定成员初始化**。

## validation layers

vulkan原生检查很少，减少驱动开销（driver overhead).

**validation**

使用验证层是避免application因意外依赖未定义行为而在不同驱动程序上崩溃

validation一般是运行时检查。在调用drawcall的时候会检查framebuffer完整性，program以及众多buffer是否合法，texture是否可以采样等等一系列问题。

而vulkan在运行的时候剥离了这一层,validation layer。这一层是可选组件，会hook到vulkan的函数调用中执行额外操作。可以在开发时启用，在发布的时候关闭。

没有validation layer并不意味着完全不检查，还是有一些常见错误可以被检查出来。除了标准的`VK_LAYER_KHRONOS_validation`还有一些其他第三方的验证层可以使用。

**opengl vs vulkan**

关于validation这一概念，opengl和vulkan的关系有点像rust和c++。

vulkan的API更加底层细化，规则也更加详细，其语义本身更加静态、更加显式、更少副作用。opengl本身语义较为宽松，如果很多东西驱动不去validation，那么就无法正确实现规范要求的行为。

在vulkan中一些shader组合，大部分状态，以及编译/链接信息提前打包到vkpipeline中。**接近可直接执行（承诺语义）的状态包，给了很强的静态承诺**。

而在opengl中，例如API没有要求application显示声明，前后访问关系，image是什么layout，但是同时要求了API本身结果必须正确。那么驱动就只能自己跟踪，猜测，插入同步。

这些需要推断的语义，被vulkan要求显式写出来，提供给驱动。

- 多参数、类型不匹配这些归编译器检查不属于validation layer
- 一些匹配、同步、资源绑定等等的一系列契约（我要求你做什么，提供什么等等）才会由validation layer进行检查。

例子：【详见例子-validationlayer】



physical devices & queue family

logical device & queues
