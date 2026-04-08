swap chain creation

## intro

当门调整窗口的大小的时候,window surface就会发生变换，此时我们的swap chain就和surface不再适配了。我们就需要捕获这些事件并对swap chain进行重建。

## recreate

我们首先需要调用`waitIdle`等待之前的渲染，并释放它们的资源。之后我们还需要cleanup之前不用的objects 比如imageview之类的。最后直接调用之前定义的创建函数即可。

```c++
swapChainImageViews.clear();
swapChain = nullptr;
createSwapChain();
createImageViews();
```

这样做有一个缺点就是，我们需要等待所有渲染完成之后，去重新创建新的swap chain。我们可以在旧的渲染在旧的swap chain的同时，创建新的swap chain。我们这时候需要在`vk::SwapchainCreateInfoKHR`中的`oldSwapchain`去指明旧的swapchain，这样可以在适时用完旧的swap chain再destroy它

## suboptimal / out-of-date-swap chain

我们需要知道什么时候该重建swap chain。vulkan的 `vk::raii::SwapchainKHR::acquireNextImage`和`vk::raii::Queue::presentKHR`的返回值会告诉我们。

- `vk::Result::eErrorOutOfDateKHR` 说明swap chain和window surface已经不兼容了（例如窗口尺寸改变）。**不能用于prersent**，必须进行重建。这个结果会发出异常，我们可以通过定义宏`VULKAN_HPP_HANDLE_ERROR_OUT_OF_DATE_AS_SUCCESS`，让其变成success结果(只是不抛出异常，但是获取图像仍然是失败的），然后我们再自行判断。
- `vk::Result::eSuboptimalKHR` swap chain**还可以继续去present**，但是只是属性和surface不再匹配。呈现的结果可能有拉伸或者黑边。这个仍然属于成功返回的范畴。

在处理这些结果的时候，我们需要注意的一点就是**fence以及semaphore。**因为我们的重建流程，可能会破坏掉原本的同步逻辑，导致一直wait或者signaled的情况出现。

` vk::raii::SwapchainKHR::acquireNextImage`之后

```c++
if (result == vk::Result::eErrorOutOfDateKHR) // acquire失败了，image没有被获取，imageAvailableSemaphore也没有被signal
{
    recreateSwapChain();
    return; // 这里return了，注意我们的fence在之前就被reset了，所以会导致后续一直会等待，需要在我们可以确定可以submit的时候在reset fence
}
// suboptimal 会成功acquire,不能直接return去重建，否则imageAvailableSemaphore就没人wait了会破坏信号量状态。选择先进行submit,消耗掉
// 这个信号量，然后由present来处理suboptimal
// vulkan要求：把一个 binary semaphore 传给 acquireNextImage 或作为 submit 的 signal semaphore 时，它必须处于 unsignaled 状态。
if (result != vk::Result::eSuccess && result != vk::Result::eSuboptimalKHR) 
{
    assert(result == vk::Result::eTimeout || result == vk::Result::eNotReady);
    throw std::runtime_error("failed to acquire swap chain image!");
}
```

`vk::raii::Queue::presentKHR`之后 imageAvailableSemaphore以及renderFinishedSemaphore都已经被用过了，并且wait(消费）了。信号量处于“正常”状态。**notes**：无论返回的是不是erroroutofdate，因为wait信号量的操作是在这之前。

```c++
if ((result == vk::Result::eSuboptimalKHR) || (result == vk::Result::eErrorOutOfDateKHR) || framebufferResized)
{
    framebufferResized = false;
    recreateSwapChain();
}
else
{
    // There are no other success codes than eSuccess; on any error code, presentKHR already threw an exception.
    assert(result == vk::Result::eSuccess);
}
```

**Sum**: 

1) acquire 之后的`eErrorOutOfDateKHR`意味着根本没有拿到image,而后续的cmd,submit等等都依赖这个image index，所以不能进行下去，recreate完之后直接return,相当于作废这一帧。
2) 而acquire之后的`submitOptimal`拿到了image,可以present只是不完美，那么继续进行这一帧，交给后续present处理。
3) present之后，到这里这一帧该做的都做了,record,submit,present等等，信号量也使用过了，如果还需要重建，那和这一帧也没有关系了，不需要return,直接frameindex++走下一帧了。

## explicitly

即使大部分驱动或者平台都可以自动检测window resize然后返回上述两个resulty，但是这并不是保证发生的。所以我们为了保险起见，需要显式处理window resize这个事件。

需要加一个新的成员变量`framebufferResized`，这个检测需要确保在present之后，如果放在present之前，会导致一个semaphore（acquire之后就是imageAvailable,submit之后就是renderfinished)一直处于被signaled的状态

通过回调函数进行detect

```c++
void initWindow()
{
    glfwInit();

    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);

    window = glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", nullptr, nullptr);
    glfwSetWindowUserPointer(window, this);
    glfwSetFramebufferSizeCallback(window, framebufferResizeCallback);
}

static void framebufferResizeCallback(GLFWwindow* window, int width, int height)
{
    auto app = reinterpret_cast<HelloTriangleApplication*>(glfwGetWindowUserPointer(window));
    app->framebufferResized = true;
}
```

**为什么是static?**

因为c和c++的兼容问题

```c++
typedef void (*GLFWframebuffersizefun)(GLFWwindow*, int, int);
void glfwSetFramebufferSizeCallback(GLFWwindow*, GLFWframebuffersizefun);
```

这是set callback的定义，它要求一个函数的是上面那个样子，不包含this指针，如果将`framebufferResizeCallback`(也就是GLFWframebuffersizefun)声明成成员函数，就会带隐式的this指针。所以要static。但是我们又需要这个，所以需要设置一个userpointer来保存this。

## handling minimization

对于最小化窗口我们暂停渲染,直至其恢复。

```c++
void recreateSwapChain() {
    int width = 0, height = 0;
    glfwGetFramebufferSize(window, &width, &height);
    while (width == 0 || height == 0) {
        glfwGetFramebufferSize(window, &width, &height);
        glfwWaitEvents(); // 不是busy wait，会等待事件触发
    }

    device.waitIdle();

    ...
}
```

