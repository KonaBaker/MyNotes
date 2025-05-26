https://zhuanlan.zhihu.com/p/7345604081

**cpu driven** 合批、剔除、搜集等在cpu在调用gpu绘制指令之前完成的一些处理。

将这些操作转移到gpu执行 -> **gpu driven（数据驱动的架构）**





<img src="/home/user/data/notes&doc-for-engine/cg/assets/v2-9a454154f41a09f06f2478a3ef0987dc_1440w.jpg" alt="img" style="zoom:50%;" />

<img src="/home/user/data/notes&doc-for-engine/cg/assets/v2-5c7bb26199326df58d2dcda106b498c2_1440w.jpg" alt="img" style="zoom:50%;" />

- Instance Culling

  <img src="/home/user/data/notes&doc-for-engine/cg/assets/100044282-75468-1.jpg" style="zoom:50%;" />

- Mesh Cluster Rendering

  将场景分为一个个小的cluster然后利用gpu并行渲染。由cpu分发 draw call -> 由gpu进行统一管理、调度。

- Depth Reprojection

  将前一帧的信息保留到另一帧。反投影成世界坐标，再计算在当前帧的位置。

  **应用场景**

  - TAA

  - 光线追踪降噪

  - motion vector

    计算运动轨迹