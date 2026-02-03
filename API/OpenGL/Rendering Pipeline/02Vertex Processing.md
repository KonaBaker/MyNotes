# Vertex Processing 顶点处理

**顶点处理**是渲染流水线中的一组阶段，包括多个可选的shader stage。处理过后就会为**顶点后处理**以及**之后阶段**提供数据。

## Vertex Shader

[Vertex Shader](.\sub\2-1 vertex shader.md)

输入：由一系列顶点属性组成的单一顶点。

输出：output vertex

输入和输出的顶点之间是1:1的

## Tessellation

[Tessellation](./sub/2-2 Tessellation.md)

将上一阶段的顶点输出**收集成图元**。

## geometry shader

[geometry shader](./sub/2-3 geometry shader.md)

输入：单个基图元

输出：0个或多个图元。

不同的图元可以渲染到不同的image上



