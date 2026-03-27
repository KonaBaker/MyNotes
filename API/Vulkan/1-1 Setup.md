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

## physical devices & queue family

vulkan中几乎所有操作，draw、上传纹理等操作，都需要将命令提交到queue中执行，queue有不同的类型（来自不同的family)。每个family只允许执行特定的子集命令。

```c++
vk::raii::PhysicalDevice physicalDevice = nullptr // 接收选取的显卡
auto physicalDevices = instance.enumeratePhysicalDevices()； // 获取显卡列表
```

### 适用性检查

- `getProperties` 获得一些诸如设备名称、类型和支持的 Vulkan 版本等基本属性
- `getFeatures` 获得一些可选功能支持的信息。
- `getQueueFamilyProperties` 获得设备支持的queue family
- `enumerateDeviceExtensionProperties` 获得设备支持的扩展

这些都是在phtsical device上操作。

## logical device & queues

### 指定info

创建logical device同样需要createinfo,在其中指定一些结构体，这些结构体中又包含一系列info。

1) `vk::DeviceQueueCreateInfo` 指定要创建的队列

- `queueFamilyIndex` 需要的队列族的index，比如graphics
- `queueCount` 需要的queue的数量
- `pQueuePriorities` 优先级(影响command buffer调度)

2) `vk::StrcutureChain` 来指定需要的一些额外功能。

vulkan向后兼容，默认只能使用vulkan 1.0中的基本功能，如果要使用额外功能，需要**显式**启用。

```c++
// Create a chain of feature structures
vk::StructureChain<vk::PhysicalDeviceFeatures2, vk::PhysicalDeviceVulkan13Features, vk::PhysicalDeviceExtendedDynamicStateFeaturesEXT> featureChain = {
    {},                               // vk::PhysicalDeviceFeatures2 (empty for now)
    {.dynamicRendering = true },      // Enable dynamic rendering from Vulkan 1.3
    {.extendedDynamicState = true }   // Enable extended dynamic state from the extension
};
```

structureChain是一个辅助模板，连接三个不同功能结构体。{}内对每个结构初始化。

传入只需要传入第一个结构体的指针就可以了。

3) 指定设备扩展requiredDeviceExtension（上面验证是否支持扩展的时候使用过）

以上综合整个指定过程，其实就是**复刻**了一遍上面的**适用性检查**。上面检查物理设备是否支持，下面逻辑设备就要显式指定这些feature。

### create

```c++
vk::DeviceCreateInfo deviceCreateInfo{
    .pNext = &featureChain.get<vk::PhysicalDeviceFeatures2>(),
    .queueCreateInfoCount = 1,
    .pQueueCreateInfos = &deviceQueueCreateInfo,
    .enabledExtensionCount = static_cast<uint32_t>(requiredDeviceExtension.size()),
    .ppEnabledExtensionNames = requiredDeviceExtension.data()
};
device = vk::raii::Device( physicalDevice, deviceCreateInfo );
```

和instance中指定的区别是，这些extension及一些设置是这个**设备特定**的。

### queue handles

我们需要一个handle来和与device一同创建的queue进行交互。

```c++
vk::raii::Queue graphicsQueue = vk::raii::Queue( device, graphicsIndex, 0 );
```

