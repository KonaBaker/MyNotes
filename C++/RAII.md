资源获取即初始化。

它将在使用前获取（分配的堆内存、执行线程、打开的套接字、打开的文件、锁定的互斥量、磁盘空间、数据库连接等有限资源）的资源的生命周期与某个对象的生命周期绑定在一起。

确保在控制对象的生命周期结束时，按照资源获取的相反顺序释放所有资源。

原理就是：**利用栈上局部变量的自动析构来保证资源一定会被释放**。（可能是我们忘记释放，或者由于异常程序提前终止，没有执行释放）

一个RAII的类的实现需要四个步骤

- 设计一个类封装资源，资源可以使上述的所需要获取的资源。
- 在构造函数中执行资源的初始化。
- 在析构函数中执行销毁操作。
- 在使用的时候声明一个该对象的类。

```c++
class Instance {
private:
    VkInstance handle = VK_NULL_HANDLE;

public:
    Instance(std::nullptr_t) {
        handle = VK_NULL_HANDLE;
    }

    Instance(Context const& ctx, CreateInfo const& info) {
        vkCreateInstance(..., &handle);
    }

    ~Instance() {
        if (handle != VK_NULL_HANDLE) {
            vkDestroyInstance(handle, ...);
        }
    }

    VkInstance get() const { return handle; }
};
```

例如vkInstance像这样被封装起来管理生命周期。

栈对象，自动析构，类智能指针风格（可以later赋值，生命周期管理。
