# load model

从一个模型文件中加载vertex和index数据。

## sample mesh

使用的是一个将光照烘焙到纹理中的模型，OBJ格式。

继续通过stbi来加载texture。

使用tinyobjloader来加载obj文件。

```c++
#define TINYOBJLOADER_IMPLEMENTATION
#include <tiny_obj_loader.h>
```

由于vulkan坐标和stbi加载的不一致，我们需要对其进行翻转

```c++
stbi_set_flip_vertically_on_load
```

## loading vertices & indices

vertices和indices将不再是const的，并且作为成员变量。

写一个`loadModel()`函数。

```c++
void loadModel() {
    tinyobj::attrib_t attrib;
    std::vector<tinyobj::shape_t> shapes;
    std::vector<tinyobj::material_t> materials;
    std::string warn, err;

    if (!tinyobj::LoadObj(&attrib, &shapes, &materials, &warn, &err, MODEL_PATH.c_str())) {
        throw std::runtime_error(warn + err);
    }
}
```

通过`Loadobj` 加载到相应的数据结构。

obj文件由position\normals\texture coord\faces组成。

faces指定了任一数量的顶点，这个顶点是通过索引指定的。这个索引不仅是整个顶点的索引，可以引用某一个索引的属性。

- `attrib`中保存了vertices\normals\texcoords。
- `shapes`中保存了所有的面，其中的mesh的indices是一个index(tinyobj::index_t)的容器，包含vertex_index、normal_index、texcoord_index
- `err` 发生的错误
- `warn` 警告，例如缺少材质的定义。

```c++
vertex.pos = {
    attrib.vertices[3 * index.vertex_index + 0],
    attrib.vertices[3 * index.vertex_index + 1],
    attrib.vertices[3 * index.vertex_index + 2]
};

vertex.texCoord = {
    attrib.texcoords[2 * index.texcoord_index + 0],
    attrib.texcoords[2 * index.texcoord_index + 1]
};

vertex.color = {1.0f, 1.0f, 1.0f};
```

attrib是float来存储的，不是vec3,所以对于某个顶点位置的各个分量需要逐个访问。

### 去重

我们需要使用unordered_map来进行去重。

```c++
std::unordered_map<Vertex, uint32_t> uniqueVertices{};

for (const auto& shape : shapes) {
    for (const auto& index : shape.mesh.indices) {
        Vertex vertex{};

        ...

        if (uniqueVertices.count(vertex) == 0) {
            uniqueVertices[vertex] = static_cast<uint32_t>(vertices.size());
            vertices.push_back(vertex);
        }

        indices.push_back(uniqueVertices[vertex]);
    }
}
```

需要**注意**的一点是，我们这里保存的indices和obj中的索引是不一样的，我们indices是按照shape的顺序一个个添加的并且使我们所理解的顶点的索引。而obj中的是各个属性的索引，pos/tex/normal全部分开，我们无法直接加载后使用，所以需要对它们进行一个组合，组合到我们的vertex结构。

我们将自定义的struct作为了key，就需要实现额外的两个函数，判断是否相等的成员函数，以及一个hash函数。
