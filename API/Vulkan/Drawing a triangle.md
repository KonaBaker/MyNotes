# base code

## 资源管理

现代c++可以通过`<memory>`头文件进行自动地资源管理。重载std::shared_ptr，应用RAII。

使用`vkCreate*`或者`vkAllocate*`来创建对象。使用`vkDestroy*`或`vkfree*`来清除对象。

## glfw交互 

## Instance

VkInstance是application和driver之间的连接桥梁

application就是你的应用程序，包含程序的名字，版本号和引擎名字等信息。

这写信息是给显卡驱动看的（可能会针对一些application比如知名游戏，做特定优化）

extension顾名思义就是额外的功能，比如vulkan并不”知道“窗口，就需要glfw的扩展。

# 校验层

所有实用的标准验证功能已集成至 SDK 内置的 `VK_LAYER_KHRONOS_validation` 层中。

通过

```c++
const std::vector<const char*> validationLayers = {
    "VK_LAYER_KHRONOS_validation"
};
```

指定想要启动的层。

validationLayers中保存的就是想要启动的层的名字，这里只有一个。

我们还需要检查请求的层是否可用，因为可能一些我们想要的层在这台主机上没有，或者这个环境上不可用。

```c++
bool checkValidationLayerSupport() {
    uint32_t layerCount;
    vkEnumerateInstanceLayerProperties(&layerCount, nullptr);

    std::vector<VkLayerProperties> availableLayers(layerCount);
    vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.data());

    return false;
}
```

之后对`availableLayers`以及`validationLayers`进行一一比对。

# 物理设备和队列簇

