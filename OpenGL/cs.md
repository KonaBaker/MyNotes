**invocation**

最小的执行单位，代表这激素均按着色器的一次执行。

```gl_GlobalInvocationID```唯一的全局ID

**local_size**

```layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;```

定义单个**工作组**内的invocation数量。

**work_group**

工作组。是gpu调度的基本单位

同一个工作组内的invocation可以

- 共享本地内存
- 使用barrier
- 通过```gl_LocalInvocationID```访问组内位置

**global_size**
整个计算任务的总尺寸，指定工作组的数量

```glDispatchCompute(num_groups_x, num_groups_y, num_groups_z)```

```
全局尺寸 = 工作组数量 × 本地尺寸

global_size_x = num_groups_x × local_size_x
global_size_y = num_groups_y × local_size_y  
global_size_z = num_groups_z × local_size_z
```

```
// 工作组相关
gl_WorkGroupSize     // 本地尺寸 (local_size_x, local_size_y, local_size_z)
gl_WorkGroupID       // 当前工作组的ID
gl_NumWorkGroups     // 工作组总数

// Invocation相关
gl_LocalInvocationID    // 工作组内的本地ID (0到local_size-1)
gl_GlobalInvocationID   // 全局ID = gl_WorkGroupID * gl_WorkGroupSize + gl_LocalInvocationID
```

