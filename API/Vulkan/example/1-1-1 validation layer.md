### 例子一：纹理刚被写完，下一步又拿来读

先看“同一张纹理先写后读”。

OpenGL 里你可以先把纹理挂到 FBO 上渲染，再在下一次 draw 里把它当采样纹理读：

```
GLuint tex = ...;
GLuint fbo = ...;
GLuint programWrite = ...;
GLuint programRead  = ...;

// pass 1: 写 tex
glBindFramebuffer(GL_FRAMEBUFFER, fbo);
glFramebufferTexture2D(GL_FRAMEBUFFER,
                       GL_COLOR_ATTACHMENT0,
                       GL_TEXTURE_2D,
                       tex,
                       0);

glViewport(0, 0, 512, 512);
glUseProgram(programWrite);
glDrawArrays(GL_TRIANGLES, 0, 3);

// pass 2: 读 tex
glBindFramebuffer(GL_FRAMEBUFFER, 0);
glViewport(0, 0, 800, 600);

glUseProgram(programRead);
glBindTextureUnit(0, tex);
glDrawArrays(GL_TRIANGLES, 0, 3);
```

这段代码里，你没有显式告诉 OpenGL：

“前一个 pass 对 `tex` 是 color attachment write，后一个 pass 对 `tex` 是 shader read，请在这里做缓存可见性处理和状态转换。”

但驱动必须知道这件事，否则第二个 pass 可能读不到刚写进去的数据，或者读到的是硬件上还没准备好的状态。也就是说，这个“资源从写转为读”的语义，**在 OpenGL 里主要是驱动通过资源历史和当前用法来推断**。

对应的 Vulkan 写法就不会只写“前后两个 pass”，你还要把中间关系写出来。简化地看像这样：

```
// pass 1: 把 image 当 color attachment 写
vkCmdBeginRendering(cmd, &renderingInfoWrite);
vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineWrite);
vkCmdDraw(cmd, 3, 1, 0, 0);
vkCmdEndRendering(cmd);

// 明确写出：前面是 color attachment write，后面要给 fragment shader read
VkImageMemoryBarrier2 barrier{};
barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2;
barrier.srcStageMask = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT;
barrier.srcAccessMask = VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT;
barrier.dstStageMask = VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
barrier.dstAccessMask = VK_ACCESS_2_SHADER_SAMPLED_READ_BIT;
barrier.oldLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
barrier.image = image;
barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
barrier.subresourceRange.levelCount = 1;
barrier.subresourceRange.layerCount = 1;

VkDependencyInfo dep{};
dep.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO;
dep.imageMemoryBarrierCount = 1;
dep.pImageMemoryBarriers = &barrier;

vkCmdPipelineBarrier2(cmd, &dep);

// pass 2: 把 image 当 sampled image 读
vkCmdBeginRendering(cmd, &renderingInfoRead);
vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineRead);
vkCmdBindDescriptorSets(cmd,
                        VK_PIPELINE_BIND_POINT_GRAPHICS,
                        pipelineLayoutRead,
                        0, 1, &descriptorSetWithSampledImage,
                        0, nullptr);
vkCmdDraw(cmd, 3, 1, 0, 0);
vkCmdEndRendering(cmd);
```

这里最关键的不是 barrier 这个 API 名字，而是：
 **“从写到读”这个语义不再藏在驱动内部推断，而是变成了应用必须提供的输入。**

如果你不写这个 barrier，编译器通常不会报错；validation layer 大概率会报；不开 validation 的话，结果就可能未定义或者至少不可依赖。

------

### 例子二：图像当前到底处于什么“使用状态”

很多 GPU 对 image 在不同用途下有不同要求。比如作为 render target 用，和作为 sampled texture 用，底层期望的状态可能不同。

OpenGL 里你不会显式写“这张纹理现在从 render-target 状态切到 shader-read 状态”。你只是改了 API 用法：

```
// 先作为 attachment
glBindFramebuffer(GL_FRAMEBUFFER, fbo);
glFramebufferTexture2D(GL_FRAMEBUFFER,
                       GL_COLOR_ATTACHMENT0,
                       GL_TEXTURE_2D,
                       tex,
                       0);
glDrawArrays(GL_TRIANGLES, 0, 3);

// 后作为 texture
glBindFramebuffer(GL_FRAMEBUFFER, 0);
glBindTextureUnit(0, tex);
glUseProgram(program);
glDrawArrays(GL_TRIANGLES, 0, 3);
```

OpenGL 没有把“image layout/state transition”暴露成你必须写的 API 契约。
 这不代表这种状态不存在，而是代表：**状态机主要在驱动内部。**

驱动需要跟踪“`tex` 之前被当作什么，现在又被当作什么”，然后在合适的时候做必要转换。你代码里没写，不等于这件事不需要发生，而是它被藏起来了。

Vulkan 则直接把这个状态机抬到 API 表面。还是看刚才那段 barrier：

```
barrier.oldLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
```

这两行就已经非常说明问题了：
 OpenGL 里这部分语义是驱动隐式维护的；Vulkan 里这部分语义是应用显式声明的。

所以 Vulkan 不是“突然就能不检查”，而是它从 API 设计上把这块信息交还给应用提供了。驱动不需要猜“你是不是想从 attachment 转成 sampled”，因为你已经写出来了。

------

### 例子三：一次 draw 依赖哪些资源，OpenGL 和 Vulkan 谁说得更清楚

OpenGL 里你可能这样画一个物体：

```
GLuint program = ...;
GLuint vao = ...;
GLuint tex = ...;
GLuint ubo = ...;

glUseProgram(program);
glBindVertexArray(vao);
glBindTextureUnit(0, tex);
glBindBufferBase(GL_UNIFORM_BUFFER, 0, ubo);
glDrawElements(GL_TRIANGLES, indexCount, GL_UNSIGNED_INT, 0);
```

这当然已经是对象化的 API 了，不是说它完全靠全局散装状态。
 但对驱动来说，在 `glDrawElements` 真正发生时，它还是要把这次 draw 需要的整体配置拼起来看：

- 当前 program 需要哪些资源槽位
- texture unit 0 上的对象是否符合 shader 预期
- uniform block binding 0 上的 buffer 是否满足 shader 接口
- vao 提供的顶点格式是否匹配 shader 输入
- 当前 framebuffer、blend、depth 等状态是否和这次 draw 兼容

也就是说，**这些对象本身各自知道一部分信息，但“这次 draw 的完整执行语义”仍然是运行时组合出来的。**

Vulkan 则会更早把“资源接口长什么样”固化下来。简化地写，像这样：

```
// descriptor set layout: binding 0 = uniform buffer, binding 1 = combined image sampler
VkDescriptorSetLayoutBinding bindings[2]{};

bindings[0].binding = 0;
bindings[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
bindings[0].descriptorCount = 1;
bindings[0].stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;

bindings[1].binding = 1;
bindings[1].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
bindings[1].descriptorCount = 1;
bindings[1].stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;

VkDescriptorSetLayoutCreateInfo setLayoutInfo{};
setLayoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
setLayoutInfo.bindingCount = 2;
setLayoutInfo.pBindings = bindings;

vkCreateDescriptorSetLayout(device, &setLayoutInfo, nullptr, &setLayout);

// pipeline layout 引用这个 descriptor set layout
VkPipelineLayoutCreateInfo pipelineLayoutInfo{};
pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
pipelineLayoutInfo.setLayoutCount = 1;
pipelineLayoutInfo.pSetLayouts = &setLayout;

vkCreatePipelineLayout(device, &pipelineLayoutInfo, nullptr, &pipelineLayout);

// 创建 pipeline 时，shader + pipeline layout + 顶点输入等一起固定
vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &pipeline);
```

到 draw 时，你绑定的是“必须符合这套布局”的 descriptor set：

```
vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
vkCmdBindVertexBuffers(cmd, 0, 1, &vertexBuffer, offsets);
vkCmdBindIndexBuffer(cmd, indexBuffer, 0, VK_INDEX_TYPE_UINT32);
vkCmdBindDescriptorSets(cmd,
                        VK_PIPELINE_BIND_POINT_GRAPHICS,
                        pipelineLayout,
                        0, 1, &descriptorSet,
                        0, nullptr);
vkCmdDrawIndexed(cmd, indexCount, 1, 0, 0, 0);
```

这里的关键是，`descriptorSet` 不是“随便一个运行时对象，draw 时再看看行不行”，而是它从分配、更新、绑定开始，就被前面的 `DescriptorSetLayout` 和 `PipelineLayout` 约束住了。

所以 Vulkan 的不同点不是“它完全不检查资源绑定”，而是：

**它把资源接口关系提前变成了对象创建时的承诺。**

OpenGL 里 program 当然也知道自己要哪些 uniform/sampler/block，但这种“接口承诺”没有像 Vulkan 的 pipeline layout / descriptor set layout 那样，被系统化成一套强约束的对象关系网络。于是驱动在 draw 附近仍然更需要做动态确认。

------

如果把这些例子压成一句话，就是：

**OpenGL 的很多正确性信息存在于“驱动必须自己推断的上下文历史”里；Vulkan 则把这些信息提升成了应用必须显式提供的 API 参数。**