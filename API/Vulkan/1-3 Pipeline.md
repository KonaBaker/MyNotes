# Pipeline

## Introduction

![vulkan simplified pipeline](./assets/vulkan_simplified_pipeline.svg)

- input assembler 从buffer收集原始顶点数据。
- tessellation shader subdivide geometry to increase mesh quality
- geometry shader.在图元上运行，丢弃该图元或者输出更多的图元。在除了intel集成GPU外的大多数显卡上，性能不理想。被**mesh shader**管线来替代。和光线追踪一样，是一种全新的管线方案。
- color blend是固定的。不同于opengl，不可随意更改管线设置。

vulkan的图形管线几乎是**completely immutable**。如果想要更改shader、绑定不同的framebuffer、设置blend func，都必须重新创建管线。

pros: **承诺语义** 减少驱动程序开销，更好的优化。

cons:操作繁琐。

## shader modules

vulkan必须指定字节码format：SPIR-V（专门为vulkan设计的）

有了统一的byte code，就有了标准，对于shader在不同gpu上的行为会更加一致。同时也降低了GPU厂商编写compiler的复杂度(shader code -> native code).

SPIR-V是一种强类型的IR，语义明确定义。而glsl是一种文本语言，可解释空间大。

### vertex shader

![normalized device coordinates](./assets/normalized_device_coordinates.svg)

对于NDC，xy的范围和OpenGL一致但是y坐标翻转，z范围变成了[0,1].

入口：`vertMain` slang支持多个入口。返回值是输出

对于slang并没有采用内置变量，而是一种语义标注的方式：

`SV_VertexID` 当前顶点索引。

`SV_Position` 相当于gl_Position，输出clip space 的位置。

```c++
float4 sv_position : SV_Position;
float4 fragMain(VertexOutput inVert) : SV_Target
```

支持创建shader modules

### fragment shader

入口：`fragMain` 需要指定SV_target，返回值是颜色。参数接收顶点的输出。

输入输出是通过location指定的索引链接在一起的。

### loading

编译通过slangc编译为spv，loading的不是slang原文本，而是编译后的spv。

最终得到的是`std::vector<std::byte> buffer`。

具体文件操作可以参考【fstream】

### creating shader modules

在loading以后我们需要将其封装到`vk::raii::ShaderModule`对象中，才能传递到管线。

shadermodule同样需要createinfo。但是信息就很少了，只需要一个指针和大小。

```c++
vk::ShaderModuleCreateInfo createInfo{ 
    .codeSize = code.size() * sizeof(char), 
    .pCode = reinterpret_cast<const uint32_t*>(code.data()) 
};
```

spir-v的基本单元是32-bit word四个字节，以uint32_t组织。需要做类型转换。

> 但是这里有一个“匪夷所思”的点就是codesize 和 pcode的不一致，按理说codesize应该也以uint32_t为单位进行计算。

shader modules也是**device**级别的。

**notes**

编译链接spirv的行为知道图形管线创建才会发生，而且发生后就没用了。

所以可以作为创建图形管线函数中的局部变量。

### creating shader stage

使用`vk::PipelineShaderStageCreateInfo`传递给管线。

```c++
vk::PipelineShaderStageCreateInfo vertShaderStageInfo{ 
    .stage = vk::ShaderStageFlagBits::eVertex, 
    .module = shaderModule,  
    .pName = "vertMain" 
};
vk::PipelineShaderStageCreateInfo fragShaderStageInfo{ 
    .stage = vk::ShaderStageFlagBits::eFragment, 
    .module = shaderModule, 
    .pName = "fragMain" 
};
vk::PipelineShaderStageCreateInfo shaderStages[] = {vertShaderStageInfo, fragShaderStageInfo};
```



创建好结构体数组后就完成了，稍后会被管线引用。
