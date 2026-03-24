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