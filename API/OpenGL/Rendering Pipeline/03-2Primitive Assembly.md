# primitive assembly

该阶段是在vertex post processing进行的（clip之前）。

将顶点流组装成图元。

图元被divided into 一系列独立的base primitive，经过一些简单处理后，被送到光栅化器进行渲染。

**概念**

primitve或者primitive type/mode

- `GL_POINTS`
- `GL_LINE_STRIP`
- `GL_TRIANGLE_FAN`

诸如此类

base primitive

- point
- line
- triangle

也就是primitive最终都会被分解为base primitive，例如：

`v0 v1 v2 v3 v4`顶点按照`GL_TRIANGLE_STRIP`组装，最后被分解为三个三角形

```c++
(v0,v1,v2)
(v1,v2,v3)
(v2,v3,v4)
```

## early primitive assembly

在GS之前也会进行某种形式的图元装配，仅执行到base primitive的转换

【详细见geometry shader】

## primitive order

处理顺序一般来说是固定的：

- 单draw call按顺序处理
- multi-draw中也是按顺序处理
- 实例化绘制中，按gl_InstanceID的顺序

## discard

启用`GL_RASTERIZER_DISCARD`，可以丢弃所有图元。

- 用于测试先前渲染阶段的性能（隔离后部分，观察顶点处理阶段的开销有多大）
- 防止渲染在transform feedback期间产生的图元

## face culling

三角形图元的剔除。

三角形图元具有特定的朝向，由三角形的三个顶点的顺序以及屏幕上的表观顺序定义。

### 环绕顺序

当发起DC的时候，会根据vertex spec中的顺序进行处理（GS/TES可以改变这个顺序）。

- 顺时针Clockwise(GL_CW)
- 逆时针Counter-Clockwise(GL_CCW)

`glFrontFace(GLenum mode);`设置某种环绕方式为正面。默认是GL_CCW

其他非三角形图元，则始终是正面。

**tessellation winding order**

【详细见tessellation】

## culling

首先需要启用`glEnable(GL_CULL_FACE)`

然后指定哪一面`glCullFace(GL_FRONT)`

`glCullFace(GL_FRONT_AND_BACK)`和`glEnable(GL_RASTERIZER_DISCARD)`的区别就是前者只会剔除三角形，后者所有图元全部discard。

## Fragment shader

fs中会检测一个图元的朝向，和如果是正面gl_FrontFaceing为true 背面就为false。
