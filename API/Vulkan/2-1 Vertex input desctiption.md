在vertex shader中声明attribute(per-vertex)，然后在app中定义相同的struct以及vertex data。

接下来就需要把data format传递给shader。这里需要两个结构:

## binding descriptions

`vk::VertexInputBindingDescription`

> A vertex binding describes at which rate to load data from memory  throughout the vertices. It specifies the number of bytes between data entries and whether to  move to the next data entry after each vertex or after each instance.

```c++
struct Vertex {
    glm::vec2 pos;
    glm::vec3 color;

    static vk::VertexInputBindingDescription getBindingDescription()
    {
      return {.binding = 0, .stride = sizeof(Vertex), .inputRate = vk::VertexInputRate::eVertex};
    }
};
```

- `binding` 就是binding index
- `stride`是 from one entry(一条记录，一个顶点的数据) to the next的字节数
- `inputrate`
  - `vk::VertexInputRate::eVertex`  Move to the next data entry after each vertex
  - `vk::VertexInputRate::eInstance`  Move to the next data entry after each instance

**entry解释**

entry就是一条记录，一个顶点的数据

```
|<-- entry 0 -->|<-- entry 1 -->|<-- entry 2 -->| ...
[pos0 | color0 ][pos1 | color1 ][pos2 | color2 ]
 0              20              40              60  (字节偏移)
```

## attribute descriptions

`vk::VertexInputAttributeDescription` 

> An attribute description struct describes how to extract a vertex  attribute from a chunk of vertex data originating from a binding  description.

```c++
#include <array>

...

    static std::array<vk::VertexInputAttributeDescription, 2> getAttributeDescriptions()
    {
      return {{{.location = 0, .binding = 0, .format = vk::Format::eR32G32Sfloat, .offset = offsetof(Vertex, pos)},
               {.location = 1, .binding = 0, .format = vk::Format::eR32G32B32Sfloat, .offset = offsetof(Vertex, color)}}};
    }
}
```

- `location` 对应vertex shader中的input的`location`修饰符。**某一段字节，应该被送进着色器的哪个输入变量**。
- `format` the type of data for the attribute。对于channel多或少的情况，处理方式和opengl是一样的，多的用默认值(0, 0, 1),少的直接丢弃。
  - `float` : `vk::Format::eR32Sfloat`
  - `float2`: `vk::Format::eR32G32Sfloat`
  - `float3`: `vk::Format::eR32G32B32Sfloat`
  - `float4`: `vk::Format::eR32G32B32A32Sfloat`
  - `int2`  : `vk::Format::eR32G32Sint`, a 2-component vector of 32-bit signed integers
  - `uint4` : `vk::Format::eR32G32B32A32Uint`, a 4-component vector of 32-bit unsigned integers
  - `double`: `vk::Format::eR64Sfloat`, a double-precision (64-bit) float

- `offset` 表明了从per-vertex data中的哪个字节数开始读这个attribute的数据。读多少呢？format已经规定了byte size。
- `binding` 表明了per-vertex data来自哪里。比如来自哪个vertex buffer?不同的attribute可能来自不同的buffer，但是组织到了同一个vertex结构里。找到对应index的binding description，这里面描述着数据如何排列，如上面写的stride是多少？按vertex还是instance等等。

## pipeline vertex input

```c++
auto bindingDescription = Vertex::getBindingDescription();
auto attributeDescriptions = Vertex::getAttributeDescriptions();
vk::PipelineVertexInputStateCreateInfo   vertexInputInfo{
    .vertexBindingDescriptionCount   = 1,
 	.pVertexBindingDescriptions      = &bindingDescription,
 	.vertexAttributeDescriptionCount = static_cast<uint32_t(attributeDescriptions.size()),
 	.pVertexAttributeDescriptions    = attributeDescriptions.data()
};
```

需要在pipeline构建的时候指定数据



