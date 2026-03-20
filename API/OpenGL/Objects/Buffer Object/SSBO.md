SSBO是一种buffer object 主要用于在glsl中进行数据的存储和检错

- SSBO最大可达128MB  > UBO 16KB
- SSBO是可写的，支持原子操作。
- SSBO可以拥有可变存储空间，UBO拥有固定的存储大小。
- 同等条件下，SSBO的访问速度可能低于UBO。

> An interface to **buffer textures** via **image load/store**

### memory qualifiers

`coherent`

每个线程/invocation/核心，会有缓存cache或者寄存器，那么在写入的时候，可能只是暂时写到了cache中，并没有写回显存。其他线程读到的可能还是旧值。

在遇到memorybarrier的时候，将这个变量同步到显存中。

```c++
layout(std430, binding = 0) coherent buffer MySSBO {
    int sharedData;
};

void main() {
    uint tid = gl_LocalInvocationID.x;

    if (tid == 0) {
        sharedData = 42; // 线程0写入数据。如果没有coherent，42可能只停留在线程0的Cache里
    }

    // 第一步：内存屏障。
    // 强制把 sharedData=42 这个操作刷入主存，对其他线程可见。
    memoryBarrierBuffer(); 

    // 第二步：执行屏障。
    // 线程1可能跑得比线程0快，如果在线程0写之前线程1就去读，还是会错。
    // 所以让线程1在这里等一下，直到线程0也跑到了这里。
    barrier(); 

    if (tid == 1) {
        // 因为有 coherent + memoryBarrier + barrier 三管齐下，
        // 这里百分之百能读到 42！
        int val = sharedData; 
    }
}
```



`volatile`

告诉编译器这个变量可能随时被更改，不要读缓存，从显存中去读。彻底关闭了缓存机制。每一次写入都必须直接写入显存，是激进的coherent。

> 很少使用。通常只用于spin-lock

`restrict`

通常情况下，编译器会假设在相同的shader中你可能会通过不同的变量访问相同的image/buffer。如果你通过第一个变量写入数据，第二个变量读取数据，编译器可能会认为你可能正在读取刚刚写入的值。

使用restrict会告诉编译器，**在当前着色器调用中**，只有这一个特定变量可以修改该内存。这使得编译器可以更好的优化读写操作。

> **你应该尽可能使用这个限定符**

`readonly`

只读，禁止原子操作。

`writeonly`

只写，禁止原子操作。

### Atomic operations 

### OpenGL usage

```c++
struct SSBOData {
    float inputVal;
    float outputVal;
};

void runSSBODemo() {
    SSBOData myData = { 3.14f, 0.0f };
    GLuint ssbo;
    glCreateBuffers(1, &ssbo);

    // 直接为 Buffer 分配内存并初始化数据。
    // GL_DYNAMIC_STORAGE_BIT 允许以后用 glNamedBufferSubData 修改。
    // GL_MAP_READ_BIT 允许我们后面把结果 Map 回内存读取。
    glNamedBufferStorage(ssbo, sizeof(SSBOData), &myData, 
                         GL_DYNAMIC_STORAGE_BIT | GL_MAP_READ_BIT);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, ssbo);
    
    // ... 此处省略调用 Compute Shader 的代码 (glDispatchCompute) ...
    // glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT); // 确保 GPU 写完

    // 映射显存回 CPU 读取结果
    void* ptr = glMapNamedBuffer(ssbo, GL_READ_ONLY);
    if (ptr) {
        SSBOData* result = static_cast<SSBOData*>(ptr);
        std::cout << "Output from GPU: " << result->outputVal << std::endl;
        glUnmapNamedBuffer(ssbo);
    }

    glDeleteBuffers(1, &ssbo);
}
```

```
#version 460 core
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(std430, binding = 0) buffer DataBuffer {
    float inputVal;
    float outputVal;
} myBuffer;

void main() {
    float val = myBuffer.inputVal;
    myBuffer.outputVal = val * 2.0; 
}
```

