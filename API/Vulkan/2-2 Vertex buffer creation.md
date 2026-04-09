# Vertex Buffer

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

第一步我们需要从vertexbuffer query需求：

```c++
vk::MemoryRequirements memRequirements = vertexBuffer.getMemoryRequirements();
```

 `vk::MemoryRequirements` 有三个字段

- `size`: 所需要分配的实际内存大小。比如我要一个100字节的buffer，GPU在分配的时候可能会向上取整进行对齐，比如256字节，会和bufferInfo的size不一致。`memRequirements.size >= bufferInfo.size`。分配内存的时候要使用前者，应用数据的时候使用后者。
- `alignment`: 资源在所分配内存中的起始偏移量必须满足的对齐要求（字节数），depends on `bufferInfo.usage` and `bufferInfo.flags`.如果访问不对齐，可能造成性能下降或者ub。
- `memoryTypeBits`: 每一位，是一个内存类型的索引，代表该资源可以使用第i个内存类型。

显卡会提供不同类型的存储，每种存储的性能和允许的操作不尽相同。我们需要结合我们的需求来找到合适的类型。

```c++
uint32_t findMemoryType(uint32_t typeFilter, vk::MemoryPropertyFlags properties) {}
```

1) 首先需要找到可用的类型

**[第一个参数选类型]**`typeFilter`就用bit的形式指定了合适的memory types，我们只要找到一个符合要求的就可以。这里只是应用了一个简单的循环算法，可以应用更复杂的算法。

**[第二个参数选feature]** properties(**`vk::MemoryPropertyFlags`**)  定义了某种类型(`vk::memoryType`)的一些特殊feature,比如是否可以map到cpu进行读写等等。

首先需要通过physical devices获取:

```c++
vk::PhysicalDeviceMemoryProperties memProperties = physicalDevice.getMemoryProperties();
```

这个结构体包括了两个arrays `memoryTypes`和`memoryHeaps`。其中`memoryTypes`这个array由`vk::memoryType`组成，`vk::memoryType`中又包括了heap以及properties. properties就定义了features

```c++
vk::PhysicalDeviceMemoryProperties -> memoryTypes -> vk::memoryType -> vk::MemoryPropertyFlags -> vk::MemoryPropertyFlagBits
```



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

第二个参数是offset，把这个 buffer 绑定到 `memory` 这块内存中、从第 `offset` 字节开始的位置。如果不是0,需要可以被`memRequirements.alignment`整除。也就是说，如果alignment = 256，那么这个memory的内存对齐要求就是256,如果offset = 100就是不可以的，512可以。

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

