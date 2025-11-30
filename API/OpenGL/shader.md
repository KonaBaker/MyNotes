#### **GPU端程序**

着色器是一种**用户定义的程序**,专门设计在gpu中某个阶段（也对应opengl可编程管线）运行。用于处理opengl传入的数据，为某些可编程阶段提供代码实现，也可以（受限制）用于通用gpu计算。

**program object**可以将多个着色器阶段组合成一个完整的整体。

**program pipeline object** 允许将不同的shade stage编译成独立的program。然后再将这些独立的program组合成完整整体。

阶段：
vertex(唯一且必须) -> tessellation & evaluation -> geometry -> fragment  | compute（一个独立于管线的部分）

#### invocation

着色器每次执行被称为"invocation"(调用)。

着色器阶段的调用之间是无法交互的。

每个着色器阶段都定义了自身调用频率。

- vertex: 每个顶点一次（通常）
- tesc: 每个面片的每个输出顶点一次。同一输入面片的调用之间可通信
- tese: [着色器 - OpenGL 百科 --- Shader - OpenGL Wiki](https://www.khronos.org/opengl/wiki/Shader)见描述后补充
- geometry:每个图元执行一次（实例化多次）
- fragment:每个片段执行一次（helper fragment特例：
  - GPU通常quad并行执行fragment shader,有的没被覆盖的部分可能需要被“拉进来”计算导数等，于是执行次数就变多了。
- compute:由工作组决定。工作组内可通信。

#### 关于条件判断

对于uniform和常量或其组合都是**”statically uniform expression"**，所以可以放心在if中存在，不会导致分歧.

>注意：这里的静态统一表达式，并不是C++中多广泛被认为的“静态”，即编译期确定。它只是指**在shader执行期间对所有线程都有相同的值**
>
>导致分歧的原因，主要是同一warp内需要执行不同的代码路径，会导致指令器处理不过来（因为通常一个SIMD单元只有一个指令处理器，剩下的都是数学计算单元）。





