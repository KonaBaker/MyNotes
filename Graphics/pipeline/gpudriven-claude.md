# GPU-Driven Rendering Pipeline 深度解析

> 从 CPU-bound 到 GPU 自治：原理、数据结构、Vulkan 实现与现代引擎实践

------

## 目录

1. [为什么需要 GPU-Driven？](#1-为什么需要-gpu-driven)
2. [架构演进路线](#2-架构演进路线)
3. [核心数据结构设计](#3-核心数据结构设计)
4. [Indirect Draw：CPU 让权的起点](#4-indirect-draw-cpu-让权的起点)
5. [Compute Shader 作为 Command Generator](#5-compute-shader-作为-command-generator)
6. [GPU 端剔除系统](#6-gpu-端剔除系统)
7. [两趟式遮挡剔除与 HZB](#7-两趟式遮挡剔除与-hzb)
8. [Bindless 资源系统](#8-bindless-资源系统)
9. [Mesh Shader 与 Meshlet](#9-mesh-shader-与-meshlet)
10. [完整帧流程串联](#10-完整帧流程串联)
11. [GPU Scene：场景数据的 GPU 侧管理](#11-gpu-scene场景数据的-gpu-侧管理)
12. [Virtual Geometry：Nanite 的核心思路](#12-virtual-geometry-nanite-的核心思路)
13. [现代引擎实现参考](#13-现代引擎实现参考)
14. [性能分析与常见陷阱](#14-性能分析与常见陷阱)

------

## 1. 为什么需要 GPU-Driven？

### 1.1 传统渲染管线的瓶颈

在传统 CPU-driven 渲染模型中，每一帧大致经历：

```
CPU Loop:
  for each object in scene:
    if (frustum_cull(object)):           // CPU 做剔除
      bind_pipeline(object.pipeline)    // API 调用
      bind_descriptor_set(object.mat)   // API 调用
      bind_vertex_buffer(object.mesh)   // API 调用
      draw_indexed(...)                  // API 调用 → 提交 draw call
```

这个模型在对象数量较少时工作良好，但存在几个根本性限制：

**API 调用开销（CPU-side）**

每个 `vkCmdDraw*` 调用都需要经过驱动层的验证、状态跟踪和命令录制。现代 CPU 上，一个 draw call 的 CPU 端开销大约在 **1–10 µs** 之间。如果场景有 10,000 个对象，CPU 每帧仅在 draw 调用上就可能花费 10–100 ms，这远超 16 ms 的帧预算。

**CPU-GPU 同步气泡**

CPU 需要等待上一帧的结果才能做某些决策（如遮挡查询结果），或者 GPU 需要等 CPU 准备好命令才能开始执行，造成流水线气泡：

```
Frame N:   [CPU work ████████][GPU work ████████]
Frame N+1:                   [CPU wait ████][CPU work ████][GPU work ████████]
                                   ↑
                              GPU 因等待 CPU 而空转
```

**剔除精度与并行度**

CPU 单线程（即使多线程）的剔除能力远不及 GPU。一帧内 CPU 能合理剔除数千个对象，而 GPU 可以并行处理数十万个对象的剔除，且可以利用深度缓冲做精确的像素级遮挡剔除。

### 1.2 GPU-Driven 的核心思想

**把"决策权"移交给 GPU**。

CPU 的工作退化为：

1. 上传/维护场景描述数据（Mesh 描述符、变换矩阵、材质句柄）
2. 发起少量 Compute dispatch 和 Indirect draw 调用
3. 处理游戏逻辑（不涉及渲染决策）

GPU 自行完成：

1. 遍历所有潜在可见对象
2. 执行多级剔除
3. 生成 draw 命令
4. 执行光栅化或光线追踪

最终理想状态下，CPU 每帧只需要一次 `vkCmdDispatch`（剔除）+ 一次 `vkCmdDrawIndexedIndirectCount`（渲染），draw call 数量从 O(可见对象数) 降为 **O(1)**。

------

## 2. 架构演进路线

### 阶段一：Naive（每对象一次 draw）

```
CPU → [bind mat A][draw A][bind mat B][draw B][bind mat C][draw C]...
                ↑           ↑           ↑
           API overhead × N objects
```

### 阶段二：Instancing（相同 Mesh 合批）

```cpp
vkCmdDrawIndexedInstanced(mesh, instance_count, first_instance);
```

解决了相同 mesh 的重复绘制，但不同 mesh 依然需要单独调用，且材质变化仍是瓶颈。

### 阶段三：Multi-Draw Indirect（MDI）

```
CPU 写入 command buffer → GPU 批量执行所有 draw
      ↓
vkCmdDrawIndexedIndirect(indirect_buffer, draw_count)
```

CPU 一次性把所有 draw 命令写入一个 GPU buffer，然后用单条 API 调用触发全部绘制。draw call 数量从 O(N) 降为 O(1)，但剔除仍在 CPU 完成。

### 阶段四：GPU-Driven（Compute 生成命令）

```
Compute Pass: 读取 scene data → 执行 GPU 剔除 → 写入 indirect command buffer
Draw Pass:    vkCmdDrawIndexedIndirectCount(indirect_buffer)
```

剔除逻辑迁移到 GPU，CPU 完全不参与 per-object 决策。

### 阶段五：Mesh Shader Pipeline（完全脱离顶点索引缓冲约束）

Task Shader（放大器） → Mesh Shader（生成几何） → Fragment Shader

支持 LOD 选择、micro-tessellation、剔除的最细粒度（meshlet 级别），是 Nanite 等系统的基础。

------

## 3. 核心数据结构设计

GPU-driven 的基础是把"场景"描述为一组 GPU 可直接读取的结构化数据。

### 3.1 Mesh Descriptor（网格描述符）

```cpp
// 描述一个 mesh 在 vertex/index buffer 中的位置
struct MeshDescriptor {
    uint32_t vertex_offset;      // 在全局顶点池中的起始 index
    uint32_t index_offset;       // 在全局索引池中的起始位置
    uint32_t index_count;        // 索引数量
    uint32_t vertex_count;       // 顶点数量（剔除用）
    
    // AABB（在 local space，用于 GPU 剔除）
    glm::vec3 aabb_min;
    float     pad0;
    glm::vec3 aabb_max;
    float     pad1;
};
```

### 3.2 Instance（实例数据）

```cpp
// 场景中每个对象实例
struct InstanceData {
    glm::mat4 transform;         // world transform
    uint32_t  mesh_id;           // 索引到 MeshDescriptor 数组
    uint32_t  material_id;       // 索引到 MaterialData 数组
    uint32_t  flags;             // bit 0: visible, bit 1: casts_shadow, ...
    uint32_t  pad;
};
```

### 3.3 Material（材质数据，Bindless）

```cpp
// 材质只存句柄，不存纹理本身
struct MaterialData {
    uint64_t albedo_handle;       // bindless texture handle
    uint64_t normal_handle;
    uint64_t roughness_handle;
    uint64_t emissive_handle;
    
    glm::vec4 base_color;
    float     roughness_factor;
    float     metallic_factor;
    uint32_t  flags;
    uint32_t  pad;
};
```

### 3.4 Draw Command（Indirect 命令）

Vulkan 规定的 indexed indirect draw 命令结构：

```cpp
// 对应 VkDrawIndexedIndirectCommand
struct DrawCommand {
    uint32_t index_count;
    uint32_t instance_count;  // 通常为 1（或 0 表示被剔除）
    uint32_t first_index;
    int32_t  vertex_offset;
    uint32_t first_instance;  // 同时作为 instance_id，shader 里用来读取 InstanceData
};
```

关键点：`first_instance` 被复用为 instance index，shader 里通过 `gl_BaseInstance`（GLSL）或 `BaseVertexLocation`（HLSL）读取，从而索引到对应的 `InstanceData`。

### 3.5 全局 Buffer 布局

```
GPU Memory:
┌─────────────────────────────────────────────────┐
│  Vertex Pool (所有 mesh 的顶点连续存储)           │
│  Index Pool  (所有 mesh 的索引连续存储)           │
│  MeshDescriptor[]  (mesh_count 个)               │
│  InstanceData[]    (instance_count 个)           │
│  MaterialData[]    (material_count 个)           │
│  DrawCommand[]     (max_draw_count 个，compute写) │
│  DrawCount         (uint32, compute atomic write) │
│  HZB (Hierarchical Z-Buffer, 用于遮挡剔除)       │
└─────────────────────────────────────────────────┘
```

------

## 4. Indirect Draw：CPU 让权的起点

### 4.1 Vulkan Indirect Draw API

Vulkan 提供以下 Indirect Draw 变体：

```cpp
// 固定 draw count
vkCmdDrawIndirect(cmd, buffer, offset, draw_count, stride);
vkCmdDrawIndexedIndirect(cmd, buffer, offset, draw_count, stride);

// 动态 draw count（count 也存在 GPU buffer 里）
// 需要 VK_KHR_draw_indirect_count 或 Vulkan 1.2
vkCmdDrawIndexedIndirectCount(
    cmd,
    indirect_buffer, indirect_offset,  // draw 命令所在 buffer
    count_buffer,    count_offset,      // draw count 所在 buffer
    max_draw_count,                     // 安全上限
    stride                              // sizeof(VkDrawIndexedIndirectCommand)
);
```

`DrawIndexedIndirectCount` 是 GPU-driven 的关键：draw count 由 GPU Compute 写入，CPU 完全不知道最终会执行多少次 draw，只给出上限保护。

### 4.2 Vulkan RAII：创建 Indirect Buffer

```cpp
#include <vulkan/vulkan_raii.hpp>

// ─── 辅助：创建 GPU buffer（简化示意，省略 allocator 层）───
struct Buffer {
    vk::raii::Buffer      buffer;
    vk::raii::DeviceMemory memory;
    void*                  mapped = nullptr;

    Buffer(const vk::raii::Device& device,
           const vk::raii::PhysicalDevice& physDevice,
           vk::DeviceSize size,
           vk::BufferUsageFlags usage,
           vk::MemoryPropertyFlags props)
        : buffer(nullptr), memory(nullptr)
    {
        // 创建 buffer
        vk::BufferCreateInfo bufCI{
            {}, size, usage, vk::SharingMode::eExclusive
        };
        buffer = device.createBuffer(bufCI);

        // 分配内存
        auto reqs = buffer.getMemoryRequirements();
        uint32_t memType = findMemoryType(physDevice, reqs.memoryTypeBits, props);
        vk::MemoryAllocateInfo allocInfo{ reqs.size, memType };
        memory = device.allocateMemory(allocInfo);
        buffer.bindMemory(*memory, 0);

        if (props & vk::MemoryPropertyFlagBits::eHostVisible)
            mapped = memory.mapMemory(0, size);
    }

    static uint32_t findMemoryType(const vk::raii::PhysicalDevice& pd,
                                   uint32_t filter, vk::MemoryPropertyFlags flags) {
        auto props = pd.getMemoryProperties();
        for (uint32_t i = 0; i < props.memoryTypeCount; i++)
            if ((filter & (1 << i)) &&
                (props.memoryTypes[i].propertyFlags & flags) == flags)
                return i;
        throw std::runtime_error("no suitable memory type");
    }
};

// ─── 创建 Indirect Command Buffer ───
Buffer createIndirectBuffer(const vk::raii::Device& device,
                            const vk::raii::PhysicalDevice& physDevice,
                            uint32_t maxDrawCount)
{
    vk::DeviceSize size = sizeof(VkDrawIndexedIndirectCommand) * maxDrawCount;

    return Buffer{
        device, physDevice, size,
        // INDIRECT_BUFFER：作为 indirect draw 源
        // STORAGE_BUFFER：Compute shader 写入
        // TRANSFER_DST：可从 staging buffer 初始化
        vk::BufferUsageFlagBits::eIndirectBuffer |
        vk::BufferUsageFlagBits::eStorageBuffer  |
        vk::BufferUsageFlagBits::eTransferDst,
        vk::MemoryPropertyFlagBits::eDeviceLocal   // GPU-local，最快
    };
}

// ─── 创建 Draw Count Buffer ───
Buffer createCountBuffer(const vk::raii::Device& device,
                         const vk::raii::PhysicalDevice& physDevice)
{
    return Buffer{
        device, physDevice,
        sizeof(uint32_t),
        vk::BufferUsageFlagBits::eIndirectBuffer |
        vk::BufferUsageFlagBits::eStorageBuffer  |
        vk::BufferUsageFlagBits::eTransferDst,
        vk::MemoryPropertyFlagBits::eDeviceLocal
    };
}
```

### 4.3 Vertex/Index 全局池

GPU-driven 的前提是所有 mesh 共享同一个 vertex buffer 和 index buffer（"Mega Mesh Buffer"），否则 indirect draw 无法索引不同 mesh。

```cpp
class MegaMeshBuffer {
public:
    Buffer vertex_buffer;
    Buffer index_buffer;
    
    uint32_t vertex_head = 0;  // 下一个可用顶点位置
    uint32_t index_head  = 0;  // 下一个可用索引位置
    
    struct Allocation {
        uint32_t vertex_offset;
        uint32_t index_offset;
        uint32_t vertex_count;
        uint32_t index_count;
    };
    
    MegaMeshBuffer(const vk::raii::Device& device,
                   const vk::raii::PhysicalDevice& physDevice,
                   uint32_t max_vertices,
                   uint32_t max_indices)
        : vertex_buffer(device, physDevice,
                        sizeof(Vertex) * max_vertices,
                        vk::BufferUsageFlagBits::eVertexBuffer |
                        vk::BufferUsageFlagBits::eStorageBuffer |
                        vk::BufferUsageFlagBits::eTransferDst,
                        vk::MemoryPropertyFlagBits::eDeviceLocal),
          index_buffer(device, physDevice,
                       sizeof(uint32_t) * max_indices,
                       vk::BufferUsageFlagBits::eIndexBuffer  |
                       vk::BufferUsageFlagBits::eStorageBuffer |
                       vk::BufferUsageFlagBits::eTransferDst,
                       vk::MemoryPropertyFlagBits::eDeviceLocal)
    {}
    
    // 上传一个 mesh，返回其在全局 pool 中的偏移
    Allocation upload(std::span<const Vertex>   vertices,
                      std::span<const uint32_t> indices,
                      UploadContext& ctx)
    {
        Allocation alloc{
            vertex_head, index_head,
            (uint32_t)vertices.size(),
            (uint32_t)indices.size()
        };
        ctx.upload(vertex_buffer.buffer, vertex_head * sizeof(Vertex), vertices);
        ctx.upload(index_buffer.buffer,  index_head  * sizeof(uint32_t), indices);
        vertex_head += (uint32_t)vertices.size();
        index_head  += (uint32_t)indices.size();
        return alloc;
    }
};
```

------

## 5. Compute Shader 作为 Command Generator

这是 GPU-driven 的心脏：一个 Compute shader，遍历所有实例，执行剔除测试，对通过的实例写入一条 `DrawIndexedIndirectCommand`。

### 5.1 Compute Shader（GLSL）

```glsl
// cull.comp
#version 450
#extension GL_KHR_shader_subgroup_ballot : enable

layout(local_size_x = 64) in;  // 每组 64 个线程

// ─── 场景数据输入 ───
layout(set = 0, binding = 0) readonly buffer InstanceBuffer {
    InstanceData instances[];
};
layout(set = 0, binding = 1) readonly buffer MeshBuffer {
    MeshDescriptor meshes[];
};
layout(set = 0, binding = 2) uniform CullUniforms {
    mat4  view_proj;
    vec4  frustum_planes[6];   // world-space frustum planes
    vec3  camera_pos;
    float near_plane;
    uint  instance_count;
    uint  pad[3];
};

// ─── 输出：indirect draw 命令 ───
layout(set = 0, binding = 3) writeonly buffer DrawCommandBuffer {
    DrawIndexedIndirectCommand draw_commands[];
};
layout(set = 0, binding = 4) buffer DrawCountBuffer {
    uint draw_count;
};

// ─── AABB frustum 剔除 ───
bool isVisible(in MeshDescriptor mesh, in mat4 transform) {
    // 把 AABB 8 个角点变换到 world space，检查是否在 frustum 内
    vec3 corners[8];
    corners[0] = vec3(mesh.aabb_min.x, mesh.aabb_min.y, mesh.aabb_min.z);
    corners[1] = vec3(mesh.aabb_max.x, mesh.aabb_min.y, mesh.aabb_min.z);
    corners[2] = vec3(mesh.aabb_min.x, mesh.aabb_max.y, mesh.aabb_min.z);
    corners[3] = vec3(mesh.aabb_max.x, mesh.aabb_max.y, mesh.aabb_min.z);
    corners[4] = vec3(mesh.aabb_min.x, mesh.aabb_min.y, mesh.aabb_max.z);
    corners[5] = vec3(mesh.aabb_max.x, mesh.aabb_min.y, mesh.aabb_max.z);
    corners[6] = vec3(mesh.aabb_min.x, mesh.aabb_max.y, mesh.aabb_max.z);
    corners[7] = vec3(mesh.aabb_max.x, mesh.aabb_max.y, mesh.aabb_max.z);

    for (int p = 0; p < 6; p++) {
        int outside = 0;
        for (int c = 0; c < 8; c++) {
            vec4 world_pos = transform * vec4(corners[c], 1.0);
            if (dot(frustum_planes[p], world_pos) < 0.0)
                outside++;
        }
        if (outside == 8) return false;  // AABB 完全在某个平面外侧
    }
    return true;
}

void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= instance_count) return;

    InstanceData inst = instances[idx];
    if ((inst.flags & 1u) == 0u) return;  // 标记为不可见

    MeshDescriptor mesh = meshes[inst.mesh_id];

    // ─── 执行剔除 ───
    bool visible = isVisible(mesh, inst.transform);

    if (visible) {
        // 原子递增，获取本 draw 的槽位
        uint slot = atomicAdd(draw_count, 1u);
        
        draw_commands[slot].indexCount    = mesh.index_count;
        draw_commands[slot].instanceCount = 1;
        draw_commands[slot].firstIndex    = mesh.index_offset;
        draw_commands[slot].vertexOffset  = int(mesh.vertex_offset);
        draw_commands[slot].firstInstance = idx;  // 传递 instance id 给 VS
    }
}
```

**注意 `firstInstance = idx`**：这是 GPU-driven 里传递 per-draw 数据的常用技巧。VS 里用 `gl_BaseInstance` 读取，再用它索引 InstanceData buffer 获取变换矩阵和材质 ID。

### 5.2 Vertex Shader 侧的配合

```glsl
// gbuffer.vert
#version 450

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec2 in_uv;

layout(set = 0, binding = 0) readonly buffer InstanceBuffer {
    InstanceData instances[];
};

layout(location = 0) out vec3 out_world_pos;
layout(location = 1) out vec3 out_normal;
layout(location = 2) out vec2 out_uv;
layout(location = 3) flat out uint out_material_id;

layout(push_constant) uniform PC {
    mat4 view_proj;
};

void main() {
    // gl_BaseInstance 对应 DrawCommand.firstInstance = instance_id
    InstanceData inst = instances[gl_BaseInstance];
    
    vec4 world_pos = inst.transform * vec4(in_position, 1.0);
    gl_Position    = view_proj * world_pos;
    
    out_world_pos   = world_pos.xyz;
    out_normal      = mat3(transpose(inverse(inst.transform))) * in_normal;
    out_uv          = in_uv;
    out_material_id = inst.material_id;
}
```

### 5.3 Vulkan RAII：Compute Pass 录制

```cpp
void recordCullPass(const vk::raii::CommandBuffer& cmd,
                    const CullResources& res,
                    uint32_t instanceCount)
{
    // ─── 重置 draw count 为 0（每帧开始前）───
    cmd.fillBuffer(*res.count_buffer.buffer, 0, sizeof(uint32_t), 0u);

    // ─── Buffer barrier：确保 fillBuffer 完成后 compute 才读 ───
    vk::BufferMemoryBarrier2 count_barrier{
        vk::PipelineStageFlagBits2::eTransfer,
        vk::AccessFlagBits2::eTransferWrite,
        vk::PipelineStageFlagBits2::eComputeShader,
        vk::AccessFlagBits2::eShaderRead | vk::AccessFlagBits2::eShaderWrite,
        VK_QUEUE_FAMILY_IGNORED, VK_QUEUE_FAMILY_IGNORED,
        *res.count_buffer.buffer, 0, sizeof(uint32_t)
    };
    vk::DependencyInfo dep_info{};
    dep_info.setBufferMemoryBarriers(count_barrier);
    cmd.pipelineBarrier2(dep_info);

    // ─── 绑定 Compute Pipeline ───
    cmd.bindPipeline(vk::PipelineBindPoint::eCompute, *res.cull_pipeline);
    cmd.bindDescriptorSets(vk::PipelineBindPoint::eCompute,
                           *res.cull_pipeline_layout, 0,
                           { *res.cull_descriptor_set }, {});

    // ─── Dispatch：每 64 个实例一组 ───
    uint32_t groups = (instanceCount + 63) / 64;
    cmd.dispatch(groups, 1, 1);

    // ─── Barrier：Compute 写完命令缓冲后，Draw 才能读 ───
    std::array<vk::BufferMemoryBarrier2, 2> draw_barriers{
        vk::BufferMemoryBarrier2{
            vk::PipelineStageFlagBits2::eComputeShader,
            vk::AccessFlagBits2::eShaderWrite,
            vk::PipelineStageFlagBits2::eDrawIndirect,
            vk::AccessFlagBits2::eIndirectCommandRead,
            VK_QUEUE_FAMILY_IGNORED, VK_QUEUE_FAMILY_IGNORED,
            *res.indirect_buffer.buffer, 0, VK_WHOLE_SIZE
        },
        vk::BufferMemoryBarrier2{
            vk::PipelineStageFlagBits2::eComputeShader,
            vk::AccessFlagBits2::eShaderWrite,
            vk::PipelineStageFlagBits2::eDrawIndirect,
            vk::AccessFlagBits2::eIndirectCommandRead,
            VK_QUEUE_FAMILY_IGNORED, VK_QUEUE_FAMILY_IGNORED,
            *res.count_buffer.buffer, 0, sizeof(uint32_t)
        }
    };
    dep_info.setBufferMemoryBarriers(draw_barriers);
    cmd.pipelineBarrier2(dep_info);
}

// ─── 执行 Indirect Draw ───
void recordDrawPass(const vk::raii::CommandBuffer& cmd,
                    const CullResources& res,
                    uint32_t maxDrawCount)
{
    cmd.bindVertexBuffers(0, { *res.mega_mesh.vertex_buffer.buffer }, { 0 });
    cmd.bindIndexBuffer(*res.mega_mesh.index_buffer.buffer, 0,
                        vk::IndexType::eUint32);
    
    // 一次 API 调用，GPU 执行所有通过剔除的 draw
    cmd.drawIndexedIndirectCount(
        *res.indirect_buffer.buffer, 0,         // command buffer
        *res.count_buffer.buffer, 0,            // count buffer
        maxDrawCount,                           // 上限
        sizeof(VkDrawIndexedIndirectCommand)    // stride
    );
}
```

### 5.4 Compute Pipeline 创建

```cpp
vk::raii::Pipeline createCullPipeline(
    const vk::raii::Device& device,
    const vk::raii::PipelineLayout& layout,
    const std::vector<uint32_t>& spirv)
{
    vk::ShaderModuleCreateInfo shaderCI{ {}, spirv };
    auto shader_module = device.createShaderModule(shaderCI);

    vk::PipelineShaderStageCreateInfo stageCI{
        {},
        vk::ShaderStageFlagBits::eCompute,
        *shader_module,
        "main"
    };

    vk::ComputePipelineCreateInfo pipelineCI{ {}, stageCI, *layout };
    auto [result, pipeline] = device.createComputePipeline(nullptr, pipelineCI);
    if (result != vk::Result::eSuccess)
        throw std::runtime_error("failed to create cull pipeline");
    return std::move(pipeline);
}
```

------

## 6. GPU 端剔除系统

GPU-driven 能发挥最大价值的关键在于多级剔除。每一级都过滤掉一批不需要渲染的对象，减少后续阶段的工作量。

### 6.1 视锥剔除（Frustum Culling）

上面的 Compute shader 已经展示了基础版本。更高效的方式是用 **sphere test** 代替 AABB，因为每个实例只需要一次 dot product 乘以 6 个平面：

```glsl
// 从 AABB 提取包围球（预计算，存在 MeshDescriptor 里）
bool sphereFrustumTest(vec3 center_world, float radius) {
    for (int i = 0; i < 6; i++) {
        if (dot(frustum_planes[i].xyz, center_world) + frustum_planes[i].w + radius < 0.0)
            return false;
    }
    return true;
}
```

**提取 Frustum Planes（CPU 端，每帧更新 uniform）：**

```cpp
// 从 ViewProj 矩阵直接提取 6 个平面（Gribb/Hartmann 方法）
std::array<glm::vec4, 6> extractFrustumPlanes(const glm::mat4& vp) {
    std::array<glm::vec4, 6> planes;
    // Left, Right, Bottom, Top, Near, Far
    for (int i = 0; i < 4; i++) {
        planes[0][i] = vp[i][3] + vp[i][0];  // left
        planes[1][i] = vp[i][3] - vp[i][0];  // right
        planes[2][i] = vp[i][3] + vp[i][1];  // bottom
        planes[3][i] = vp[i][3] - vp[i][1];  // top
        planes[4][i] = vp[i][3] + vp[i][2];  // near
        planes[5][i] = vp[i][3] - vp[i][2];  // far
    }
    // 归一化平面法线（使 distance 有物理意义）
    for (auto& p : planes) {
        float len = glm::length(glm::vec3(p));
        p /= len;
    }
    return planes;
}
```

### 6.2 背面剔除（Backface Culling on GPU）

对于凸体，可以在 Compute shader 里提前剔除完全背对相机的对象（所有面都背对）。这在密集场景（草地、岩石群）中效果显著：

```glsl
// 用包围球中心与相机的角度估算
bool backfaceCull(vec3 obj_center, vec3 obj_normal_avg, vec3 cam_pos) {
    vec3 dir = normalize(cam_pos - obj_center);
    // 如果包围球"正面"的平均法线完全背对相机，整体剔除
    return dot(dir, obj_normal_avg) > -0.95;
}
```

### 6.3 小三角形剔除（Small Triangle Culling）

当对象在屏幕上投影面积小于 1 像素（次像素三角形）时，光栅化器仍会处理它，但产生 0 个片元——纯粹浪费。GPU-driven 可以在 Compute 阶段通过投影包围球的屏幕空间半径过滤：

```glsl
bool smallTriangleCull(vec3 sphere_center_world, float sphere_radius,
                       mat4 proj, vec2 screen_size) {
    vec4 clip = view_proj * vec4(sphere_center_world, 1.0);
    
    // NDC 空间下包围球的投影半径
    float projected_radius = sphere_radius * proj[1][1] / clip.w;
    
    // 如果投影半径 < 0.5 像素，剔除（低于 1 像素）
    float screen_radius = projected_radius * screen_size.y * 0.5;
    return screen_radius >= 0.5;
}
```

### 6.4 距离/LOD 剔除

```glsl
// 根据距离选择 LOD 或直接剔除
int selectLOD(float dist, in MeshDescriptor mesh) {
    // mesh 存储了每个 LOD 的阈值距离
    for (int lod = 0; lod < MAX_LODS; lod++) {
        if (dist < mesh.lod_distances[lod])
            return lod;
    }
    return -1;  // -1 = 距离太远，剔除
}
```

当 LOD 选择结果为 -1 时，不写入 draw command，即隐式剔除。

------

## 7. 两趟式遮挡剔除与 HZB

视锥剔除只能过滤相机视野外的对象。对于被其他物体遮挡的对象（想象一堵墙后面的大量建筑），需要遮挡剔除（Occlusion Culling）。

### 7.1 Hierarchical Z-Buffer（HZB / Hi-Z）

HZB 是对深度缓冲的 Mipmap：

- **Mip 0**：完整分辨率深度缓冲
- **Mip 1**：2x2 块的最大深度（保守 = 不遮挡任何实际可见的东西）
- **Mip N**：每个 texel 覆盖 2^N × 2^N 像素区域内的最大深度

**剔除逻辑**：把对象的包围球投影到 HZB，读取对应 mip 层级的深度值。如果包围球的最近点深度 > HZB 采样深度，说明整个对象被遮挡。

```glsl
// HZB 遮挡剔除（在 Compute shader 中）
layout(set = 1, binding = 0) uniform sampler2D hzb;

bool occlusionCull(vec3 sphere_center, float sphere_radius, mat4 view_proj,
                   vec2 hzb_size) {
    // 投影到 NDC
    vec4 clip     = view_proj * vec4(sphere_center, 1.0);
    vec3 ndc      = clip.xyz / clip.w;
    
    // 包围球屏幕空间半径
    float proj_r  = sphere_radius / clip.w * view_proj[1][1];
    
    // 选择合适的 HZB mip（覆盖包围球的屏幕空间尺寸）
    float diameter_pixels = proj_r * hzb_size.y;
    float mip = ceil(log2(max(diameter_pixels, 1.0)));
    
    // 采样 HZB（最大深度 = 最保守）
    vec2 uv      = ndc.xy * 0.5 + 0.5;
    float hzb_z  = textureLod(hzb, uv, mip).r;
    
    // 包围球的最近点深度（距相机最近的面）
    // 在 Vulkan NDC 中 z 范围 [0,1]，clip.w 越小 = 越近
    float obj_z  = (clip.z - sphere_radius * view_proj[2][2]) / clip.w;
    
    // 如果对象最近点比 HZB 记录的最大深度还远，说明被遮挡
    return obj_z <= hzb_z;
}
```

### 7.2 两趟式渲染（Two-Pass Occlusion Culling）

单纯用当前帧的 HZB 会有一个鸡蛋问题：第一帧没有深度缓冲，无法剔除任何对象。解决方案是**使用上一帧的 HZB 做保守剔除**：

```
第 N 帧流程：

Pass 1（Early Pass）：
  ┌─ 使用上一帧 HZB 剔除（Compute）
  │  → 生成 DrawCommandBuffer_A（认为可见的对象）
  ├─ 渲染 DrawCommandBuffer_A → 生成 Depth Buffer N
  └─ 从 Depth Buffer N 生成 HZB_N

Pass 2（Late Pass）：
  ┌─ 使用 HZB_N 剔除所有在 Pass 1 中被剔除的对象（Compute）
  │  → 生成 DrawCommandBuffer_B（Pass 1 误剔除 / 新出现的对象）
  └─ 渲染 DrawCommandBuffer_B（叠加到 Pass 1 结果上）

下一帧 Pass 1 使用 HZB_N。
```

**Pass 1 误剔除的情况**：当相机快速移动，上一帧 HZB 无法代表当前帧遮挡关系，某些本应可见的对象可能被误剔除。Pass 2 用当前帧真实深度再次检验，弥补这一误差。

### 7.3 HZB 生成：Compute Shader

```glsl
// hzb_build.comp - 逐 mip 层级构建 HZB
#version 450
layout(local_size_x = 8, local_size_y = 8) in;

layout(set = 0, binding = 0) uniform sampler2D src_depth;
layout(set = 0, binding = 1, r32f) writeonly uniform image2D dst_hzb;

layout(push_constant) uniform PC {
    ivec2 src_size;
    ivec2 dst_size;
};

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(coord, dst_size))) return;

    // 读取 2x2 采样点，取最大（最保守）
    vec2 uv = (vec2(coord) + 0.5) / vec2(dst_size);
    vec2 texel = 1.0 / vec2(src_size);
    
    float d00 = texture(src_depth, uv + vec2(-texel.x, -texel.y) * 0.5).r;
    float d10 = texture(src_depth, uv + vec2( texel.x, -texel.y) * 0.5).r;
    float d01 = texture(src_depth, uv + vec2(-texel.x,  texel.y) * 0.5).r;
    float d11 = texture(src_depth, uv + vec2( texel.x,  texel.y) * 0.5).r;
    
    float max_depth = max(max(d00, d10), max(d01, d11));
    imageStore(dst_hzb, coord, vec4(max_depth));
}
```

每一层 mip 需要 dispatch 一次，或者使用 `SPV_AMD_shader_image_load_store_lod` / `GL_EXT_shader_image_load_formatted` 等扩展在单次 dispatch 内完成所有层级。

### 7.4 Vulkan RAII：HZB 纹理与视图

```cpp
struct HZB {
    vk::raii::Image        image;
    vk::raii::DeviceMemory memory;
    std::vector<vk::raii::ImageView> mip_views;  // 每个 mip 一个 view（compute 写入用）
    vk::raii::ImageView    full_view;             // 全 mip view（采样用）
    uint32_t               mip_count;
    vk::Extent2D           base_size;

    static HZB create(const vk::raii::Device& device,
                      const vk::raii::PhysicalDevice& physDevice,
                      vk::Extent2D depth_extent)
    {
        HZB hzb;
        hzb.base_size  = { depth_extent.width / 2, depth_extent.height / 2 };
        hzb.mip_count  = (uint32_t)std::floor(std::log2(
                              std::max(hzb.base_size.width, hzb.base_size.height))) + 1;

        vk::ImageCreateInfo imgCI{
            {},
            vk::ImageType::e2D,
            vk::Format::eR32Sfloat,          // 32-bit float depth
            { hzb.base_size.width, hzb.base_size.height, 1 },
            hzb.mip_count,
            1,
            vk::SampleCountFlagBits::e1,
            vk::ImageTiling::eOptimal,
            vk::ImageUsageFlagBits::eSampled |   // compute shader 读
            vk::ImageUsageFlagBits::eStorage     // compute shader 写各 mip
        };
        hzb.image  = device.createImage(imgCI);

        // 分配内存（省略，同 Buffer 的做法）
        // ...

        // 为每个 mip 创建独立 ImageView（compute 写入时需要指定 mip level）
        for (uint32_t mip = 0; mip < hzb.mip_count; mip++) {
            vk::ImageViewCreateInfo viewCI{
                {},
                *hzb.image,
                vk::ImageViewType::e2D,
                vk::Format::eR32Sfloat,
                {},
                { vk::ImageAspectFlagBits::eColor, mip, 1, 0, 1 }
            };
            hzb.mip_views.push_back(device.createImageView(viewCI));
        }

        // 全 mip view（sampler 读取，用于剔除采样）
        vk::ImageViewCreateInfo fullViewCI{
            {},
            *hzb.image,
            vk::ImageViewType::e2D,
            vk::Format::eR32Sfloat,
            {},
            { vk::ImageAspectFlagBits::eColor, 0, hzb.mip_count, 0, 1 }
        };
        hzb.full_view = device.createImageView(fullViewCI);

        return hzb;
    }
};
```

------

## 8. Bindless 资源系统

GPU-driven 中每个 draw 可能使用不同材质/纹理，如果每次 draw 都切换 descriptor set，就失去了批处理的意义。Bindless 让 shader 在运行时动态索引任意纹理。

### 8.1 Vulkan Descriptor Indexing

需要启用的特性（Vulkan 1.2 core，或 `VK_EXT_descriptor_indexing`）：

```cpp
vk::PhysicalDeviceDescriptorIndexingFeatures indexingFeatures{};
indexingFeatures.runtimeDescriptorArray              = VK_TRUE;
indexingFeatures.descriptorBindingPartiallyBound     = VK_TRUE;
indexingFeatures.descriptorBindingUpdateUnusedWhilePending = VK_TRUE;
indexingFeatures.descriptorBindingSampledImageUpdateAfterBind = VK_TRUE;
indexingFeatures.shaderSampledImageArrayNonUniformIndexing   = VK_TRUE;

vk::PhysicalDeviceFeatures2 features2{};
features2.pNext = &indexingFeatures;

vk::DeviceCreateInfo deviceCI{};
deviceCI.pNext = &features2;
// ...
```

### 8.2 创建 Bindless Descriptor Pool & Layout

```cpp
vk::raii::DescriptorPool createBindlessPool(const vk::raii::Device& device,
                                             uint32_t max_textures = 65536)
{
    std::array<vk::DescriptorPoolSize, 1> pool_sizes{{
        { vk::DescriptorType::eCombinedImageSampler, max_textures }
    }};
    
    vk::DescriptorPoolCreateInfo poolCI{
        vk::DescriptorPoolCreateFlagBits::eFreeDescriptorSet |
        vk::DescriptorPoolCreateFlagBits::eUpdateAfterBind,  // Bindless 必须
        1,          // max sets
        pool_sizes
    };
    return device.createDescriptorPool(poolCI);
}

vk::raii::DescriptorSetLayout createBindlessLayout(const vk::raii::Device& device,
                                                    uint32_t max_textures = 65536)
{
    vk::DescriptorSetLayoutBinding binding{
        0,                                          // binding
        vk::DescriptorType::eCombinedImageSampler,
        max_textures,                               // 数组大小（runtime array）
        vk::ShaderStageFlagBits::eAll,
        nullptr
    };
    
    // 每个 binding 的 flags
    vk::DescriptorBindingFlags bindingFlags =
        vk::DescriptorBindingFlagBits::ePartiallyBound |
        vk::DescriptorBindingFlagBits::eUpdateAfterBind |
        vk::DescriptorBindingFlagBits::eVariableDescriptorCount;
    
    vk::DescriptorSetLayoutBindingFlagsCreateInfo flagsCI{};
    flagsCI.setBindingFlags(bindingFlags);
    
    vk::DescriptorSetLayoutCreateInfo layoutCI{
        vk::DescriptorSetLayoutCreateFlagBits::eUpdateAfterBindPool,
        binding
    };
    layoutCI.pNext = &flagsCI;
    
    return device.createDescriptorSetLayout(layoutCI);
}
```

### 8.3 Fragment Shader 中的 Bindless 采样

```glsl
// gbuffer.frag
#version 450
#extension GL_EXT_nonuniform_qualifier : enable

layout(set = 1, binding = 0) uniform sampler2D textures[];  // bindless 数组

layout(set = 0, binding = 0) readonly buffer MaterialBuffer {
    MaterialData materials[];
};

layout(location = 0) in vec2 in_uv;
layout(location = 3) flat in uint in_material_id;

layout(location = 0) out vec4 out_albedo;
layout(location = 1) out vec4 out_normal;

void main() {
    MaterialData mat = materials[in_material_id];
    
    // nonuniformEXT 告诉 GPU 不同 thread 可能用不同 index
    // 不加的话 GPU 可能错误地将 index 视为 uniform，产生未定义行为
    uint albedo_idx    = mat.albedo_handle;
    uint normal_idx    = mat.normal_handle;
    
    vec4 albedo = texture(textures[nonuniformEXT(albedo_idx)], in_uv);
    vec3 normal = texture(textures[nonuniformEXT(normal_idx)], in_uv).xyz * 2.0 - 1.0;
    
    out_albedo = albedo;
    out_normal = vec4(normalize(normal), 1.0);
}
```

### 8.4 动态注册纹理

```cpp
class BindlessRegistry {
    vk::raii::DescriptorPool       pool;
    vk::raii::DescriptorSetLayout  layout;
    vk::raii::DescriptorSet        set;
    uint32_t                       next_slot = 0;

public:
    uint32_t registerTexture(const vk::raii::Device& device,
                              vk::ImageView view,
                              vk::Sampler   sampler)
    {
        uint32_t slot = next_slot++;
        
        vk::DescriptorImageInfo imgInfo{
            sampler, view, vk::ImageLayout::eShaderReadOnlyOptimal
        };
        vk::WriteDescriptorSet write{
            *set, 0,        // set, binding
            slot, 1,        // arrayElement, count
            vk::DescriptorType::eCombinedImageSampler,
            &imgInfo
        };
        device.updateDescriptorSets(write, nullptr);
        
        return slot;  // 返回 slot index，存入 MaterialData.albedo_handle
    }
};
```

------

## 9. Mesh Shader 与 Meshlet

Mesh Shader Pipeline 是对传统 IA（Input Assembly）→ VS → GS 流程的彻底重写，提供了一个完整的"几何生成 + 剔除"编程模型。

### 9.1 传统 VS 的局限

传统顶点着色器受 Input Assembly 约束：

- 必须以 index buffer + vertex buffer 的形式提交
- 无法在 VS 内部剔除整个三角形组
- LOD 切换需要换绑 vertex/index buffer

### 9.2 Meshlet：Mesh 的分块单元

Meshlet 是将一个 mesh 预切分的小片段，通常每个 meshlet 包含：

- **64–128 个顶点**
- **64–126 个三角形**（或更少，受约束于 meshlet shader 的 output 限制）

每个 meshlet 有自己的包围球和锥形剔除数据，允许在 **Task Shader（扩增着色器）** 阶段做 per-meshlet 剔除，粒度远比 per-object 精细。

```cpp
// CPU 端 Meshlet 数据结构
struct Meshlet {
    uint32_t vertex_offset;   // 在 meshlet 顶点索引池中的起始位置
    uint32_t triangle_offset; // 在 meshlet 三角形索引池中的起始位置
    uint32_t vertex_count;
    uint32_t triangle_count;
    
    // 剔除数据
    glm::vec3 bounding_sphere_center;  // local space
    float     bounding_sphere_radius;
    glm::vec3 cone_apex;               // 锥形剔除（法线锥）
    glm::vec3 cone_axis;
    float     cone_cutoff;             // cos(半角)
};
```

**Meshlet 生成**可以使用 `meshoptimizer` 库：

```cpp
#include <meshoptimizer.h>

std::vector<Meshlet> buildMeshlets(std::span<const Vertex>   vertices,
                                   std::span<const uint32_t> indices)
{
    const size_t max_vertices  = 64;
    const size_t max_triangles = 124;
    const float  cone_weight   = 0.5f;  // 法线锥剔除权重

    size_t max_meshlets = meshopt_buildMeshletsBound(
        indices.size(), max_vertices, max_triangles);
    
    std::vector<meshopt_Meshlet> raw_meshlets(max_meshlets);
    std::vector<uint32_t>        meshlet_vertices(max_meshlets * max_vertices);
    std::vector<uint8_t>         meshlet_triangles(max_meshlets * max_triangles * 3);

    size_t meshlet_count = meshopt_buildMeshlets(
        raw_meshlets.data(),
        meshlet_vertices.data(),
        meshlet_triangles.data(),
        indices.data(), indices.size(),
        &vertices[0].pos.x, vertices.size(), sizeof(Vertex),
        max_vertices, max_triangles, cone_weight);
    
    // 转换为引擎格式并生成包围球/法线锥
    std::vector<Meshlet> result;
    for (size_t i = 0; i < meshlet_count; i++) {
        auto& rm = raw_meshlets[i];
        meshopt_Bounds bounds = meshopt_computeMeshletBounds(
            &meshlet_vertices[rm.vertex_offset],
            &meshlet_triangles[rm.triangle_offset],
            rm.triangle_count,
            &vertices[0].pos.x, vertices.size(), sizeof(Vertex));
        
        Meshlet m;
        m.vertex_offset   = rm.vertex_offset;
        m.triangle_offset = rm.triangle_offset;
        m.vertex_count    = rm.vertex_count;
        m.triangle_count  = rm.triangle_count;
        m.bounding_sphere_center = { bounds.center[0], bounds.center[1], bounds.center[2] };
        m.bounding_sphere_radius = bounds.radius;
        m.cone_apex   = { bounds.cone_apex[0], bounds.cone_apex[1], bounds.cone_apex[2] };
        m.cone_axis   = { bounds.cone_axis[0], bounds.cone_axis[1], bounds.cone_axis[2] };
        m.cone_cutoff = bounds.cone_cutoff;
        result.push_back(m);
    }
    return result;
}
```

### 9.3 Task Shader（Amplification Shader）

Task Shader 相当于旧有 GPU-driven 里 Compute 生成 draw command 的角色，但直接集成在渲染管线中：

```glsl
// task.glsl (GLSL with GL_EXT_mesh_shader)
#version 450
#extension GL_EXT_mesh_shader : require

layout(local_size_x = 32) in;  // 每个 workgroup 处理 32 个 meshlet

// 传递给 Mesh Shader 的 payload
struct TaskPayload {
    uint meshlet_indices[32];  // 通过剔除的 meshlet 的索引
};
taskPayloadSharedEXT TaskPayload payload;

layout(set = 0, binding = 0) readonly buffer MeshletBuffer {
    Meshlet meshlets[];
};
layout(set = 0, binding = 1) readonly buffer InstanceBuffer {
    InstanceData instances[];
};
layout(push_constant) uniform PC {
    uint  meshlet_count;
    uint  instance_id;
    mat4  view_proj;
    vec3  camera_pos;
};

void main() {
    uint local_id  = gl_LocalInvocationID.x;
    uint meshlet_id = gl_WorkGroupID.x * 32 + local_id;
    
    uint visible = 0u;
    if (meshlet_id < meshlet_count) {
        Meshlet m  = meshlets[meshlet_id];
        mat4 model = instances[instance_id].transform;
        
        // 1. 包围球 frustum 剔除
        vec3 world_center = (model * vec4(m.bounding_sphere_center, 1.0)).xyz;
        bool in_frustum   = sphereFrustumTest(world_center, m.bounding_sphere_radius);
        
        // 2. 背面锥形剔除（Cone Culling）
        //    如果相机在法线锥的"背面"，整个 meshlet 背对相机
        vec3 world_apex = (model * vec4(m.cone_apex, 1.0)).xyz;
        vec3 world_axis = normalize(mat3(model) * m.cone_axis);
        vec3 dir_to_cam = normalize(camera_pos - world_apex);
        bool front_face = dot(dir_to_cam, world_axis) > m.cone_cutoff;
        
        visible = (in_frustum && front_face) ? 1u : 0u;
    }
    
    // 通过 subgroup ballot 收集哪些 meshlet 通过了剔除
    // （避免 atomic + 保持 coherent 的 payload 写入）
    uvec4 ballot = subgroupBallot(visible == 1u);
    uint  count  = subgroupBallotBitCount(ballot);
    uint  index  = subgroupBallotExclusiveBitCount(ballot);
    
    if (visible == 1u)
        payload.meshlet_indices[index] = meshlet_id;
    
    // emit 给 Mesh Shader 的 workgroup 数量 = 通过剔除的 meshlet 数量
    EmitMeshTasksEXT(count, 1, 1);
}
```

### 9.4 Mesh Shader

```glsl
// mesh.glsl
#version 450
#extension GL_EXT_mesh_shader : require

// 每个 Mesh Shader workgroup 处理一个 meshlet
layout(local_size_x = 64) in;  // 最多 64 个顶点

// 输出：最多 64 顶点，124 三角形
layout(triangles, max_vertices = 64, max_primitives = 124) out;

struct TaskPayload {
    uint meshlet_indices[32];
};
taskPayloadSharedEXT TaskPayload payload;

// 输出到 fragment shader
layout(location = 0) out vec3 out_world_pos[];
layout(location = 1) out vec3 out_normal[];
layout(location = 2) out vec2 out_uv[];
layout(location = 3) flat out uint out_material_id[];

layout(set = 0, binding = 0) readonly buffer MeshletBuffer {
    Meshlet meshlets[];
};
layout(set = 0, binding = 1) readonly buffer MeshletVertexBuffer {
    uint meshlet_vertex_indices[];  // 指向全局顶点池的索引
};
layout(set = 0, binding = 2) readonly buffer MeshletTriangleBuffer {
    uint8_t meshlet_tri_indices[];  // 每个三角形 3 个字节，索引到 meshlet 内顶点
};
layout(set = 0, binding = 3) readonly buffer VertexBuffer {
    Vertex vertices[];
};
layout(set = 0, binding = 4) readonly buffer InstanceBuffer {
    InstanceData instances[];
};
layout(push_constant) uniform PC {
    mat4 view_proj;
    uint instance_id;
};

void main() {
    uint meshlet_id = payload.meshlet_indices[gl_WorkGroupID.x];
    Meshlet m = meshlets[meshlet_id];
    
    SetMeshOutputsEXT(m.vertex_count, m.triangle_count);
    
    mat4 model = instances[instance_id].transform;
    
    // 处理顶点（每个线程处理一个顶点）
    if (gl_LocalInvocationID.x < m.vertex_count) {
        uint vi      = meshlet_vertex_indices[m.vertex_offset + gl_LocalInvocationID.x];
        Vertex vert  = vertices[vi];
        
        vec4 world_pos    = model * vec4(vert.pos, 1.0);
        gl_MeshVerticesEXT[gl_LocalInvocationID.x].gl_Position = view_proj * world_pos;
        
        out_world_pos  [gl_LocalInvocationID.x] = world_pos.xyz;
        out_normal     [gl_LocalInvocationID.x] = mat3(model) * vert.normal;
        out_uv         [gl_LocalInvocationID.x] = vert.uv;
        out_material_id[gl_LocalInvocationID.x] = instances[instance_id].material_id;
    }
    
    // 处理三角形（每个线程处理一个三角形）
    if (gl_LocalInvocationID.x < m.triangle_count) {
        uint ti = m.triangle_offset + gl_LocalInvocationID.x * 3;
        gl_PrimitiveTriangleIndicesEXT[gl_LocalInvocationID.x] = uvec3(
            meshlet_tri_indices[ti    ],
            meshlet_tri_indices[ti + 1],
            meshlet_tri_indices[ti + 2]
        );
    }
}
```

### 9.5 Vulkan RAII：Mesh Shader Pipeline 创建

```cpp
vk::raii::Pipeline createMeshPipeline(
    const vk::raii::Device&         device,
    const vk::raii::PipelineLayout& layout,
    const vk::raii::RenderPass&     render_pass,
    const std::vector<uint32_t>&    task_spirv,
    const std::vector<uint32_t>&    mesh_spirv,
    const std::vector<uint32_t>&    frag_spirv)
{
    auto task_module = device.createShaderModule({{ }, task_spirv});
    auto mesh_module = device.createShaderModule({{ }, mesh_spirv});
    auto frag_module = device.createShaderModule({{ }, frag_spirv});
    
    std::array<vk::PipelineShaderStageCreateInfo, 3> stages{{
        { {}, vk::ShaderStageFlagBits::eTaskEXT,     *task_module, "main" },
        { {}, vk::ShaderStageFlagBits::eMeshEXT,     *mesh_module, "main" },
        { {}, vk::ShaderStageFlagBits::eFragment,    *frag_module, "main" }
    }};
    
    // Mesh Shader Pipeline 没有 VertexInputState 和 InputAssemblyState
    vk::PipelineRasterizationStateCreateInfo raster{
        {}, VK_FALSE, VK_FALSE,
        vk::PolygonMode::eFill,
        vk::CullModeFlagBits::eBack,
        vk::FrontFace::eCounterClockwise,
        VK_FALSE, 0, 0, 0, 1.0f
    };
    
    vk::PipelineMultisampleStateCreateInfo ms{ {}, vk::SampleCountFlagBits::e1 };
    
    vk::PipelineDepthStencilStateCreateInfo depth{
        {}, VK_TRUE, VK_TRUE, vk::CompareOp::eLess
    };
    
    vk::PipelineColorBlendAttachmentState blend_att{
        VK_FALSE, {}, {}, {}, {}, {}, {},
        vk::ColorComponentFlagBits::eR | vk::ColorComponentFlagBits::eG |
        vk::ColorComponentFlagBits::eB | vk::ColorComponentFlagBits::eA
    };
    vk::PipelineColorBlendStateCreateInfo blend{ {}, VK_FALSE, {}, blend_att };
    
    vk::GraphicsPipelineCreateInfo pipelineCI{
        {},
        stages,
        nullptr,  // 无 VertexInput
        nullptr,  // 无 InputAssembly
        nullptr,  // 无 Tessellation
        nullptr,  // ViewportState（需要补充）
        &raster,
        &ms,
        &depth,
        &blend,
        nullptr,
        *layout,
        *render_pass,
        0
    };
    
    auto [result, pipeline] = device.createGraphicsPipeline(nullptr, pipelineCI);
    return std::move(pipeline);
}
```

------

## 10. 完整帧流程串联

一个完整的 GPU-driven G-Buffer 帧流程（延迟渲染）：

```
每帧：
┌───────────────────────────────────────────────────────────────┐
│ CPU（极少工作）                                                 │
│  1. 更新 Camera UBO（view matrix, frustum planes）             │
│  2. 更新 InstanceData（移动的对象的 transform）                 │
│  3. 提交命令缓冲（可预录制，每帧只改少量 push constant）         │
└───────────────────────────────────────────────────────────────┘
            │
            ▼
┌───────────────────────────────────────────────────────────────┐
│ GPU：Pass 1 - Early Cull（Compute）                            │
│  in:  InstanceData[], MeshDescriptor[], HZB(last frame)        │
│  out: DrawCommandBuffer_A[], DrawCount_A                       │
│  做：frustum cull + HZB occlusion cull（上帧深度）              │
└───────────────────────────────────────────────────────────────┘
            │
            ▼  barrier: storage write → indirect read
┌───────────────────────────────────────────────────────────────┐
│ GPU：Pass 1 - Early Draw（Graphics）                           │
│  vkCmdDrawIndexedIndirectCount(DrawCommandBuffer_A, DrawCount_A)│
│  → GBuffer (albedo, normal, material_id, depth)               │
└───────────────────────────────────────────────────────────────┘
            │
            ▼
┌───────────────────────────────────────────────────────────────┐
│ GPU：HZB Build（Compute，多个 dispatch）                        │
│  in:  depth attachment from Pass 1                             │
│  out: HZB mip chain (HZB_current)                             │
└───────────────────────────────────────────────────────────────┘
            │
            ▼
┌───────────────────────────────────────────────────────────────┐
│ GPU：Pass 2 - Late Cull（Compute）                             │
│  in:  Pass 1 剔除掉的 instance，HZB_current                    │
│  out: DrawCommandBuffer_B[], DrawCount_B                       │
│  做：用当前帧真实深度再次检验被 Pass 1 误剔除的对象              │
└───────────────────────────────────────────────────────────────┘
            │
            ▼
┌───────────────────────────────────────────────────────────────┐
│ GPU：Pass 2 - Late Draw（Graphics）                            │
│  vkCmdDrawIndexedIndirectCount(DrawCommandBuffer_B, DrawCount_B)│
│  → 叠加到同一 GBuffer（继续写入，depth test 保护正确性）         │
└───────────────────────────────────────────────────────────────┘
            │
            ▼
┌───────────────────────────────────────────────────────────────┐
│ GPU：Lighting Pass（Compute 或 Graphics）                      │
│  读取 GBuffer → 计算光照 → 写入 HDR buffer                     │
│  shadow map 查询、SSR、AO 等效果在此阶段                        │
└───────────────────────────────────────────────────────────────┘
            │
            ▼
┌───────────────────────────────────────────────────────────────┐
│ GPU：Post-Process → Swapchain Present                          │
└───────────────────────────────────────────────────────────────┘
```

### 帧流程的命令录制

```cpp
void recordFrame(const vk::raii::CommandBuffer& cmd, FrameData& frame) {
    cmd.begin({ vk::CommandBufferUsageFlagBits::eOneTimeSubmit });
    
    // 1. 更新 per-frame uniform（camera）
    updateCameraUBO(cmd, frame);
    
    // 2. Pass 1 Cull
    {
        // 重置 count buffer
        cmd.fillBuffer(*frame.draw_count_A.buffer, 0, 4, 0u);
        pipelineBarrier_TransferToCompute(cmd, frame.draw_count_A);
        
        cmd.bindPipeline(vk::PipelineBindPoint::eCompute, *cull_pipeline);
        cmd.bindDescriptorSets(vk::PipelineBindPoint::eCompute,
                               *cull_layout, 0, { *frame.cull_set_A }, {});
        cmd.dispatch((instance_count + 63) / 64, 1, 1);
        
        pipelineBarrier_ComputeToIndirect(cmd, frame.draw_cmd_A, frame.draw_count_A);
    }
    
    // 3. Pass 1 Draw（G-Buffer）
    {
        beginGBuffer(cmd, frame.gbuffer);
        cmd.bindPipeline(vk::PipelineBindPoint::eGraphics, *gbuffer_pipeline);
        cmd.bindDescriptorSets(vk::PipelineBindPoint::eGraphics,
                               *gbuffer_layout, 0, { *frame.scene_set, *bindless_set }, {});
        cmd.bindVertexBuffers(0, { *mega_mesh.vb.buffer }, { 0 });
        cmd.bindIndexBuffer(*mega_mesh.ib.buffer, 0, vk::IndexType::eUint32);
        
        cmd.drawIndexedIndirectCount(
            *frame.draw_cmd_A.buffer, 0,
            *frame.draw_count_A.buffer, 0,
            MAX_DRAWS,
            sizeof(VkDrawIndexedIndirectCommand));
        
        endGBuffer(cmd);
    }
    
    // 4. HZB Build
    buildHZB(cmd, frame.gbuffer.depth, frame.hzb_current);
    
    // 5. Pass 2 Cull + Draw（类似 Pass 1，略）
    // ...
    
    // 6. Lighting
    lightingPass(cmd, frame);
    
    // 7. Post-process + present
    postProcess(cmd, frame);
    
    cmd.end();
}
```

------

## 11. GPU Scene：场景数据的 GPU 侧管理

### 11.1 Scene Buffer 的更新策略

并非每帧都要上传所有实例数据。高效的做法是 **Dirty-flag + Streaming Upload**：

```cpp
class GPUScene {
    Buffer   instance_buffer;    // 全量实例数据（device local）
    Buffer   staging_buffer;     // 上传用 staging（host visible）
    
    std::vector<InstanceData> cpu_instances;
    std::vector<uint32_t>     dirty_indices;  // 本帧修改的实例

public:
    void markDirty(uint32_t instance_id) {
        dirty_indices.push_back(instance_id);
    }
    
    void flushUploads(const vk::raii::CommandBuffer& cmd) {
        if (dirty_indices.empty()) return;
        
        // 批量上传脏实例（可以合并连续区间为一次 copyBuffer）
        for (uint32_t idx : dirty_indices) {
            size_t offset = idx * sizeof(InstanceData);
            memcpy((char*)staging_buffer.mapped + offset,
                   &cpu_instances[idx], sizeof(InstanceData));
            
            vk::BufferCopy copy{ offset, offset, sizeof(InstanceData) };
            cmd.copyBuffer(*staging_buffer.buffer, *instance_buffer.buffer, copy);
        }
        dirty_indices.clear();
        
        // barrier：transfer → compute shader read
        vk::BufferMemoryBarrier2 barrier{
            vk::PipelineStageFlagBits2::eTransfer,
            vk::AccessFlagBits2::eTransferWrite,
            vk::PipelineStageFlagBits2::eComputeShader,
            vk::AccessFlagBits2::eShaderRead,
            VK_QUEUE_FAMILY_IGNORED, VK_QUEUE_FAMILY_IGNORED,
            *instance_buffer.buffer, 0, VK_WHOLE_SIZE
        };
        vk::DependencyInfo dep{};
        dep.setBufferMemoryBarriers(barrier);
        cmd.pipelineBarrier2(dep);
    }
};
```

### 11.2 可见性历史（Temporal Coherence）

利用帧间时间连续性：记录上一帧每个实例的可见性结果，下一帧优先处理上帧可见的实例（"历史可见集合"），这类实例很可能本帧仍然可见，可以跳过复杂的剔除测试。

```cpp
// GPU 端：输出可见性 mask
layout(set = 0, binding = 5) buffer VisibilityBuffer {
    uint visibility[];  // bit per instance
};

// Compute shader 末尾：
if (visible)
    atomicOr(visibility[idx / 32], 1u << (idx % 32));
else
    atomicAnd(visibility[idx / 32], ~(1u << (idx % 32)));
```

------

## 12. Virtual Geometry：Nanite 的核心思路

UE5 Nanite 是 GPU-driven 的极致形态，核心是**无限细节的虚拟几何**。以下是其关键思路（非官方实现）：

### 12.1 Cluster DAG（有向无环图）

Nanite 不使用传统 LOD（简单地替换低多边形模型），而是将 mesh 预处理为**Cluster Hierarchy（DAG）**：

```
原始 mesh（数百万三角形）
  └─ Cluster Group（若干 cluster 合并简化）
       └─ Cluster Group（继续合并简化）
            └─ ...（直到整体只剩几十个三角形）

每层 cluster group：
  - 包含若干个精细 cluster（子节点）
  - 自身是子节点的简化版本（粗糙表示）
  - 边界误差：从此层切换带来的屏幕误差估计
```

渲染时，从根节点开始遍历 DAG：

- 如果当前节点的屏幕误差 < 阈值（1像素），使用当前节点的 cluster 渲染
- 否则，展开为子节点继续判断

这样每个像素永远不会有超过 1 个三角形的误差，同时自动适配距离。

### 12.2 Streaming

Nanite 的 cluster 数据可以流式加载：

- 只有视野内且当前 LOD 层级需要的 cluster page 才驻留 GPU
- Page fault（缺页）时回退到更粗糙的父节点层级（已常驻）
- 后台异步从磁盘加载精细层级

### 12.3 Visibility Buffer（软件光栅化）

Nanite 不使用传统 G-Buffer（存储大量中间数据），而是：

1. **硬件光栅化**：绘制较大三角形（每三角形覆盖 ≥1 像素）
2. **软件光栅化（Compute）**：绘制次像素到小三角形，效率远高于硬件光栅器

两者都写入一张 **Visibility Buffer**（64-bit per pixel）：

- 高 32 位：Instance ID
- 低 32 位：Triangle ID（在 cluster 内的序号）

然后在 Shading Pass 里按需读取材质属性：

```glsl
// shading pass
uint64_t vis = visibility_buffer[pixel];
uint instance_id  = uint(vis >> 32);
uint triangle_id  = uint(vis & 0xFFFFFFFF);

// 重建重心坐标插值
BarycentricCoords bary = computeBarycentric(instance_id, triangle_id, pixel);
MaterialData mat = materials[instances[instance_id].material_id];
vec4 albedo = texture(textures[mat.albedo_handle], interpolate(bary, uvs));
```

这种方案的好处：**只对最终可见的像素执行一次 shade**，彻底消除 overdraw 的 shader 计算浪费。

------

## 13. 现代引擎实现参考

### Unreal Engine 5（Nanite + Lumen）

| 组件     | 实现方式                                                    |
| -------- | ----------------------------------------------------------- |
| Nanite   | Cluster DAG + Visibility Buffer + 软件光栅化                |
| 剔除     | Instance cull → Cluster cull → Triangle cull，全在 Compute  |
| Bindless | Descriptor Heap（DX12）/ Bindless（Vulkan）                 |
| 光照     | Lumen：Software Raytracing on SDF + Hardware RT             |
| 命令生成 | `ExecuteIndirect`（DX12）/ `DrawIndexedIndirectCount`（VK） |

### id Software（id Tech 7，DOOM Eternal/The Dark Ages）

- **Mega Geometry**：所有场景 mesh 驻留单一 buffer
- **GPU-driven cluster pipeline**：Mesh Shader（Task + Mesh）
- **Two-pass HZB occlusion**（经典实现，id 公开讲解过）
- **Bindless material**：每帧零 descriptor set switch

### Unity（BatchRendererGroup / DOTS Renderer）

- `BatchRendererGroup` API 允许开发者在 Compute shader 里生成 draw 命令
- `GPUResidentDrawer`：自动管理实例上传 + Indirect Draw
- 与 DOTS（Data-Oriented Technology Stack）结合，LOD 选择、剔除均在 Job System + Compute 上完成

### Lumberyard / O3DE

- Meshlet-based rendering
- 每个 LOD 细分为 meshlet，Task Shader 做 per-meshlet 剔除
- Virtual texture streaming 与 GPU-driven 结合

------

## 14. 性能分析与常见陷阱

### 14.1 AtomicAdd 竞争

`atomicAdd(draw_count, 1)` 在大量线程同时执行时可能产生竞争，虽然原子操作本身正确，但**并发原子操作的延迟**会成为瓶颈（所有线程序列化写入同一地址）。

**解决方案**：使用 subgroup 操作批量收集，只做一次 atomic：

```glsl
// 用 subgroup ballot 统计本 subgroup 内通过剔除的线程数
uvec4 ballot    = subgroupBallot(visible);
uint  group_cnt = subgroupBallotBitCount(ballot);
uint  local_idx = subgroupBallotExclusiveBitCount(ballot);

// 只有 subgroup 内第一个线程做原子加法，获取 base slot
uint base_slot = 0u;
if (subgroupElect())
    base_slot = atomicAdd(draw_count, group_cnt);
base_slot = subgroupBroadcastFirst(base_slot);  // 广播给 subgroup 内所有线程

// 每个通过剔除的线程写到 base_slot + local_idx
if (visible)
    writeDrawCommand(base_slot + local_idx, ...);
```

原子操作次数从 O(visible_count) 降为 O(visible_count / subgroup_size)。

### 14.2 Draw Command Buffer 排序与 State Switching

Indirect draw 执行顺序由 buffer 内命令顺序决定。如果不同 pipeline state 的 draw 混排，需要在 GPU 端先对命令排序（按 pipeline/material 分组），否则每次 pipeline barrier 都会打断 batch。

常见做法：**多个 indirect buffer，每个 buffer 对应一种 pipeline/material group**，Compute 按 material 的 pipeline key 分类写入。

### 14.3 HZB 时间性误差

- 相机突然快速旋转：上帧 HZB 几乎无效，Pass 1 几乎不剔除任何对象，Pass 2 承担所有工作 → 帧时间峰值
- 高速移动的大型遮挡物消失：本帧深度变浅，Pass 2 剔除补救，但已进入 Pass 1 的对象仍会渲染 → 轻微过绘制（acceptable）

### 14.4 Count Buffer 的 Memory Hazard

`fillBuffer` 清零 → Compute 写入 → `DrawIndirectCount` 读取，这三个阶段必须有正确的 barrier 顺序，漏掉任何一个都会导致 GPU 读到上帧的 count 值，产生闪烁或崩溃。

建议在调试阶段启用 `VK_LAYER_KHRONOS_validation` 的 synchronization validation，可以检测出绝大多数此类 hazard：

```cpp
VkValidationFeaturesEXT val_features{};
val_features.sType = VK_STRUCTURE_TYPE_VALIDATION_FEATURES_EXT;
VkValidationFeatureEnableEXT enables[] = {
    VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT
};
val_features.enabledValidationFeatureCount = 1;
val_features.pEnabledValidationFeatures    = enables;
```

### 14.5 Mesh Shader 的 Warp 效率

Task shader 每个 workgroup 处理 N 个 meshlet，如果通过剔除的 meshlet 不均匀，`EmitMeshTasksEXT(count)` 发出的 Mesh Shader workgroup 数量差异大，可能导致 GPU 利用率低。

经验规则：Task Shader local_size 选 32（与 warp/wavefront 大小对齐），充分利用 subgroup 操作。

### 14.6 Shader 中的非均匀索引

Bindless 的 `textures[nonuniformEXT(idx)]` 如果漏写 `nonuniformEXT`，在某些 GPU 上会只使用 subgroup 内第一个线程的 index，导致所有像素采样同一张纹理（极难排查的视觉 bug）。

------

## 总结

GPU-driven rendering 的本质是**一次思维模式的转变**：从"CPU 描述每帧做什么"到"GPU 自己决定做什么"。

其技术路径可归纳为：

```
Mega Buffer（统一管理所有几何数据）
    +
Compute Culling（GPU 端多级剔除）
    +
Indirect Draw（CPU 零决策的 draw 提交）
    +
Bindless（消除材质切换开销）
    =
GPU-Driven Core

    ↓ 进一步
Mesh Shader（消除 IA 约束，per-meshlet 剔除）
    +
Visibility Buffer（消除 overdraw shader 浪费）
    +
Virtual Geometry Streaming（无限细节）
    =
Next-Gen GPU-Driven（Nanite 路线）
```

每一层技术都建立在前一层的基础上，理解了 Indirect Draw 的原理，自然理解为什么需要 Compute 来生成命令；理解了 Compute 剔除，自然理解 HZB 是对它的精度提升；理解了 HZB 的局限，自然理解为什么 Meshlet + Task Shader 是更细粒度的解法。

整个 GPU-driven 体系的终极目标只有一个：**让 GPU 的每一个 ALU 周期都用在产生最终图像上，而不是浪费在剔除失败的三角形、过多的驱动层调用或错误的状态切换上**。