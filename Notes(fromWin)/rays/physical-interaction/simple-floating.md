# simple-floating

主要文件：

- source-physical-interaction/service/simple-floating-object-service.hpp[cpp]

这里主要介绍浮力计算的部分。

| Simple Floating Object   | Simple Floating Object | Object Path            | string    | /                                  | 浮力物体所在的场景图节点路径。（指 Physical 中 Actor 所在节点） |
| ------------------------ | ---------------------- | ---------------------- | --------- | ---------------------------------- | ------------------------------------------------------------ |
| Raise Object             | float                  | -inf                   | inf       | 米（m）                            | 物体竖直偏移高度                                             |
| Buoyancy Coeff           | float                  | -inf                   | inf       | no degree                          | 浮力系数                                                     |
| Buoyancy Torque          | float                  | -inf                   | inf       | no degree                          | 扭矩系数                                                     |
| Max Buoyancy Force       | float                  | -inf                   | inf       | m/s^2                              | 最大的浮力                                                   |
| Drag Force Height Offset | float                  | -inf                   | inf       | no degree                          | 浮力在物体位置的偏移                                         |
| Up Drag                  | float                  | -inf                   | inf       | no degree                          | 竖直方向的阻力                                               |
| Forward Drag             | float                  | -inf                   | inf       | no degree                          | 前后方向的阻力                                               |
| Right Drag               | float                  | -inf                   | inf       | no degree                          | 左右方向的阻力                                               |
| Rotational Frag          | float                  | -inf                   | inf       | no degree                          | 旋转（扭矩）阻力                                             |
| Floating Object Size     | enum                   | [small, medium, large] | no degree | 控制波浪大小的影响（效果暂未实装） |                                                              |

存储了一系列需要计算浮力节点的几何，主要是更新计算的数据。

```
std::unordered_set<Node_ID> floating_object_nodes;
```

#### simple-floating-object-service

**update_floating_obejct_data**

遍历所有floating_objects_nodes（Simple_Floating_Object类型：包含浮力的一些设置参数)。拿到网格和物体的一些信息：

```
const auto& ocean_mesh_config = txn.trait<Ocean_Mesh_Config>(ocean_mesh_node);
auto const& floating_object = txn.trait<Simple_Floating_Object>(node_id);
```

之后获得物理的object所在node上的物理actor和scene。

再调用Simple_Collision_Query模块的相关查询数据：包括水面速度(velocity_results),偏移(displacement_results)和法线(normal_results)。并根据查询到的数据计算。

浮力计算部分：

```
auto ocean_wave_height = ocean_mesh_config.ocean_height + query_result.displacement_results[0].y;
auto bottom_depth = ocean_wave_height - world_position[0].y + floating_object.raise_object;

if (bottom_depth <= 0.0f) continue;

auto buoyancy = -scene.gravity * floating_object.buoyancy_coeff * bottom_depth * bottom_depth * bottom_depth;
if (floating_object.max_buoyancy_force < math::inf) {
    buoyancy = util::clamp_magnitude(buoyancy, floating_object.max_buoyancy_force);
}
ext_svc_physics::Physics_System::instance().add_force(floating_object.object_node, buoyancy, ext_svc_physics::Force_Mode::acceleration);
```

这里的buoyancy并不是传统定义的浮力，没有密度，体积V的计算也做了近似，还加入了一个浮力的系数，所以最后在调用add_force的时候使用的Force_Mode::acceleration，这样也不用再有多余的质量归一化的计算（与物体质量无关）。

施加旋转扭矩：

```
auto torque = math::cross(query_result.normal_results[0], transform_up) * floating_object.buoyancy_torque;
ext_svc_physics::Physics_System::instance().add_torque(floating_object.object_node, torque,ext_svc_physics::Force_Mode::acceleration);
```





之后是添加浮力阻力：包括竖直、前后、左右和旋转力矩。

首先是计算施加这些力的重心位置

```
auto force_position = world_position[0] + floating_object.darg_force_height_offset * up;
```

```
auto transform_x = world_transform.config().rotation * x
```

计算当前物体坐标系的三个轴x = up | forward | right

结合之前计算的物体相对于水面的速度

```
auto velocity_relative_to_water = ext_svc_physics::Physics_System::instance().linear_velocity(floating_object.object_node) - query_result.velocity_results[0];
```

```
ext_svc_physics::Physics_System::instance().add_force_at_world_pos(floating_object.object_node, physics_actor.mass * transform_x * math::dot(transform_x, -velocity_relative_to_water) * floating_object.x_drag * physics_actor.mass, force_position);
```

最后是关于旋转力矩：

```
ext_svc_physics::Physics_System::instance().add_torque(floating_object.object_node, -ext_svc_physics::Physics_System::instance().angular_velocity(floating_object.object_node) * floating_object.rotational_drag, ext_svc_physics::Force_Mode::acceleration);
```



> 这里还有一些问题，为什么计算阻力的时候乘了两遍质量，还有在竖直方向为什么使用的是up而不是transform_up
