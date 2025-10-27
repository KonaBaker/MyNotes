

### Buffer

缓冲对象持有一个任意大小的线性内存数组，在使用之前需要先分配这块内存。有mutable和immutable两种分配方式。

使用DSA模式，无需在bind到target上。

**immutable**

```glnamedbufferstorage``` 

dsa方式，不用指定target，直接传入buffer的数字名称即可。

**mutable**

```glnamedbufferdata```

该操作会同时重新分配缓冲对象的存储空间。（可变存储空间）

---

```glnamedbuffersubdata```

只更新数据，但不重新分配存储空间，可变与不可变均可使用

```glclearnamedbuffersubdata```&```glclearnamedbufferdata```

清空缓冲区（部分）,都不会重新分配存储空间

```glGetNamedBufferSubData```

将数据读回cpu

```glCopyNamedBufferSubData```

复制

---

**mapping**

上面两个函数可以向缓冲区提供数据，但是可能会造成**性能浪费**：例如当某个算法生成的数据需要存入缓冲区对象，就必须先分配临时内存来存储这些数据，然后才能传递。读取数据也是类似的。

**直接获取缓冲区对象存储空间的指针**然后再进行写入操作。

在映射过程中，不能调用任何导致opengl读取、修改或写入该缓冲区的函数（持久映射方式除外）。

```glmapnamedbuffer```&```glmapnamedbufferrange```(整个和部分缓冲区)

函数会返回对应缓冲区的指针。

对于access参数可以设定：

- GL_MAP_READ_BIT
- GL_MAP_WRITE_BIT

```glunmapnamedbuffer```

是之前map的指针生效，此时缓冲区对象会更新做的修改

**持久化mapping**

使用不可变存储方式进行创建，flags包含GL_MAP_PERSISTENT_BIT。

但是这是需要对映射指针写入数据进行刷新，从而使其**对opengl可见**

```glflushmappednamedbufferrange```

如果要使用opengl写入，用户读取：

command(write) -> glmemorybarrier -> fence sycn->干其他事情->fence sync -> read from pointer

> 使用示例：
>
> ```
> #include <GL/glew.h>
> #include <iostream>
> #include <vector>
> #include <thread>
> #include <chrono>
> 
> class PersistentMappedBuffer {
> private:
>     GLuint buffer;
>     void* mappedPtr;
>     GLsizeiptr bufferSize;
>     GLsync fence;
>     
> public:
>     PersistentMappedBuffer(GLsizeiptr size) : bufferSize(size), fence(nullptr) {
>         // 1. 创建缓冲对象（DSA方式）
>         glCreateBuffers(1, &buffer);
>         
>         // 2. 分配不可变存储空间，设置持久化映射标志
>         // GL_MAP_PERSISTENT_BIT: 允许持久化映射
>         // GL_MAP_COHERENT_BIT: 自动同步CPU和GPU内存
>         // GL_DYNAMIC_STORAGE_BIT: 允许动态修改内容
>         GLbitfield storageFlags = GL_MAP_PERSISTENT_BIT | 
>                                  GL_MAP_COHERENT_BIT | 
>                                  GL_DYNAMIC_STORAGE_BIT;
>         
>         glNamedBufferStorage(buffer, bufferSize, nullptr, storageFlags);
>         
>         // 3. 创建持久化映射
>         // GL_MAP_WRITE_BIT: 允许写入
>         // GL_MAP_READ_BIT: 允许读取
>         // GL_MAP_PERSISTENT_BIT: 持久化映射
>         // GL_MAP_COHERENT_BIT: 自动同步
>         GLbitfield mapFlags = GL_MAP_WRITE_BIT | 
>                              GL_MAP_READ_BIT | 
>                              GL_MAP_PERSISTENT_BIT | 
>                              GL_MAP_COHERENT_BIT;
>         
>         mappedPtr = glMapNamedBufferRange(buffer, 0, bufferSize, mapFlags);
>         
>         if (!mappedPtr) {
>             std::cerr << "Failed to map buffer persistently!" << std::endl;
>             throw std::runtime_error("Buffer mapping failed");
>         }
>         
>         std::cout << "Persistent buffer mapped successfully!" << std::endl;
>     }
>     
>     ~PersistentMappedBuffer() {
>         // 清理fence
>         if (fence) {
>             glDeleteSync(fence);
>         }
>         
>         // 取消映射
>         glUnmapNamedBuffer(buffer);
>         
>         // 删除缓冲对象
>         glDeleteBuffers(1, &buffer);
>     }
>     
>     // 写入数据到缓冲区
>     void writeData(const void* data, GLsizeiptr size, GLsizeiptr offset = 0) {
>         if (offset + size > bufferSize) {
>             std::cerr << "Write operation exceeds buffer size!" << std::endl;
>             return;
>         }
>         
>         // 等待之前的GPU操作完成
>         waitForGPU();
>         
>         // 直接写入映射的内存
>         std::memcpy(static_cast<char*>(mappedPtr) + offset, data, size);
>         
>         // 如果不使用GL_MAP_COHERENT_BIT，需要手动刷新
>         // glFlushMappedNamedBufferRange(buffer, offset, size);
>         
>         std::cout << "Data written to buffer at offset " << offset << std::endl;
>     }
>     
>     // 从缓冲区读取数据
>     void readData(void* data, GLsizeiptr size, GLsizeiptr offset = 0) {
>         if (offset + size > bufferSize) {
>             std::cerr << "Read operation exceeds buffer size!" << std::endl;
>             return;
>         }
>         
>         // 等待GPU写入完成
>         waitForGPU();
>         
>         // 确保GPU内存更改对CPU可见
>         glMemoryBarrier(GL_BUFFER_UPDATE_BARRIER_BIT);
>         
>         // 从映射的内存读取
>         std::memcpy(data, static_cast<char*>(mappedPtr) + offset, size);
>         
>         std::cout << "Data read from buffer at offset " << offset << std::endl;
>     }
>     
>     // 设置同步fence，用于CPU/GPU同步
>     void insertFence() {
>         if (fence) {
>             glDeleteSync(fence);
>         }
>         fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
>     }
>     
>     // 等待GPU操作完成
>     void waitForGPU() {
>         if (fence) {
>             // 等待fence信号
>             GLenum result = glClientWaitSync(fence, GL_SYNC_FLUSH_COMMANDS_BIT, GL_TIMEOUT_IGNORED);
>             
>             if (result == GL_ALREADY_SIGNALED || result == GL_CONDITION_SATISFIED) {
>                 std::cout << "GPU operations completed" << std::endl;
>             } else {
>                 std::cout << "GPU wait failed or timed out" << std::endl;
>             }
>             
>             glDeleteSync(fence);
>             fence = nullptr;
>         }
>     }
>     
>     // 获取缓冲对象ID
>     GLuint getBufferID() const { return buffer; }
>     
>     // 获取映射指针
>     void* getMappedPtr() const { return mappedPtr; }
>     
>     // 演示非相干映射的使用
>     void demonstrateNonCoherentMapping() {
>         std::cout << "\n=== 演示非相干映射 ===" << std::endl;
>         
>         // 创建非相干映射的缓冲
>         GLuint nonCoherentBuffer;
>         glCreateBuffers(1, &nonCoherentBuffer);
>         
>         // 只使用GL_MAP_PERSISTENT_BIT，不使用GL_MAP_COHERENT_BIT
>         GLbitfield storageFlags = GL_MAP_PERSISTENT_BIT | GL_DYNAMIC_STORAGE_BIT;
>         glNamedBufferStorage(nonCoherentBuffer, 1024, nullptr, storageFlags);
>         
>         GLbitfield mapFlags = GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT;
>         void* nonCoherentPtr = glMapNamedBufferRange(nonCoherentBuffer, 0, 1024, mapFlags);
>         
>         if (nonCoherentPtr) {
>             // 写入数据
>             int testData = 12345;
>             std::memcpy(nonCoherentPtr, &testData, sizeof(testData));
>             
>             // 必须手动刷新映射范围
>             glFlushMappedNamedBufferRange(nonCoherentBuffer, 0, sizeof(testData));
>             
>             std::cout << "Non-coherent mapping data written and flushed" << std::endl;
>             
>             // 清理
>             glUnmapNamedBuffer(nonCoherentBuffer);
>         }
>         
>         glDeleteBuffers(1, &nonCoherentBuffer);
>     }
> };
> 
> // 使用示例
> void demonstrateUsage() {
>     std::cout << "=== OpenGL 4.6 DSA 持久化映射示例 ===" << std::endl;
>     
>     try {
>         // 创建1KB的持久化映射缓冲区
>         PersistentMappedBuffer buffer(1024);
>         
>         // 准备测试数据
>         std::vector<float> testData = {1.0f, 2.0f, 3.0f, 4.0f, 5.0f};
>         
>         // 写入数据
>         buffer.writeData(testData.data(), testData.size() * sizeof(float));
>         
>         // 设置fence进行同步
>         buffer.insertFence();
>         
>         // 模拟GPU操作
>         std::cout << "模拟GPU处理..." << std::endl;
>         std::this_thread::sleep_for(std::chrono::milliseconds(100));
>         
>         // 读取数据
>         std::vector<float> readData(testData.size());
>         buffer.readData(readData.data(), readData.size() * sizeof(float));
>         
>         // 验证数据
>         std::cout << "验证数据: ";
>         for (size_t i = 0; i < readData.size(); ++i) {
>             std::cout << readData[i] << " ";
>         }
>         std::cout << std::endl;
>         
>         // 演示缓冲区作为顶点缓冲的使用
>         std::cout << "\n=== 作为顶点缓冲使用 ===" << std::endl;
>         
>         // 顶点数据
>         struct Vertex {
>             float x, y, z;
>         };
>         
>         std::vector<Vertex> vertices = {
>             {0.0f, 0.5f, 0.0f},
>             {-0.5f, -0.5f, 0.0f},
>             {0.5f, -0.5f, 0.0f}
>         };
>         
>         // 写入顶点数据
>         buffer.writeData(vertices.data(), vertices.size() * sizeof(Vertex));
>         
>         // 绑定为顶点缓冲（可选，用于传统渲染管线）
>         glBindBuffer(GL_ARRAY_BUFFER, buffer.getBufferID());
>         
>         std::cout << "顶点数据已写入缓冲区，可用于渲染" << std::endl;
>         
>         // 演示非相干映射
>         buffer.demonstrateNonCoherentMapping();
>         
>     } catch (const std::exception& e) {
>         std::cerr << "Error: " << e.what() << std::endl;
>     }
> }
> 
> int main() {
>     // 假设OpenGL上下文已经创建
>     // 初始化GLEW
>     if (glewInit() != GLEW_OK) {
>         std::cerr << "Failed to initialize GLEW" << std::endl;
>         return -1;
>     }
>     
>     // 检查OpenGL版本和扩展支持
>     if (!GLEW_VERSION_4_6) {
>         std::cerr << "OpenGL 4.6 not supported" << std::endl;
>         return -1;
>     }
>     
>     demonstrateUsage();
>     
>     return 0;
> }
> ```

**特定目标**

一般的buffer对象绑定到特定目标，opengl会按照既定格式和方式来操作这些数据。

GL_ARRAY_BUFFER/GL_ELEMENT_ARRAY_BUFFER等等

**绑定索引目标**

某些目标是带索引的，可以绑定多个功能相似的缓冲对象

```glbindbufferrange```&```glbindbufferbase```

绑定到索引而不是仅绑定到目标（```glbindbuffer```)，且这种绑定不仅仅为了修改而绑定到上下文（虽然在DSA下，为了修改也无需绑定），而是之后确实需要使用（这可跟是否是DSA无关了哦）

**多重绑定和索引目标**

```glbindbuffersrange```

将一个buffer数组（包含count个buffer)绑定到[first, first + count)

是一个批量操作。

