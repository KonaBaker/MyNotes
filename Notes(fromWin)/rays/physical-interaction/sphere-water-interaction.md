| Sphere Water Interaction   | Sphere Water Interaction Config | Object Path | string | /         | 交互物体所在的场景图节点路径。                               |
| -------------------------- | ------------------------------- | ----------- | ------ | --------- | ------------------------------------------------------------ |
| Radius                     | float                           | 0.01        | 50.0   | 米（m）   | 球体半径                                                     |
| Weight                     | float                           | -50.0       | 50.0   | no degree | 产生交互波的权重                                             |
| Vertical Weight            | float                           | 0.0         | 2.0    | no degree | 产生交互波竖直方向的权重                                     |
| Inner Sphere Multiplier    | float                           | 0.0         | 10.0   | no degree | 内部受力球的水平力系数                                       |
| Inner Sphere Offset        | float                           | 0.01        | 1.0    | no degree | 内部受力球偏移                                               |
| Vertical Offset            | float                           | 0.0         | 2.0    | no degree | 竖直方向偏移（暂未实装）                                     |
| Compensate For Wave Motion | float                           | 0.0         | 1.0    | no degree | FFT模拟的波浪会有水平方向的偏移，该系数用来对动态波的位置进行偏移 |
| Max Speed                  | float                           | 0.0         | inf    | m/s       | 物体和水的最大相对速度                                       |

- source-physical-interaction/collision/simple-collision-qury.hpp[cpp]
- source/ocean-pass.cpp
- runtime/shader/collision/cascades-data.glsl
- runtime/shader/cillision/query-collision-data-comp.glsl
- runtime/pass/collision/query-collision-data.json