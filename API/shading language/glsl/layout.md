`layout(binding = N)` 在 GLSL 中用于把某些着色器资源（UBO/SSBO/image/sampler/atomic 等）绑定到编号为 N 的“binding point/unit”。

不同资源类型各自有独立的命名空间（UBO binding points、SSBO binding points、image units、texture units、vertex attribute locations……互不冲突）。

