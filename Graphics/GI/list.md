很好的方向。GI 是游戏引擎渲染岗位面试的重灾区，下面按"重要性 + 学习顺序"分层给你一个完整的路线图。每一层都是下一层的前置知识，建议按 Tier 顺序学。

### Tier 0：必备理论基础（不会就直接挂）

这一层是后面所有技术的根，面试官几乎一定会从这里切入。

- **渲染方程（The Rendering Equation）**：Kajiya 1986，要会写、会解释每一项的物理意义。
- **辐射度量学**：Radiance、Irradiance、Radiant Flux、立体角、cosine 项的来源。
- **BRDF / BSDF**：Lambert、Phong、Cook-Torrance、GGX/Trowbridge-Reitz，能量守恒、互易性。
- **蒙特卡洛积分**：估计器、方差、收敛性。
- **重要性采样（Importance Sampling）+ MIS**：尤其是 MIS，几乎所有现代采样方案都依赖它。
- **Russian Roulette、Next Event Estimation**：路径追踪的基本优化。

推荐：PBRT（理论圣经，前 14 章）+ GAMES101/202。

### Tier 1：经典实时 GI（面试高频，必须能讲清原理与优缺点）

#### 1.1 静态烘焙系

- **Lightmap**：UV 展开、Charts、Seam 处理。
- **Light Probe + Spherical Harmonics (SH)**：SH 基函数、L1/L2 阶投影、为什么用 SH 不用其他基。
- **PRT (Precomputed Radiance Transfer)**：Sloan 2002，理解 Transfer Vector / Matrix，能解释为什么 PRT 可以做软阴影和 inter-reflection，以及它的局限（静态几何）。
- **Irradiance Volume / Irradiance Probes**。

#### 1.2 屏幕空间系

- **SSAO → HBAO → GTAO**：GTAO 是工业界主流，要会推导。
- **SSR (Screen Space Reflection)**：Hi-Z marching、fallback 策略。
- **SSGI**：本质是 SSR 的漫反射版本，理解为什么效果差且为什么仍然是 fallback 的一环。

#### 1.3 经典动态 GI

- **Reflective Shadow Maps (RSM)**：Dachsbacher 2005，一次 bounce 的基础。
- **Light Propagation Volumes (LPV)**：CryEngine 当年的方案，理解 SH 在 grid 中的传播。

### Tier 2：现代实时 GI（这一层是当前主流方向）

- **Voxel-based GI**
  - **VXGI / SVOGI / Voxel Cone Tracing**：Crassin 2011，理解体素化、Mipmap、Cone Tracing 近似。
  - 优点和漏光、内存问题。
- **DDGI (Dynamic Diffuse Global Illumination)**：Majercik 2019，NVIDIA RTXGI。当下最广泛使用的 probe 方案，必须熟：八面体编码、Depth/Visibility test、Probe relocation。
- **Surfel-based GI**：EA SEED 的方案（GI-1.0 / Halcyon），理解 surfel 生成、覆盖、acceleration structure，是 Battlefield / 寒霜系新方向。
- **Hardware Ray Tracing GI**：BVH、TLAS/BLAS、Inline RT vs RT Pipeline、Shader Binding Table。

### Tier 3：工业级集成方案（重点中的重点，UE 岗必问）

- **Lumen (UE5)**：必须啃透，最少要能讲清以下组件：

  - **Surface Cache**：Card 生成、材质属性缓存
  - **Mesh SDF + Global SDF**：Software Ray Tracing 的底层
  - **Software RT vs Hardware RT** 两条路径的区别
  - **Screen Probes + Radiance Cache** 的 Final Gather
  - **World Space Probes**、Irradiance Cache
  - **Distant Lighting** 用到的 Far Field

  推荐：Krzysztof Narkowicz / Daniel Wright 在 SIGGRAPH 的演讲。

- **Frostbite GI**：Surfel GI + Far Field（GDC/SIGGRAPH 2021）。

- **Unity APV (Adaptive Probe Volumes)**：HDRP 新方案。

- **Godot SDFGI**：开源可读源码，学习成本最低。

### Tier 4：路径追踪进阶（看岗位侧重，离线/RT 渲染相关必学）

- **Path Tracing**：手写一个能跑的 PT 是基本功。

- **BDPT (双向路径追踪)**、**MLT (Metropolis Light Transport)**。

- **Photon Mapping / SPPM**：理解光子图、密度估计、为什么对 caustics 友好。

- **ReSTIR 系列（极其重要的近年热点）**：

  - ReSTIR DI（Bitterli 2020）
  - ReSTIR GI（Ouyang 2021）
  - ReSTIR PT

  RIS + Reservoir 时空复用是当下最 hot 的方向，UE5.4+、新游戏（Cyberpunk PT、Alan Wake 2）都在用。

### Tier 5：降噪与重建（RT 落地的关键）

- **SVGF / A-SVGF**：时空滤波，理解 Variance Estimation。
- **NRD (NVIDIA Real-time Denoiser)**、**OIDN**。
- **TAA / DLSS / FSR**：跟降噪强耦合，理解 jitter、history rejection、disocclusion。

------

### 学习顺序建议

按 Tier 顺序走，但是 Tier 1/2/3 可以交叉。如果时间有限，给你一个**应急路线**：

渲染方程 → BRDF → MC + 重要性采样 → SH/Light Probe → RSM → SSAO/SSR → VXGI 思想 → DDGI → Lumen → ReSTIR

### 面试常见提问角度（让你校准学习深度）

1. "讲一下 Lumen 的整个流程"（必出）
2. "DDGI 和 VXGI 的对比、各自漏光原因"
3. "SH 为什么用 L2、能不能表示 specular"
4. "ReSTIR 的 reservoir 怎么时空复用、bias 哪里来"
5. "实现一个 PT，怎么减少方差"
6. "MIS 的权重怎么算、为什么 balance heuristic 不是最优"
7. "Surfel 和 Probe 方案的本质区别"

需要的话我可以挑其中某一块（比如 Lumen 或 ReSTIR）展开讲，或者给你列对应的 paper / talk 清单。