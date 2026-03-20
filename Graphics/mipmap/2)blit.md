# blit

- 从 mip 0 blit 到 mip 1

- 做一次 barrier，让 mip 1 从写后可读

- 再从 mip 1 blit 到 mip 2

- 再 barrier

- 如此反复直到最后一级

最大问题：

- 一级一barrier，

- 访寸消耗/缓存局部性差。用不上shuffle或者shared memory，可能用上L2cache。

## opengl

每一层是上一层downsample + filter得到的，选一种卷积核。`glGenerateMipmap`并不要求具体实现，所以更深入的讨论应该找具体的驱动。



## vulkan

