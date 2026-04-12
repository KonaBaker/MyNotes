## intro

我们现在可以为每个顶点传递任意的attribute，但是我们如何传递一个全局的变量呢？比如matrix这种全局且可能每帧变换。

> 是 GPU 资源（纹理、缓冲区、采样器等）的"打包容器"，告诉着色器去哪里读取数据。你可以把它理解为一组"资源绑定槽"的集合。

**resource descriptors**能帮助我们解决这个问题，一个descriptor可以让shader自由的访问像buffers和images这样的资源。descriptor的使用方法包括以下三个部分：

- 在pipeline创建的时候指定descriptor set layout
- 从descriptor pool中分配一个descriptor sets
- 在渲染的时候绑定descriptor sets

descriptor set layout指定了resources的类型，就像render pass明确attachments的类型一样。

descriptor set指定了将要绑定到descriptor的实际buffer，就像framebuffer指定了绑定到attachments的image view。

最后就是像vertex buffer那样，在draw call中被绑定。



descriptors有很多类型，这里使用的是uniform buffer objects descriptors. 

```c++
struct UniformBufferObject {
    glm::mat4 model;
    glm::mat4 view;
    glm::mat4 proj;
};
```

有这样一个结构体，我们把数据copy到一个buffer中。然后通过UBO descriptor在shader进行访问。

```glsl
struct UniformBuffer {
    float4x4 model;
    float4x4 view;
    float4x4 proj;
};
// [[vk::binding(0, 0)]] 显式控制 对于attribute同理[[vk::location(0)]]
ConstantBuffer<UniformBuffer> ubo;
```

slang的语法：

```
ConstantBuffer<T> -> ubo
Texture2D → sampled image
SamplerState → sampler
RWStructuredBuffer<T> → storage buffer
RWTexture2D → storage image
```

slang会自动分配set和binding编号。

## descriptor set layout

glm可以精确匹配shader中的类型，我们可以直接把UniformBufferObject memcpy 到一个vkbuffer中。

我们需要为shader使用的每一个descriptor binding提供详细信息，就像为每个attribute提供location一样。

```C++
void createDescriptorSetLayout() {}
```

每个binding都需要通过`VkDescriptorSetLayoutBinding`来描述

```c++
vk::DescriptorSetLayoutBinding uboLayoutBinding(0, vk::DescriptorType::eUniformBuffer, 1, vk::ShaderStageFlagBits::eVertex, nullptr);
```

- `binding` 对应一整个uniform buffer的binding
- `descriptorType` ubo\ssbo\image\sampler等等
- `descriptorCount ` 数组的长度 比如`layout(binding = 0) uniform sampler2D textures[8]; // descriptorCount = 8`
- `shaderStage`
- `pImmutableSamplers` 只对 `eSampler` 和 `eCombinedImageSampler` 类型有意义

所有的binding最后组合成一个`vkDescriptorSetLayout`

```c++
vk::DescriptorSetLayoutCreateInfo layoutInfo{.bindingCount = 1, .pBindings = &uboLayoutBinding};
vk::raii::DescriptorSetLayout descriptorSetLayout = vk::raii::DescriptorSetLayout(device, layoutInfo);
```

如果一个set有多个binding，我们先创建然后聚合到`std::array`中即可，传入数组指针。



在pipeline创建的过程中，我们需要指定descriptor layout来告诉shader使用哪些descriptor.这个结构我们在之前创建过

```c++
vk::PipelineLayoutCreateInfo pipelineLayoutInfo{ .setLayoutCount = 1, .pSetLayouts = &*descriptorSetLayout, .pushConstantRangeCount = 0 };
```

```c++
PipelineLayoutCreateInfo -> DescriptorSetLayout -> DescriptorSetLayoutBinding
    											-> DescriptorSetLayoutBinding
    											-> ...
    					 -> DescriptorSetLayout
    					 -> ...
```



## uniform buffer

和创建其他buffer的流程一样，但是这里不需要staging buffer，因为我们每一帧都要更新数据。

和command buffer等资源一样,uniform buffer也需要为并行帧做好准备，而具有多个副本。

```c++
std::vector<vk::raii::Buffer> uniformBuffers;
std::vector<vk::raii::DeviceMemory> uniformBuffersMemory;
std::vector<void*> uniformBuffersMapped;
```

```c++
void createUniformBuffers() {
    uniformBuffers.clear();
    uniformBuffersMemory.clear();
    uniformBuffersMapped.clear();

    for (size_t i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
        vk::DeviceSize bufferSize = sizeof(UniformBufferObject);
        vk::raii::Buffer buffer({});
        vk::raii::DeviceMemory bufferMem({});
        createBuffer(bufferSize, vk::BufferUsageFlagBits::eUniformBuffer, vk::MemoryPropertyFlagBits::eHostVisible | vk::MemoryPropertyFlagBits::eHostCoherent, buffer, bufferMem);
        uniformBuffers.emplace_back(std::move(buffer));
        uniformBuffersMemory.emplace_back(std::move(bufferMem));
        uniformBuffersMapped.emplace_back( uniformBuffersMemory[i].mapMemory(0, bufferSize));
    }
}
```



我们在创建缓冲区后立即使用 `vkMapMemory` 进行映射，以获得一个指针，以便后续写入数据。该缓冲区在整个应用程序生命周期内都将保持与此指针的映射状态。这种技术被称为**“持久映射”**，在所有 Vulkan 实现中均可使用。由于映射操作本身存在开销，避免每次更新缓冲区时都重新映射能够有效提升性能。

## updating uniform data

就是对每个变换矩阵进行更新变化。最后在copy数据到buffer中

```c++
memcpy(uniformBuffersMapped[currentImage], &ubo, sizeof(ubo));
```



## descriptor pool

我们需要将为每个vkbuffer创建descriptor set来绑定到layout中声明的ubo descriptor.

```c++
DescriptorSet[0]  ──指向──>  uniformBuffers[0]  (第 0 帧用)
DescriptorSet[1]  ──指向──>  uniformBuffers[1]  (第 1 帧用)
```

两个 descriptor set **共用同一个 layout**(形状一样),但里面填的 buffer 不同。

**<font color = ligblue> Notes: </font>**

**1. `VkDescriptorSetLayout`—— 模板/蓝图**

它只描述"形状":在 binding=0 位置有一个 uniform buffer,给 vertex shader 用。它不包含任何实际的 buffer,只是一个类型声明。可以理解成 C++ 里的 `struct` 定义。

**2. `VkBuffer`—— 实际的 GPU 内存**

里面存着真正的数据,比如 MVP 矩阵。它本身不知道自己会被绑定到哪个 binding 点。

**3. `VkDescriptorSet`—— 填好的实例**

按照 layout 的"形状"创建出来的一个实例,并且**告诉 Vulkan "binding=0 这个位置具体用哪个 VkBuffer"**。类比 C++ 就是按 struct 定义出的一个具体对象,字段都填上了值。



descriptor set 和cmd buffer一样需要从pool中进行分配

首先使用pool size描述这个pool里**每种类型的descriptor**总共有多少个

```
vk::DescriptorPoolSize poolSize(vk::DescriptorType::eUniformBuffer, MAX_FRAMES_IN_FLIGHT);
```

同样需要create info

```
vk::DescriptorPoolCreateInfo poolInfo{ .flags = vk::DescriptorPoolCreateFlagBits::eFreeDescriptorSet, .maxSets = MAX_FRAMES_IN_FLIGHT, .poolSizeCount = 1, .pPoolSizes = &poolSize };
```

maxset指定的是有多少个descriptor sets

同样的一个pool可以有多个pool szie，pool用`std::array`组织就可以了。

```
descriptorPool = vk::raii::DescriptorPool(device, poolInfo);
```

## descriptor set

```c++
std::vector<vk::DescriptorSetLayout> layouts(
    MAX_FRAMES_IN_FLIGHT, *descriptorSetLayout);

vk::DescriptorSetAllocateInfo allocInfo{
    .descriptorPool     = *descriptorPool,
    .descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
    .pSetLayouts        = layouts.data()
};
```

`vkAllocateDescriptorSets` 的设计是:**一次调用可以分配多个 set,每个 set 可以有各自不同的 layout**。所以 API 要求你传一个 layout 数组,长度 = 要分配的 set 数量。

在本例里,我们要分配 2 个 set,而且它们**形状完全一样**(都是"一个 UBO"),所以这个数组就是同一个 layout 重复 2 次。`std::vector` 的构造函数 `(count, value)` 刚好做这件事——创建一个 2 元素的 vector,每个元素都是 `*descriptorSetLayout`。

```c++
vk::raii::DescriptorPool descriptorPool = nullptr;
std::vector<vk::raii::DescriptorSet> descriptorSets;

...

descriptorSets.clear();
descriptorSets = device.allocateDescriptorSets(allocInfo);
```

现在我们要为每个descriptor指定buffer

```c++
for (size_t i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
    vk::DescriptorBufferInfo bufferInfo{
        .buffer = *uniformBuffers[i],
        .offset = 0,
        .range  = sizeof(UniformBufferObject)
    };

    vk::WriteDescriptorSet descriptorWrite{
        .dstSet          = *descriptorSets[i],
        .dstBinding      = 0,                                 // 对应 shader 里 binding = 0
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType  = vk::DescriptorType::eUniformBuffer,
        .pBufferInfo     = &bufferInfo
    };

    device.updateDescriptorSets(descriptorWrite, nullptr);
}
```



**RAII 对象管理生命周期,需要传给 C API 风格字段时,用 `*` 拿出原始句柄**。

```
			  ┌──────────────────────────┐
              │  DescriptorSetLayout     │   ← 只是个"形状"声明
              │  binding 0: UBO, vertex  │
              └──────────────────────────┘
                         ▲  ▲
                         │  │ (两个 set 共享同一个 layout)
                         │  │
         ┌───────────────┘  └───────────────┐
         │                                  │
  ┌──────────────┐                  ┌──────────────┐
  │ DescSet[0]   │                  │ DescSet[1]   │ 
  │ binding 0 ──┐│                  │ binding 0 ──┐│
  └─────────────┼┘                  └─────────────┼┘
                │                                  │
                ▼                                  ▼
       ┌─────────────────┐               ┌─────────────────┐
       │ uniformBuffer[0]│               │ uniformBuffer[1]│
       │  (第 0 帧用)     │               │  (第 1 帧用)     │
       └─────────────────┘               └─────────────────┘

                  ┌────────────────────┐
                  │ DescriptorPool     │  ← DescSet[0] 和 [1] 都从这里分配
                  │ maxSets = 2        │
                  │ UBO 描述符 = 2     │
                  └────────────────────┘
```

**<font color = ligblue> Notes: </font>**

一个 set 里有多个 binding,每个 binding 包含一个或多个 descriptor。一个 buffer 可以被多个 descriptor 共享,一个descriptor指向某个buffer的某个范围。

```
DescriptorSet
├── binding 0 (UBO)  ──> cameraBuffer      (相机矩阵)
├── binding 1 (UBO)  ──> lightBuffer       (灯光数据)
└── binding 2 (SSBO) ──> particleBuffer    (粒子数据)
```

一个descriptor需要一个bufferInfo来描述数据从哪里来。

一个WriteDescriptorSet对应一个binding。一个WriteDescriptorSet可能有多个bufferInfo(因为一个binding可能因为数组而含有多个descriptor)

**例子**

```c++
DescriptorSetLayout (布局定义)
│
├── binding 0  (descriptorCount = 1)
├── binding 1  (descriptorCount = 1)
└── binding 2  (descriptorCount = 3)  ← 数组 binding

         ↕ 对应

WriteDescriptorSet 数组
│
├── WriteDescriptorSet { dstBinding=0, descriptorCount=1, pBufferInfo → [bufferInfo_A] }
├── WriteDescriptorSet { dstBinding=1, descriptorCount=1, pBufferInfo → [bufferInfo_B] }
└── WriteDescriptorSet { dstBinding=2, descriptorCount=3, pBufferInfo → [bufferInfo_C0, bufferInfo_C1, bufferInfo_C2] }
                                                                          ↑ 连续数组，对应 binding 内的 [0] [1] [2]
```

bufferInfo + WriteDescriptorSet 连接上了实际的资源位置，即buffer。

DescriptorSetLayout 描述了布局，即有哪几个binding，descriptor都是什么类型，用在哪个shader stage。

- 给allocate用，用于在Cpp端接下来分配buffer
- 给pipeline layout用，用于告诉shader端布局。

最后就是在draw call的时候把pipeline layout和descriptorsets拿来调用bind。

## use

```c++
commandBuffers[frameIndex].bindDescriptorSets(vk::PipelineBindPoint::eGraphics, pipelineLayout, 0, *descriptorSets[frameIndex], nullptr);
commandBuffers[frameIndex].drawIndexed(indices.size(), 1, 0, 0, 0);
```

与顶点缓冲区和索引缓冲区不同，描述符集并非图形管线独有。因此，我们需要指定是将描述符集绑定到图形管线还是计算管线。



所以DescriptorSet描述的是某一帧，shader所用的资源的信息，它和其他概念是独立的：

- 资源本身(buffer / image / sampler 是各自独立创建和管理的)

- Layout(layout 只是形状声明,和具体资源无关)

- Pipeline(pipeline 只通过 layout 知道"形状",不知道具体填了什么)

**把"资源是什么"和"资源怎么被 shader 访问"分开**。



## Alignment requirements

C++ struct和shader内的uniform的匹配需要满足对齐要求。

- 标量类型，对齐N(= 4 bytes given 32-bit floats)
- float2是 2N
- float3/4 是 4N
- 嵌套结构，按照Base alignment向上取16的倍数
- float4x4和float4的对齐一样。

```c++
struct UniformBufferObject {
    glm::vec2 foo;
    alignas(16) glm::mat4 model;
    glm::mat4 view;
    glm::mat4 proj;
};

struct UniformBuffer {
    float2 foo;
    float4x4 model;
    float4x4 view;
    float4x4 proj;
};
ConstantBuffer<UniformBuffer> ubo;
```

对于这个例子，foo只有8bytes大小，需要使用alignas对齐到16.

我们也可以在glm头文件前定义

```c++
#define GLM_FORCE_DEFAULT_ALIGNED_GENTYPES
```

来强制对齐：

```c++
struct Foo {
    glm::vec2 v;
};

struct UniformBufferObject {
    Foo f1;
    alignas(16) Foo f2;
};
struct Foo {
    vec2 v;
};

struct UniformBuffer {
    Foo f1;
    Foo f2;
};
ConstantBuffer<UniformBuffer> ubo;
```

但是这个嵌套结构就失效了，需要手动定义

## multiple descriptor sets

通常我们可以同时绑定多个描述符集，每个集合有自己的**编号（set index）**，例如：

| Set 编号 | 用途                                                  |
| -------- | ----------------------------------------------------- |
| Set 0    | 全局共享资源（摄像机、光照等） 绑定一次               |
| Set 1    | 每个材质的资源（纹理、材质参数） 换材质的时候重新绑定 |
| Set 2    | 每个物体的资源（模型矩阵等） 每次物体绑定             |

```c++
[[vk::binding(0, 0)]] ConstantBuffer<GlobalUBO> globalData;  // set=0
[[vk::binding(0, 1)]] ConstantBuffer<ObjectUBO> objectData;  // set=1
```

这样根据绑定频次，将不同的资源分配到不同的set中，减少同步以及绑定开销。
