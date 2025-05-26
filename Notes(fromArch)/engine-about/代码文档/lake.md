![Pasted image.png.png](/home/user/data/notes/engine-about/代码文档/assets/Pasted image.png)

lake需要queue这个资源而只有ocean的时候不需要。

湖泊json示例: http://10.100.50.12/display/RSE/Water+System+Usage+and+Example

action里面多了一个位置的参数：

```
// 湖泊模型位置的 transform
``{
  ``"action"``: ``"transform"``,
  ``"node"``: ``"/mesh/water/lake/lake/root-node"``,
  ``"config"``: {
    ``"position"``: [0, 0, 0],
    ``"scaling"``: [1, 1, 1],
  ``},
``},
```

### 1.1.2. 创建 Lake

在任意 node 下右击按下图进行创建，并调控相应参数后即可创建对应网格的湖泊。

<img src="/home/user/data/notes/engine-about/代码文档/assets/image2024-2-5_13-42-46.png" alt="image2024-2-5_13-42-46" style="zoom:50%;" />

场景中出现对应配置的湖泊效果，其形状由参数 Lake model path 设定网格决定，例："lake_model_path": "models/lake.fbx",

<img src="/home/user/data/notes/engine-about/代码文档/assets/image2024-2-4_21-58-58 (1).png" alt="image2024-2-4_21-58-58 (1)" style="zoom:50%;" />



## lake-model-service

在service中有一个unordered_set<Node_ID>用来维护多个被添加了湖泊trait的node，添加和删除也通过这个set相关api如：find/erase等进行操作。

lake-model-config中保存的就是lake_model_node_path是lake对应node的路径。

#### on_post_load_scene

```
auto txn = impl->graph->read_only_transaction();
impl->config_node_set.clear();
for (
    auto node = Node_ID::root;
    node != Node_ID::nil;
    node = txn.next_descendant_of(node, Node_ID::root)
) {
    if (SS_UNLIKELY(node == Node_ID::root)) continue;
    if (txn.has_trait<Lake_Model_Config>(node)) {
        impl->config_node_set.insert(node);
    }
}
```

这段代码是在加载场景后遍历所有node,看哪个node上绑定了lake的trait就把他加入到set当中。

tips: SS_UNLIKELY是编译器的优化，表示这个分支条件不太可能发生。

## import lake

import_lake_config主要存了 **和json中一一对应**

- lake_model_path
- lake_name
-  water_material_config
- wave_config

在import_lake里面通过assimp导入lake_model_path指定的fbx文件。

通过lake_name(在导入的时候会指定名字，默认为“lake")和路径组合获得lake_model_node_path。用这个Path创建一个node子节点，并在这个node上attach上lake_model_config.

之后就是执行导入操作和一些setup config的一些操作。



## pass

大体上和ocean部分没有什么区别，这里只写一下不同的部分。

首先是有一个自定义的函数

```
auto is_ancestor_of(scene::Scene_Node_ID ancestor_node, scene::Scene_Node_ID descendant_node) -> bool {
    if (descendant_node == scene::Scene_Node_ID::nil) return false;
    if (ancestor_node == descendant_node) return true;
    auto graph = scene::Scene::graph().read_write_transaction();
    return is_ancestor_of(ancestor_node, graph.parent_of(descendant_node));
}
```

递归判断 ancestor_node是不是descendant_node的祖先。

#### auto setup_render_queue_and_material_config

```
pass.queue.clear();
auto lake_node_set = Lake_Model_Service::current().trait_node_set();
for (auto& lake_node: lake_node_set) {
    const auto& lake_config = graph.trait<Lake_Model_Config>(lake_node);
    for (auto& cmd: *(io.in_queue)) {
        auto& cmd_node = cmd.node;
        if (is_ancestor_of(graph.node_of(lake_config.lake_model_node_path), cmd_node)) {
            cmd.primitive = Drawing_Primitive::triangles;
            Water_Material_Service::current().uniforms_for_lake(cmd.uniforms, cmd.samplers_for_uniforms, lake_node);
            pass.queue.emplace_back(cmd);
        }
    }
}
```

从输入队列(`io.in_queue`)中筛选出与湖泊相关的渲染命令，为它们配置正确的渲染参数（如三角形图元类型和水体材质的uniform变量），然后将这些处理过的命令添加到渲染通道自己的队列(`pass.queue`)中。

通过 is_ancestor_of这个函数来判断in_queue的node是不是lake_model_node_path的子节点。

**为什么要这么判断？**

因为通过assimp导入模型的时候，会创建包含多个子节点的层次结构，例如/material /mesh等等，他们如果都在lake的节点下，那么都需要将这个cmd命令添加到队列中进行渲染。

**注意**:

对于别的pass,基本上是由ocean_mesh生成的render_queue -> ocean pass ->其他大部分pass,直接可用pass.queue获得cmd进行相关设置，还有小部分pass是自己根据情况直接通过pass.queue添加相关的draw command。

## shader

和ocean_pass中没什么区别，多的一些additional_data以及传入的一些参数都没有用到，已经标记Deprecated.



