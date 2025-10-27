**memory barriers**

多个独立的着色器调用单个共享的内存地址。通过内存控制函数来控制。

glsl内的:**memorybarrier**

all invocations of a single draw call

和barrier()不同，barrier()是**同步点**,同一个work group内的invocation需要都到达这里之后，才会继续同步运行。

memorybarrier()是一个flush,所有的内存，刷新到共享可见的层次结构中。

两者通常搭配使用。

memorybarrier(); barrier();

---

opengl api中的: **glmemorybarrier**

multiple shader不同draw call之间. **不会阻塞cpu,也不会等待gpu任务结束**,只是一个”顺序“的指令，让gpu按照次序执行，在某一个指令前彻底完成上一个指令。

- ```GL_SHADER_IMAGE_ACCESS_BARRIER_BIT```:

着色器对image变量的访问。限制的是image unit

> 同一 shader的后续dispatch(不同draw call).compute写入image,另一段shader读image.

- ``` GL_TEXTURE_FETCH_BARRIER_BIT```：

限制的是sampler unit

> 前compute shader image store,后有其他shader通过Sampler texture()访问。（并没有经过cpu,数据一直在显存上）

---

glfinish是需要等待gpu完成的
