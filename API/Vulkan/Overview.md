# Overview

## vulkan with RAII

### vkInstance

**Vulkan C API 原生句柄**

```c++
VkInstance instance = VK_NULL_HANDLE;

VkInstanceCreateInfo createInfo = {};
vkCreateInstance(&createInfo, nullptr, &instance);

// 用完后手动释放
vkDestroyInstance(instance, nullptr);
```

只有资源标识，没有资源管理能力，需要手动释放。

### vk::Instance

**轻量包装**

```c++
vk::Instance instance;
instance = vk::createInstance(createInfo);
```

- 接口更C++
- 轻量包装
- type-safe

仍然需要手动。

```c++
instance.destroy();
```

### vk::raii::Instance

```c++
vk::raii::Context context;
vk::raii::Instance instance(context, createInfo);
```

自动管理生命周期。

例如一个`vk::raii::image`

```c++
class Image {
public:
    // 删除了默认构造函数！
    Image() = delete;
    
    // 正常构造：传入真实的 VkImage handle
    Image(Device const& device, ImageCreateInfo const& createInfo, ...);
    
    // 接受 nullptr 的构造函数：构造一个"空"对象
    Image(std::nullptr_t) noexcept : m_image(VK_NULL_HANDLE), m_device(nullptr) {}
    
    // 移动构造（RAII资源只能移动，不能拷贝）
    Image(Image&& rhs) noexcept;
    Image(Image const&) = delete;
};
```

不允许默认构造，但允许接收nullptr的空对象构造，即必须持有有效资源或者明确为空。

和原始指针一样：

```c++
int* p;        // 危险：未初始化的野指针
int* p = nullptr;  // 安全：明确为空
```