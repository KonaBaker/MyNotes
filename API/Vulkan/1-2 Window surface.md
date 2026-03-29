# presentation

## window surface

### 一些概念

- native window / window system 操作系统层面，窗口如何呈现于屏幕。还负责鼠标交互、关闭打开等management
  - wayland
  - x11
  - HWND on Windows

- WSI(window system Integration):Vulkan API extensions 用于连接渲染API和window system的，是桥梁。

<img src="./assets/wsi_setup.png" alt="wsi_setup" style="zoom: 50%;" />

平台无关的`VkSurfaceKHR`，是一个跨平台的抽象，传入具体平台的handles，后续就可以通过这个object，来和window system交互。

每个platform都需要自己的扩展和自己的方式来创建object传入这个抽象的surface。

- Libraries 封装了上述两层。对于vulkan API直接调用`glfwCreateWindowSurface`就可以得到抽象窗口，不用关心平台。
  - GLFW
  - SDL

`VK_KHR_surface` 是instance级别的扩展

### creation

```c++
vk::raii::SurfaceKHR surface = nullptr;
```

创建需要在instance create之后立即执行，因为可能会影响physical device的选择。

由于glfw只接受c的形式，所以需要先创建`vkSurfaceKHR`再来构建raii的形式。

### querying for presentation support

需要支持presentation的queue family，一般来说之前找的支持图形渲染的管线都有这个功能，但是还是需要检验一下

```C++
physicalDevice.getSurfaceSupportKHR(qfpIndex, *surface)
```

这也是为什么我们需要在physical device选择之前创建surface。

### presentation queue

同之前，physical device查是否支持，那么在logical device里面就要选出来。

## swap chain



## image views







