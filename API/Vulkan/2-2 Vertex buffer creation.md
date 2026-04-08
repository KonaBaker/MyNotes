> Buffers in Vulkan are regions of memory used for storing arbitrary data that can be read by the graphics card.

和之前介绍的很多vulkan object不同，buffer并不会为自己自动分配memory。

## buffer create

回到了老样子，我们需要一个createinfo

```C++
vk::BufferCreateInfo bufferInfo{.size        = sizeof(vertices[0]) * vertices.size(),
                                .usage       = vk::BufferUsageFlagBits::eVertexBuffer,
                                .sharingMode = vk::SharingMode::eExclusive};
vk::raii::Buffer vertexBuffer = vk::raii::Buffer(device, bufferInfo);;
```

- `size` buffer in bytes
- `usage` 里面的数据用来干什么的。
- `sharingMode` 和swapchain中这个字段类似，可以在不同queue family间共享，或者只被一个特定的queue family使用。这里只被graphics queue使用

## memory 

这时候的buffer还没有分配memory。

### requirements

第一步我们需要query需求：

```c++
vk::MemoryRequirements memRequirements = vertexBuffer.getMemoryRequirements();
```

 `vk::MemoryRequirements` 有三个字段

- `size`: The size of the required memory in bytes may differ from `bufferInfo.size`.
- `alignment`: The offset in bytes where the buffer begins in the allocated region of memory, depends on `bufferInfo.usage` and `bufferInfo.flags`.
- `memoryTypeBits`: Bit field of the memory types that are suitable for the buffer.

显卡会提供不同类型的存储，每种存储的性能和允许的操作不尽相同。我们需要结合我们的需求来找到合适的类型。

```c++
uint32_t findMemoryType(uint32_t typeFilter, vk::MemoryPropertyFlags properties) {}
```

1) 首先需要找到可用的类型

**[第一个参数]**`typeFilter`就指定了合适的类型，我们只要找到一个符合要求的就可以。这里只是应用了一个简单的循环算法，可以应用更复杂的算法。

```c++
vk::PhysicalDeviceMemoryProperties memProperties = physicalDevice.getMemoryProperties();
```

这个结构体包括了两个arrays `memoryTypes`和`memoryHeaps`

**[第二个参数]**`vk::memoryType`中又包括了heap以及properties，properties(**`vk::MemoryPropertyFlags`**)定义了这种类型的一些特殊feature,比如是否可以map到cpu进行读写等等。

```C++
for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++)
{
    if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties)
    {
        return i;
    }
}
```

### allocation

我们已经决定了类型。

第二步就是要分配了。

```C++
vk::MemoryAllocateInfo memoryAllocateInfo{
    .allocationSize  = memRequirements.size,
    .memoryTypeIndex = findMemoryType(memRequirements.memoryTypeBits, vk::MemoryPropertyFlagBits::eHostVisible | vk::MemoryPropertyFlagBits::eHostCoherent)};
```

需要一个memory req和alloc的handle

```
vertexBufferMemory = vk::raii::DeviceMemory(device, memoryAllocateInfo);
```

我们需要将这块memory和vertexbuffer联系起来

```c++
vertexBuffer.bindMemory( *vertexBufferMemory, 0 );
```

第二个参数是offset，如果不是0,需要可以被`memRequirements.alignment`整除

## filling

```c++
void* data = vertexBufferMemory.mapMemory(0, bufferInfo.size);
memcpy(data, vertices.data(), bufferInfo.size);
vertexBufferMemory.unmapMemory();
```

map到cpu然后填充数据。

有两种方法解决cpu和gpu数据同步的问题：

- 一个就是我们刚刚找memory type的时候，给定标识`vk::MemoryPropertyFlagBits::eHostCoherent`
- 在map 读之前调用`vk::raii::Device::invalidateMappedMemoryRanges`，写之后`vk::raii::Device::flushMappedMemoryRanges`

这个同步肯定是有性能上的开销的。

这个同步只是表示，驱动意识到我们正在写buffer，但是并不意味着立即对gpu可见，这个数据传递过程在后台进行。但是可以保证这个过程会在`submit`前完成。

## bind

```c++
commandBuffer.bindVertexBuffers(0, *vertexBuffer, {0});
```



**整个流程大概如下**

```
pipeline - bindingDesc --commandbuffer-- vertexbuffer - memory - allocate - requirements
		 - attrDesc							  | map
		 								 vertex data
```

