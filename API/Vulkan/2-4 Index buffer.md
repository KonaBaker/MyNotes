index buffer

概念不必多说。

同样需要一个stagingbuffer。

## draw

draw call里面需要绑定,以及draw call的命令发生了变化

```c++
commandBuffers[frameIndex].bindIndexBuffer( *indexBuffer, 0, vk::IndexType::eUint16 );
commandBuffers[frameIndex].drawIndexed(
    indices.size(),  // indexCount
    1,               // instanceCount
    0,               // firstIndex
    0,               // vertexOffset 
    0                // firstInstance
);
```

**firstIndex**

从 index buffer 的第几个索引开始读。传 `0` 表示从头开始。

典型用途:多个 mesh 共用一个大 index buffer 时,通过 `firstIndex` 指定当前 mesh 的索引起点。比如:

- mesh A 的索引占 [0, 300),画 A 时 `firstIndex = 0`,`indexCount = 300`
- mesh B 的索引占 [300, 750),画 B 时 `firstIndex = 300`,`indexCount = 450`

**vertexOffset**

从 index buffer 取出一个索引后,硬件会把这个值**加上 `vertexOffset`**,再拿去 vertex buffer 里取顶点。传 `0` 表示不偏移。

典型用途和 `firstIndex` 类似——多个 mesh 共用一个大 vertex buffer 时用它定位。比如:

- mesh A 的顶点在 vertex buffer 的 [0, 100)
- mesh B 的顶点在 vertex buffer 的 [100, 250)

mesh B 自己的索引是 `0, 1, 2, ...`(从 0 开始写的,自成体系),画 mesh B 时只要把 `vertexOffset` 设成 `100`,硬件就会自动把索引 `0` 解释为 vertex buffer 里的第 100 个顶点。这样你就不用在 CPU 端把 mesh B 的所有索引都 +100 重写一遍。

**firstInstance*