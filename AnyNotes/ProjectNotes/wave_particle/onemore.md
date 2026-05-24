# 实时河流渲染技术方案对比与选型报告

> 面向：游戏引擎水体渲染（已有基于 Clipmap 的 FFT 海洋管线，拟新增河流渲染特性） 目标：分析当前工程上主流/前沿河流渲染方案的技术细节、优缺点，论证 CDLOD + Wave Particles 路线的合理性，并给出可作为研究生毕业课题的创新方向。

------

## 0. TL;DR（结论先行）

- 河流渲染本质上是 **几何 LOD + 流向运输 + 局部波形 + 着色** 四个子问题的组合。任何"单一技术"都无法独立支撑生产可用的河流，所有 AAA 方案都是 hybrid pipeline。
- 当前生产环境的事实标准是 **Uncharted 4 路线**：CDLOD 几何 + flow map 流向场 + Wave Particles 高频形态 + 离线 FLIP/SPH 烘焙 + 屏幕空间 foam/refraction。该方案已被验证可在 30/60fps 预算内交付电影级视觉。
- 学术界 2018 年起出现两条新的 Lagrangian 替代路径：**Wave Profile Buffer (Grenier, Ubisoft/Unity)** 和 **Water Surface Wavelets (Jeschke et al., NVIDIA/ISTA)**。两者都解决了 wave particle 的若干工程痛点（repetition、pulsing、与障碍物耦合），但成本与工业部署成熟度尚不及 Uncharted 4 路线。
- 在已有 FFT clipmap 海洋管线的前提下，推荐 **CDLOD + Wave Particles + 可选的 Wave Profile Buffer 升级路径**。可复用现有 FFT 频谱基础设施做混合 displacement，复用 clipmap 的地形采样代码做河床查询。
- 创新点（详见 §7）建议围绕 **(a) GPU-driven wave particle spawning + mesh shader culling**、**(b) 与已有 FFT 频谱的 spectral-consistent 混合**、**(c) 离线 FLIP 数据驱动的 Wavelet 系数 baking**、**(d) 与刚体物理的双向耦合**、**(e) 神经压缩 flow field** 这五条方向之一展开。

------

## 1. 河流渲染的子问题分解

不区分子问题就比较方案会导致"苹果比橘子"。任何方案都应在以下五个维度上分别评估：

| 子问题                   | 描述                                                   | 主流技术族                                                   |
| ------------------------ | ------------------------------------------------------ | ------------------------------------------------------------ |
| **G. 几何/LOD**          | 在屏幕上以合理的三角形密度覆盖大范围、长条形的河道几何 | Clipmap、Projected Grid、CDLOD、Hardware Tessellation、Mesh Shaders |
| **F. 流向场**            | 表征水沿河道方向流动的速度场，驱动纹理/粒子/UV 运动    | 美术绘制 flow map、离线 CFD 烘焙、运行时 SWE 求解、Stream Function |
| **W. 波形/displacement** | 决定水面起伏的形状（毛细波、激流、滚浪、涡旋）         | Normal map scrolling、Gerstner sum、FFT (Tessendorf)、Wave Particles、Wave Packets、Wavelets、iWave、SWE 高度场 |
| **S. 表面着色**          | 反射、折射、subsurface、菲涅尔、foam、caustics         | SSR/Planar Reflection、屏幕空间 refraction、SSS LUT、生成式 foam、ray-traced caustics |
| **C. 交互/耦合**         | 玩家/物体进入水中的扰动、河中障碍物绕流、白沫飞溅      | 局部 ripple buffer、Boundary sampling、SPH/PBF 飞溅、双向 rigid-fluid coupling |

河流相比海洋的关键差异：

1. **存在主导流向**：FFT/Gerstner 的"各向同性能量谱"假设不成立；必须有 **平流（advection）**。
2. **非周期、与地形耦合**：海洋假设无限远场和平底；河流必须贴合河床、被两岸限制（Dirichlet 边界）。
3. **局部细节比远场大尺度更重要**：玩家通常贴近河岸观察激流/涡旋，而非远眺。
4. **频谱不同**：河流以高频毛细波 + 局部冲击波为主，缺少海洋的长重力波。

理解这五个维度后，下面分两章梳理 **几何方案** 与 **波形方案**，最后做对比矩阵。

------

## 2. 几何与 LOD 技术

### 2.1 Clipmap（geomipmap / toroidal clipmap）

**核心算法**

- 围绕摄像机生成 N 个嵌套的同心环形（toroidal）网格，每一层分辨率相同但世界空间尺度按 2× 递增。
- 顶点位置在 vertex shader 中由 `floor(camPos / cellSize) * cellSize + localOffset` 给出，从而当摄像机移动时网格在世界空间"晃动"而不抖动。
- 高度采样使用 trilinear morphing 在层间过渡，避免 LOD pop。

**用于河流的工程细节**

- 通常配合一张"水体存在 mask"图集，clipmap 顶点采样到陆地处会把高度推到 -inf 或通过 alpha 丢弃。
- 顶点数固定，对带宽友好，对 vertex throughput 也固定，可严格控制 frame budget。

**优点（具体）**

- 实现简单，与已有 FFT 海洋管线（你们的现状）天然兼容：可以用同一份网格、同一份 displacement，仅在着色器里乘上一个 mask。
- 顶点缓冲区是静态的，drawcall 极少（每层一个 instance），适合移动端/弱平台。

**缺点（具体）**

- **完全为开放海洋设计**：clipmap 的拓扑是矩形/方形环，对河流"细长曲线带状"形状非常浪费 —— 大部分顶点在岸上被丢弃。屏幕外有效顶点利用率常 < 30%。
- 无法表达**沿河岸 sharp boundary**：河岸通常是 m 级的尖锐边界，clipmap 在边界处会 popping 或漏水（顶点不在岸线上）。
- 在弯道处由于网格无法对齐流向，flow map 的纹理坐标会出现拉伸/压缩。

**结论**：clipmap 不适合作为河流的主网格方案，但**可以作为远场河流（远到无法看清细节）的退化方案**与 CDLOD 衔接。

------

### 2.2 Screen-Space Projected Grid（Johanson 2004 / Bruneton 2010）

**核心算法**

- 在 NDC 空间放置规则网格，将每个顶点反投影到 y=0 平面，再 displacement。
- 配合 frustum 优化（"projector matrix"），保证 grid 紧贴可见区域。

**用于河流**

- Bruneton 在 2010 GDC ocean talk 里用过此法。

**优点**

- 屏幕利用率 100%。
- 与分辨率天然耦合，远处自动稀疏。

**缺点（致命）**

- **不能表达多个不连通的水体**：projector 假设水面是一个 z = h(x,y) 单射函数。河流分支、瀑布、悬空水帘、不同高度的多条河流（高低台地）全部失败。
- 与地形 occlusion 不友好：被山遮挡的远处河流仍然会被反投影出顶点，需要额外 culling。
- 当河道窄于一个屏幕格时容易丢顶点出现"水面波动断断续续"。
- 难以预先 stream 资源（无法预知哪段河流将被显示）。

**结论**：projected grid 是海洋方案，不适合河流。

------

### 2.3 CDLOD —— Continuous Distance-dependent Level of Detail（Strugar 2009/2010）

**核心算法**

- 将平面/曲面切分为四叉树 patch。
- 每个 patch 是同一份 N×N regular grid，shader 中根据距离决定 morph factor：

```
morphFactor = saturate( (dist - morphStart) / (morphEnd - morphStart) )
finalPos = lerp(coarsePos, finePos, morphFactor)
```

其中 coarsePos 是把当前顶点 snap 到上一层分辨率的位置，finePos 是原始位置。这样**两层 patch 在边界处天然连续**，无 T-junction。

- 通常用 CPU/compute shader 做四叉树 selection，输出 instance 列表（每个 patch 一个 instance），GPU 用 instancing 绘制。

**用于河流的工程细节（Uncharted 4 风格）**

- 河流被表示为**沿河中心线（spline）参数化**的 1D 段，每段持有：
  - bounding box / OBB
  - local-to-world 仿射或 spline-arc-length 弧长映射
  - "u 沿河宽，v 沿河长" 的局部 UV
- 四叉树 selection 改为 **沿 spline 的 1D LOD + 沿河宽方向恒定细分** 或 **2D 局部网格但 OBB 拒绝远处片段**。
- 每段河流自己存一张高分辨率 flow map，CDLOD 顶点 fetch 该 flow map 后做 displacement。

**优点（具体）**

- **完美适配长条/弯曲的水体**：四叉树/spline 分段使河流的有效顶点利用率接近 100%。
- 连续 morphing 几乎零 popping。Strugar 论文实测 64×64 patch 在 5–10 个 LOD 层级下 vertex pop ≤ 1 像素。
- 与 hardware tessellation 兼容：可以把 CDLOD 选好的 patch 再丢给 tess。Uncharted 4 实际是 CDLOD + 边缘 tess 的混合。
- 内存友好：所有 patch 共享同一份 IB（index buffer），只切换 instance 数据。
- 与你们已有的 FFT clipmap 共用部分代码（同样是 morph + nested grid 思想）。

**缺点（具体）**

- 实现复杂度高于 clipmap，需要四叉树/spline 的 CPU 端管理与一套 culling pipeline。
- patch 边缘的 morphing 需要保证邻接 patch 的 LOD 差异 ≤ 1，否则会有缝（standard CDLOD constraint）。
- 河流分叉（Y 型汇流）需要美术显式建模 spline 拓扑。

**结论**：**CDLOD 是河流几何的当前最佳工业实践**。Uncharted 4、Far Cry、Horizon 系列都使用了类似的 spline-quadtree 河流几何。

------

### 2.4 Hardware Tessellation（Phong / PN Triangles + Distance-based factor）

**核心算法**

- 在 Hull/Domain shader 中根据屏幕空间 edge length 计算 tessellation factor，DX11+/Vulkan 原生支持。
- displacement map 在 Domain shader 中 fetch。

**优点**

- 实现极简，对美术友好（直接喂 mesh + displacement map）。
- 可与任何上层方案配合作为"最后一公里"的细分。

**缺点（具体且严重）**

- Tessellator 的 inside/outside factor 是单 patch 局部决定的，跨 patch 容易出现裂缝；解决方案（fixed-edge factor）会浪费三角形。
- 在 GCN 之前的硬件上 tess 单元是瓶颈；即便在 RDNA2/Ampere 上 tess factor > 16 也会显著 stall。
- 无法表达 LOD 间的 morphing —— 边缘 tess factor 改变时仍会有跳变（geomorphing 仅在某些专用扩展下可用）。
- **没有 CDLOD 的连续性保证**，单独使用难以避免远距离 popping。

**结论**：tessellation 不应作为河流的主 LOD 方案，但可与 CDLOD 配合使用作 micro-displacement。

------

### 2.5 Mesh Shaders / GPU-Driven LOD（Nanite-style 思想）

**核心算法**

- 用 mesh shader 直接 emit 顶点/图元，跳过传统的 IA/VS/HS/DS 管线。
- 每个 meshlet (~64 顶点 ~124 三角形) 独立 culling 与 LOD selection。
- Nanite 进一步引入 cluster hierarchy 与 software rasterizer 用于亚像素级 LOD。

**用于河流**

- 目前没有公开发表的、专门为河流设计的 mesh-shader 方案。理论上可以把 CDLOD 的 patch selection 完全搬到 task/mesh shader 中，每个 meshlet 处理一段 spline-arc。

**优点**

- 完全 GPU-driven，CPU readback 为零。
- meshlet 级 frustum / occlusion / backface culling 大幅减少无效顶点。
- 与 work-graphs / GPU-driven rendering 趋势一致。

**缺点（具体）**

- mesh shader 在中低端 GPU 上仍未普及；移动端基本不支持。
- 工具链/profiler 成熟度低；调试困难。
- 没有现成的 displacement-aware LOD metric（Nanite 自己也不做大幅 displacement）。

**结论**：mesh shader 是未来方向，但**目前不应作为 baseline**。可作为 Phase 2 升级路径或本课题的创新点之一。

------

## 3. 表面运动 / 波形构建技术

下面是河流渲染最核心、也最分化的部分。这里逐一展开主流方案，重点放在**算法实质**而非视觉效果。

### 3.1 Flow Map（Vlachos 2010, Portal 2 / Left 4 Dead 2）

**核心算法**

给定一张 2D 矢量场纹理 `F(u,v) = (fx, fy)`（通常存在 RG 通道，0.5 = 零流速），shader 中：

hlsl

```hlsl
float2 flow = (tex2D(flowMap, uv).rg - 0.5) * 2.0 * flowStrength;
float t = frac(time * cycleSpeed);          // 0..1
float2 uvA = uv - flow * t;
float2 uvB = uv - flow * (t - 0.5);          // 错相 0.5
float blend = abs(2 * t - 1);                // 三角波，0->1->0
float3 nA = SampleNormalMap(uvA);
float3 nB = SampleNormalMap(uvB);
float3 N  = lerp(nA, nB, blend);
```

两张 phase 错开 0.5 的采样交叉淡化，避免单次 UV 推移过远时纹理被严重拉伸 —— 这是 Vlachos 的关键贡献。

**改进**

- 加入 noise 扰动 phase（避免 pulsing 同步可见）。
- 在 G 通道加入 foam strength，B 通道加入 wave amplitude（Uncharted 系列）。
- flow map 通常 32×32 ~ 256×256，再用美术工具（Houdini / 自研 Editor）绘制。

**优点（具体）**

- **极廉价**：每个顶点 2 次纹理采样 + 1 次 lerp。在移动端可跑。
- 完全确定，无 simulation cost，无网络同步问题。
- 美术控制力强：可以画任意花式流向。

**缺点（具体）**

- **完全 2D，没有"高度感"**：水面看起来像在"流动的贴花"而非有起伏的水。这是 Uncharted 4 团队选择放弃单纯 flow map 的核心原因（参见 [Rendering Rapids in Uncharted 4, Gonzalez-Ochoa 2016]）。
- **Pulsing 伪影**：交叉淡化造成的明暗周期性波动，在静态镜头下肉眼可见。
- **不能与障碍物正确交互**：石头后面应有 wake、应有 dead zone，flow map 无法体现，只能美术手画。
- 信息密度低：256×256 flow map 即使覆盖 100m 河段，每米也只有 2.56 个样本，无法表达 sub-meter 涡旋。

**结论**：flow map 作为 **流向场 (F)** 的载体仍是行业标准，但**作为完整波形方案不再够用**。Uncharted 4 之后的所有 AAA 河流都把 flow map 降级为输入，把 displacement 交给 wave particles 或更高级方案。

------

### 3.2 Gerstner Waves（Sum of trochoids）

**核心算法**

对每个波 i 给定方向 D_i、波数 k_i、振幅 A_i、相位速度 ω_i：

```
x(p, t) = p.x + Σ (Q_i * A_i * D_i.x * cos(k_i · p - ω_i * t))
y(p, t) = Σ (A_i * sin(k_i · p - ω_i * t))
z(p, t) = p.z + Σ (Q_i * A_i * D_i.z * cos(k_i · p - ω_i * t))
```

通常 4~8 个波叠加，加上数张高频 normal map 修饰。

**用于河流的尝试**

- 早期 Uncharted（Drake's Fortune）的小溪用 4 个 Gerstner 模拟水流被拉伸的"行进波"，但视觉极为不真实。

**优点**

- 解析、可求导（精确 normal）。
- 几乎零成本。

**缺点（致命）**

- 假设无限远场、无方向偏好；河流的"全部水都朝下游流"无法表达 —— 必须把全部 D_i 设为 flow direction，但这样 4 个 Gerstner 退化为 1 个。
- 无 advection 概念：波相对水面是平稳行进的；河流应是波形被水流"载着走"。
- 周期性肉眼可见。

**结论**：单独不适合河流。可以作为 wave particles 之上的"远场低频补充"（但通常不需要，因为河流的低频信息已被 mesh 高度场承担）。

------

### 3.3 FFT-based (Tessendorf 2001) + Flow Distortion

**核心算法**

- 在频域用 Phillips/JONSWAP 谱采样 ~Gaussian 复数振幅，IFFT 得到高度场和水平 choppy 位移。
- 你们的现有海洋系统已经是这个。

**复用为河流的几种 hack**

1. **Domain warp 法**：把 FFT 高度图采样的 UV 用 flow map 沿流向滚动后再采样。`h = FFT(uv - flow*t)`。
2. **方向化谱**：在 Phillips 谱中把方向函数 `cos²(θ - θ_wind)` 的指数提高到 16~32，得到强方向性，θ_wind 设为 flow 方向。

**优点**

- 零额外基础设施：直接复用 FFT pipeline。
- 多分辨率（cascade FFT，你们应该已有）天然提供 mip-like LOD。

**缺点（具体）**

- **方向化谱治标不治本**：FFT 仍是空间周期的（典型 256² @ 50m），无法表达河流"水沿弯道转向"的现象 —— FFT tile 内方向场是常量。
- Domain warp 后高频细节被拉伸，分辨率不足以表达激流。
- 没有边界条件：不能让波在石头处反射或被消散。
- 在 cascade 之间做 flow warp 容易出现 inter-cascade discontinuity。

**结论**：FFT 不能独立支撑河流。但作为 **wave particles 系统之外的远场低频补充** 是可行的，且与你们现有管线复用度高（见 §6 推荐方案）。

------

### 3.4 Wave Particles（Yuksel et al. 2007 + Uncharted 4 改造）

**核心算法**

原始 Yuksel 2007：

- 每个粒子是一个具有 **位置 p、振幅 a、半径 r、传播方向 d、传播速度 c** 的圆盘形 wavefront 元素。
- 它对水面高度的贡献是一个径向 cosine envelope：

```
h_i(x, t) = 0.5 * a_i * (cos(π * |x - p_i(t)| / r_i) + 1)   if |x - p_i(t)| < r_i
         = 0                                                    otherwise
```

随时间 p_i 沿 d 移动，r 随距离扩展（保能量近似）。

- 全场高度是所有粒子求和：`h(x,t) = Σ h_i(x,t)`。
- **关键 trick**：求和在一张较粗的 "particle grid texture" 上完成（粒子被 splat 进网格），然后 grid 通过双线性插值给顶点用。

**Uncharted 4 的关键改造**（Gonzalez-Ochoa 2016）：

1. **沿 flow map 的方向 advect 粒子**：不再是各向同性扩散，而是被流场载着走。
2. **多层 stacking**：3~5 张不同尺度的 wave particle grid 叠加，每张负责不同空间频率。
3. **离线 FLIP/Houdini 模拟产生"种子粒子"，并烘焙到 flow grid 中**（参见 SideFX 的官方 PostMortem）。
4. **flow grid 同时编码** flow direction、wave amplitude modulation、foam strength —— 一张图 4 个通道全用。
5. 在 mesh 顶点上 evaluate displacement = 4×Gerstner（海洋部分）+ 4× wave particle grid 采样。

**优点（具体）**

- **能正确表达"有高度感的流动水"**：粒子被 advect 而波形仍朝某个相对方向传播，体现激流的视觉特征。
- **天然支持局部交互**：玩家进入水中或扔石头都可以 spawn 新的粒子，立即产生涟漪。Uncharted 4 就用这个做了水花/船只 wake。
- **空间稀疏**：远处无粒子的水域几乎零成本。
- 离线 + 运行时 hybrid：核心激流粒子用 FLIP 烘焙得到，运行时只做 advect + splat + sum，性能极稳定。
- 已被 PS4 时代验证可在 5–8 ms（包含 mesh）内完成。

**缺点（具体，重要）**

1. **粒子寿命有限 → repetition**：每个粒子在 lifetime 内的 envelope 是确定函数，大量同寿命粒子重复 spawn 会形成可见周期。
2. **Pulsing**：粒子衰减/重生造成的"明暗呼吸感"，与 flow map 一样的问题。Naughty Dog 用 noise 扰动 + 多层 stacking 缓解。
3. **粒子 splat 到 grid 后丢失精确相位**：高频细节实际受限于 grid 分辨率。
4. **不能正确反射/绕射**：粒子只朝既定方向传播，遇到石头不会反射回来。需要美术手画反射粒子。
5. **粒子管理（spawn / despawn / lifetime / density control）需要复杂的 CPU/GPU 调度**，特别是大规模河流。

**结论**：Wave Particles 是目前 **生产环境唯一同时具备方向性 + 高度感 + 局部交互** 的方案，是 Uncharted 4 路线的核心。但其 repetition 与 pulsing 问题在 2018 年才被 Grenier 的 Wave Profile Buffer 较好解决（见下节）。

------

### 3.5 Wave Profile Buffer（Grenier 2018, Ubisoft → Unity；后被申请专利）

**核心思想**

Wave Particles 之所以会 pulsing/repetition，是因为每个粒子的高度贡献是一个**有限时长的、固定形状**的 envelope。Grenier 的关键洞察是：把"波的运动"和"波的形状"分离 ——

- 一张**很大的 2D Wave Amplitude Field**（典型 1024²+）存"在每个空间位置、沿每个方向 θ_k 的波振幅"。这是 Lagrangian 的离散：把无数粒子的影响 sum-and-average 到 field 上。
- 一张 1D 的 **Wave Profile Buffer**：`P(s)`，s ∈ [0, 1)，是一个**单一波周期内的波形函数**（可以是预计算的 sinusoid、Stokes 波、breaking wave 形状等）。
- 在采样 vertex 高度时：

```
h(x, t) = Σ_θ  A(x, θ) * P( (k · x - ω*t) mod 1 )
```

其中 θ 离散为 ~16 个方向 bin，A 通过 advection + diffusion PDE 在 GPU compute 上更新。

- 优势是 **波形（P）可以无周期连续滚动而 Amplitude Field 缓慢更新**，从而消除 wave particles 的"envelope 寿命"。

**用于河流（Grenier demo + 后续开源复现）**

- demo 中是一个交互式 River Editor：玩家可以实时在场景里放石头，flow 重新求解，A field 自动更新（相当于运行时 SWE 与 wave field 解耦合）。
- 后续开源复现：`ACskyline/Wave-Particles-with-Interactive-Vortices`、`LanLou123/waveparticle`（DX12 实现）。
- 已被申请美国专利（US 11,010,509 B1，"Systems and methods for computer simulation of detailed waves for large-scale water simulation"），但权利要求覆盖的是 wave-amplitude-grid + advection + 1D wave profile buffer 的组合，**纯学术或非商用复现不受影响**。

**优点（具体）**

- **消除 wave particle 的 pulsing 与 repetition**：因为 P(s) 是连续相位推进、A 是平滑更新的密度场。
- **天然支持流向变化**：A field 自带 θ 维度，沿不同方向有不同振幅，弯道时不需要重新生成粒子。
- **可与 SWE 结合**：A 的 advection-diffusion 与 SWE 共用 velocity field。
- 显存可控：A 是 `W × H × N_θ`（如 512×512×16 = 4M 样本，每样本 R16F = 8 MB）。

**缺点（具体）**

- **A field 仍受空间分辨率限制**：超出 Nyquist 的高频细节丢失，需要在 surface shader 端再叠一层 detail normal map。
- 方向 bin 离散数 N_θ 决定方向分辨率：N_θ=8 时各向异性可见明显锯齿。
- **专利风险（商用产品）**：US 11,010,509 B1 的权利要求 1 描述了完整 pipeline；商业引擎可能需要绕过或授权（详见 §7.8 风险分析）。
- 工业部署案例少：Grenier demo 是个人技术 demo，目前没有公开的 shipping AAA 游戏使用，工程坑较多需自己踩。

**结论**：Wave Profile Buffer 是**学术上更优、视觉上更连贯**的 wave particle 替代方案，但工业成熟度落后于 Uncharted 4 路线 2~3 年。**强烈推荐作为本项目的 Phase 2 升级路径或核心创新点**。

------

### 3.6 Water Surface Wavelets（Jeschke et al. SIGGRAPH 2018, NVIDIA + ISTA）

**核心思想**

把 2D 水面波动写成在 **(空间 x, 频率 k, 方向 θ)** 上的 6D 振幅函数 A(x,k,θ,t)，并发现这种"包络变量"远比直接的高度场 h(x,t) 变化得慢，从而可以**大幅放宽 CFL 与 Nyquist 限制**：

- 高度场 h 直接模拟要求 grid 间距 < λ/2 且 dt < CFL；
- 振幅场 A 只需要捕捉 "几何光学" 尺度上的传播，dx 与 dt 都可放大 1~2 个数量级。

PDE：

```
∂A/∂t + c_g(k) · ∇_x A = -D · A + S(x,k,θ,t)
```

c_g 是群速度，D 是耗散，S 是源项（船只 wake、雨、风等）。求解在 GPU compute 上用 semi-Lagrangian 平流完成。

最终在渲染时用一个 **Wave Profile Buffer**（注意：与 Grenier 的命名相同但内涵稍不同，是 NVIDIA Macklin 等人在 2018 年同年提出）把 A 转换为可视的 height field：

```
h(x,t) = Σ_{k,θ}  A(x,k,θ,t) * cos(k * (cos θ * x + sin θ * y) - ω(k) * t)
```

实践中 k 和 θ 都离散成 8~16 bin。

**用于河流**

- 论文 demo 直接展示了 river-like 场景：波从上游来，遇到桥墩反射，下游产生 wake。完全实时。
- **支持 precomputed wave paths**：可以离线烘焙稳态的 A field，运行时只做时间相位推进，进一步降低成本（适合静态河道）。
- 支持**双向 fluid-solid coupling**。

**优点（具体）**

- **理论最强**：在数学上同时正确处理 Fourier (远场) 与 Local (障碍物) 两种行为，是当前 SOTA。
- **真正物理正确的反射、绕射、阴影**：石头后面的"安静区"自动出现，不需要美术介入。
- **离线 + 运行时 baking**：稳态 A 可烘焙，运行时极便宜。
- 与已有 FFT 谱**理论上完全兼容**：振幅 A 的源项可以来自 Phillips 谱。

**缺点（具体）**

- **存储成本高**：5D 离散 (x,y,k_bin,θ_bin) = 512×512×8×16 ≈ 32 M samples，按 R16F 算 64 MB；在主机/移动端是显著开销。
- **实现复杂度高**：semi-Lagrangian 在 6D 空间需要小心；论文虽提供完整算法但实现仍需 1~2 人月。
- **shipping 案例尚无公开报道**：截至 2024-2026 年仍主要是学术与 NVIDIA tech demo。生产风险中等偏高。
- 与 Uncharted 4 的 art-directed 流向控制结合不直观（论文的源项是物理设定，不是美术绘制 flow map）。

**结论**：技术上的"终极形态"。**推荐作为研究路线的 stretch goal 或硕士论文创新点**，但作为 production baseline 风险偏高。

------

### 3.7 Shallow Water Equations (SWE) / Pipe Model

**核心算法**

SWE 是从 Navier-Stokes 在 "水深 << 横向尺度" 假设下积分得到的 2D 守恒律：

```
∂h/∂t + ∇·(h u) = 0                            (质量守恒)
∂(hu)/∂t + ∇·(h u ⊗ u + 0.5 g h² I) = -g h ∇b - τ_f    (动量守恒)
```

其中 h 是水深，u 是 2D 水平速度，b 是河床高程，τ_f 是摩擦项。

**实时实现的两种主流离散**：

1. **Finite Volume + HLLC Riemann solver**（科学计算路线，Brodtkorb 2010, Lacasta 2014）：精度高，但每 cell 多次 flux 计算，GPU 上 ~2-3 ms/512² grid。
2. **Pipe Model**（Mei et al. 2007, "Fast Hydraulic Erosion Simulation and Visualization on GPU"）：将 cell 之间用"虚拟管道"连接，管道流量由邻居 cell 的高度差驱动，更新极简单：

```
flux[i->j]  = max(0, flux_prev + dt * A_pipe * g * (h_i - h_j) / L_pipe)
h_i_new = h_i + dt * Σ flux  / cellArea
```

Pipe model 是 ~0.5 ms/512² grid 级别，已被 Frostbite 等引擎用过。

**用于河流的工程现状**

- **离线模拟 + 烘焙**：Naughty Dog、Ubisoft 都先用 SWE/FLIP 模拟河流，把稳态的 velocity / depth / surface curvature 烘焙到 flow map / amplitude grid。
- **运行时局部 SWE**：在玩家周围 ~30m 半径内动态求解，用于船的 wake、爆炸的局部波。Atlas (Studio Wildcard, 2019 GDC) 用此方案做交互式 wake。

**优点（具体）**

- 物理正确：流速、水深、波速 c = √(gh) 全部自洽。
- 自然处理障碍物：把 cell 设为 solid（h=0）即可。
- 支持洪水、溃坝、急流的可信视觉。

**缺点（具体）**

- **不解高频波**：SWE 是浅水"长波"近似，只能解 wavelength >> water depth 的波。河流上的毛细波、风浪必须由别的方法（如 wave particles）补充。
- 显存：512×512 grid 至少 8~16 MB（h + 2D u + flux）。
- 全局 SWE 在 100m+ 河段成本不可接受；通常只在 30m 局部 patch 跑。
- CFL 限制 dt：dt < dx / (|u| + √(gh))；激流场景 dt 可能小到 1ms 量级，需要 sub-stepping。

**结论**：SWE **不应作为河流的视觉 displacement 主力**，但是 **flow field 离线 baking 的工具**和 **运行时局部交互（wake、splash）的物理基础**。生产中是配角，不是主角。

------

### 3.8 iWave / Wave Equation Grid（Tessendorf 2008）

**核心算法**

直接在规则 grid 上离散 2D 线性波方程：

```
∂²h/∂t² = c² ∇² h - γ ∂h/∂t + S(x,t)
```

用 explicit leap-frog 或半隐式 Crank-Nicolson 推进。Tessendorf 的 iWave 是个有趣的频域加速变体：把 Laplacian 写成 IFFT(- |k|² FFT(h))，可在 N log N 时间解。

**用于河流**

- 罕见，因为不天然包含 advection。可以加 advection 项 `+ u·∇h` 但稳定性变差。

**优点**

- 实现简单。
- 与 FFT 海洋管线高度复用。

**缺点（具体）**

- 没有方向性，纯各向同性扩散。
- 高频部分受 CFL 严格限制。
- 障碍物处理用 Dirichlet 边界，但 grid 网格化与河岸不对齐时易抖动。

**结论**：iWave 比 SWE 还不适合河流。可忽略。

------

### 3.9 SPH / FLIP / PBF（Position-Based Fluids）

**核心算法**

完全 3D 的拉格朗日方法：用粒子离散流体，相邻粒子之间用核函数 W(r,h) 计算密度、压力、粘性。

- SPH（Müller 2003 起）：经典平滑粒子流体动力学。
- PBF（Macklin & Müller 2013）：位置约束求解，每帧迭代 Jacobi。
- FLIP（Zhu & Bridson 2005）：混合粒子-网格，粒子运 velocity，网格做不可压投影。

**用于河流的工程现实**

- **运行时**：仅用于 **局部小尺度** —— 瀑布、水花、玩家溅起的水珠、船头的 spray。生产引擎如 Unreal Niagara、Unity VFX Graph 都集成了 GPU SPH/PBF 模块。
- **离线**：FLIP 用于烘焙 flow map / amplitude / foam mask。Naughty Dog 在 Houdini 里跑 FLIP 来产生 Uncharted 4 河流的 ground truth 数据。

**优点（具体）**

- 完整的 3D 物理：包括破碎、混合、splash。
- 与刚体耦合天然双向。

**缺点（具体）**

- 计算量随粒子数 O(N) 但常数大，~50k 粒子已是中高端 GPU 的极限。
- 表面重建（marching cubes / anisotropic kernels）是另一笔大开销。
- 不适合大体积（一条 200m 长河流可能需要数百万粒子）。

**结论**：粒子方法是 **特效层** 而非 **主水面层**。用于瀑布、水花、wake 的 secondary VFX。

------

## 4. 综合对比矩阵

### 4.1 几何 LOD 方案对比

| 方案           | 顶点利用率  | 实现成本 | 弯曲河流适配       | LOD 平滑度  | 与现有 FFT clipmap 兼容 | 推荐场景                |
| -------------- | ----------- | -------- | ------------------ | ----------- | ----------------------- | ----------------------- |
| Clipmap        | 30~50%      | 低       | 差                 | 中          | ★★★★★（已有）           | 远场退化方案            |
| Projected Grid | 100%        | 中       | 不适用（单射限制） | 中          | ★★                      | 不推荐河流              |
| CDLOD          | 95~100%     | 中高     | 优                 | 优（morph） | ★★★★                    | **主网格方案**          |
| HW Tess        | N/A（叠加） | 极低     | N/A                | 差          | ★★★                     | micro displacement 配角 |
| Mesh Shader    | 100%        | 高       | 优                 | 优          | ★★                      | 未来升级 / 创新点       |

### 4.2 表面波形方案对比

| 方案                   | 流向支持 | 局部交互 | 反射绕射    | 高频细节           | 显存         | GPU 成本       | 工业成熟度          | 周期/Pulsing               |
| ---------------------- | -------- | -------- | ----------- | ------------------ | ------------ | -------------- | ------------------- | -------------------------- |
| Flow Map               | ★★★★     | ★        | ×           | 取决于 normal map  | <1MB         | <0.5ms         | ★★★★★               | 明显                       |
| Gerstner               | ×        | ×        | ×           | 差                 | 0            | <0.1ms         | ★★★★★               | 周期可见                   |
| FFT (Tessendorf)       | ×        | ×        | ×           | 优                 | 4~16MB       | 1~3ms          | ★★★★★（海洋）       | 周期 hidden by domain warp |
| Wave Particles         | ★★★★     | ★★★★     | ×           | 中                 | 2~8MB        | 1~3ms          | ★★★★（Uncharted 4） | 明显但可缓解               |
| Wave Profile Buffer    | ★★★★★    | ★★★★     | ×           | 中                 | 8~16MB       | 2~4ms          | ★★（demo）          | **基本消除**               |
| Water Surface Wavelets | ★★★★     | ★★★★★    | ★★★★★       | 中高               | 32~64MB      | 3~6ms          | ★（学术）           | 基本消除                   |
| SWE / Pipe Model       | ★★★★★    | ★★★★★    | ★★★（边界） | ×                  | 8~16MB       | 1~5ms          | ★★★                 | N/A（无周期）              |
| iWave                  | ×        | ★★★★     | ★★★         | 中                 | 4~8MB        | 1~2ms          | ★★                  | N/A                        |
| SPH/FLIP/PBF           | ★★★★★    | ★★★★★    | ★★★★★       | ★★（取决于粒子数） | 几十~数百 MB | 2~10ms（局部） | ★★★（特效层）       | N/A                        |

> 注：GPU 成本是 1080p、PS5/RTX 3070 量级估算，且只包含波形求解，不含 mesh、shading、reflection。

### 4.3 完整管线"组合"对比（按生产案例）

| 游戏 / 方案                     | 几何                 | 流向                      | 波形                                      | 交互               | 备注                         |
| ------------------------------- | -------------------- | ------------------------- | ----------------------------------------- | ------------------ | ---------------------------- |
| Uncharted 3 (2011)              | mesh + 局部 grid     | flow map                  | flow map UV scroll + normal map           | ×                  | Drake's Fortune 风格         |
| Portal 2 / L4D2 (2010)          | static mesh          | flow map                  | flow map UV scroll (Vlachos)              | ×                  | 经典 baseline                |
| **Uncharted 4 (2016)**          | **spline-CDLOD**     | **离线 FLIP → flow grid** | **wave particles (×4 stacks) + Gerstner** | **粒子 spawn**     | **工业 SOTA**                |
| Atlas (2019)                    | clipmap              | 全局 + 局部 SWE           | Gerstner + FFT + 局部高度                 | SWE-based wake     | 海洋 + 局部交互              |
| Sea of Thieves (2018)           | mesh / projected     | /                         | Gerstner sum + 美术控制                   | 船周围局部高度修改 | 风格化优先                   |
| RDR2 (2018)                     | spline+CDLOD-like    | flow map + 局部 sim       | Gerstner + 高度 sim                       | 物理交互高度 sim   | "Water Physics Quality" 4 级 |
| Horizon Forbidden West (2022)   | projected/CDLOD 混合 | 美术 + 局部 sim           | FFT + 二级 ripple                         | 局部 ripple buffer | 风浪与海岸交互优秀           |
| Wave Profile Buffer demo (2018) | mesh                 | 实时局部 SWE              | wave profile buffer + amplitude grid      | 全交互             | 学术 / Grenier demo          |
| Water Surface Wavelets (2018)   | mesh                 | 由 wavelet 推断           | wavelet 6D PDE                            | 全交互             | NVIDIA tech demo             |

------

## 5. 推荐方案与论证

### 5.1 推荐路线：CDLOD + Flow Map + Wave Particles（Uncharted 4 路线）+ 可选 Wave Profile Buffer 升级路径

```
┌─────────────────────────────────────────────────────────┐
│ Offline (Houdini / 自研 FLIP):                          │
│   FLIP simulation → flow grid (RG flow, B amp, A foam) │
│                  → seed wave particle 分布              │
└──────────────────────┬──────────────────────────────────┘
                       │ baked assets
                       ▼
┌─────────────────────────────────────────────────────────┐
│ Runtime:                                                │
│  ┌───────────────┐    ┌────────────────────────────────┐│
│  │ Spline-CDLOD  │    │ Wave Particle Simulation       ││
│  │  - 四叉树/弧长 │───▶│  - GPU compute advect          ││
│  │  - patch instancing│ │  - splat to grid             ││
│  │  - morphing   │    │  - lifetime mgmt               ││
│  └───────┬───────┘    └────────────┬───────────────────┘│
│          │                          │                   │
│          ▼                          ▼                   │
│  ┌──────────────────────────────────────────────────┐   │
│  │ Vertex Shader:                                   │   │
│  │   h = FFT_lowfreq(x) + Σ wave_particle_grid_i(x) │   │
│  │   sampled along flow-warped UV                   │   │
│  └──────────────────────────────────────────────────┘   │
│                       │                                 │
│                       ▼                                 │
│  ┌──────────────────────────────────────────────────┐   │
│  │ Pixel Shader:                                    │   │
│  │  detail normals (3 octaves) along flow           │   │
│  │  + Schlick Fresnel + planar/SS reflection        │   │
│  │  + SS refraction + foam mask                     │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 5.2 关键论据

**(a) 与现有 FFT clipmap pipeline 复用度最高**

- FFT 输出仍可作为"远场低频补充"（§3.3 描述的方向化 Phillips 谱）。
- Clipmap 的远场退化可与 CDLOD 河流在距离 ~200m 处无缝接驳（用同一 morph 机制）。
- Wave particle grid 的 splat-and-sample shader 与 FFT IFFT 后的高度场采样接口相同（一张 displacement texture），上层 mesh shader 无需区分。

**(b) 工业验证最充分**

- Uncharted 4 (2016) 已 shipping；自此衍生的方案被 Last of Us 2、Rift Apart、God of War Ragnarök 等多次复用。
- 风险低于 Wave Profile Buffer / Surface Wavelets（学术，shipping 案例少）。

**(c) 性能可预测且可调节**

- 粒子数与 grid 分辨率都是显式可调参数；可针对不同平台（PS5 vs Switch）做明确的 budget。
- 离线烘焙的部分占用 disk 而非 GPU/CPU runtime。

**(d) 美术工作流成熟**

- Houdini → flow grid 的 FLIP-bake workflow 是工业标配。
- Flow map editing 工具与 Maya/Blender/UE/Unity 都有先例。

**(e) 解决"有高度感的流动水"问题**

- 这是单纯 flow map 与单纯 FFT/Gerstner 都做不到的，wave particles 是唯一已验证的方案。

### 5.3 风险与 mitigation

| 风险                                     | mitigation                                                   |
| ---------------------------------------- | ------------------------------------------------------------ |
| Pulsing / repetition 可见                | 多层 stacking（3~5）+ noise phase + 随机 lifetime 抖动       |
| 障碍物绕流不正确                         | 美术 + offline FLIP 时在障碍物附近增加粒子密度 + 反射粒子手画 |
| 弯曲河流的 wave particle advect 数值耗散 | 用 RK2 advect 而非 Euler；网格分辨率随曲率自适应             |
| 与已有 FFT 谱的 phase 失同步             | 用同一 RNG seed 初始化两者                                   |
| 长河流（数 km）的 streaming              | 沿 spline 分 chunk，按距离 streaming flow grid 与粒子集      |

------

## 6. 实施阶段建议（Roadmap）

| Phase                  | 周期估计 | 内容                                                         | 可见交付物             |
| ---------------------- | -------- | ------------------------------------------------------------ | ---------------------- |
| **P0. 基础**           | 2~3 周   | Spline-CDLOD 几何系统；河流编辑器（导入 spline + bounding mesh） | 直河道可渲染、LOD 平滑 |
| **P1. Flow Map**       | 1~2 周   | Vlachos flow shader；Houdini 导出 flow grid pipeline         | 河流"流动"视觉         |
| **P2. Wave Particles** | 4~6 周   | GPU compute advect；splat-to-grid；lifetime mgmt；多层 stacking | 有高度感的激流         |
| **P3. 局部交互**       | 2~3 周   | 玩家/物体 spawn 粒子；wake 粒子；与刚体的简单耦合            | 进水 ripple、船 wake   |
| **P4. 着色**           | 3~4 周   | foam 生成（粒子 + 屏幕空间 + 深度边缘）；SSR；refraction；SSS LUT | 视觉级匹配 Uncharted 4 |
| **P5. 创新点（毕设）** | 6~10 周  | 见 §7                                                        | 论文/技术报告          |

总计 ~5 个月可完成 baseline，剩余时间用于创新研究。

------

## 7. 创新点方向（针对毕业要求）

毕业论文/技术报告需要"非简单复现"的贡献。下面提出 5 条具体方向，每条都给出**可量化的研究问题**、**可对比的 baseline**、**可发表的目标会议/期刊**。可任选 1~2 条深入。

### 7.1 [推荐 ★★★★★] Spectral-Consistent FFT + Wave Particles 混合

**研究问题**

Uncharted 4 直接把 FFT 输出和 wave particles 叠加，没有保证两者频谱一致性。例如，FFT 的 Phillips 谱可能在 k=10 rad/m 处有显著能量，wave particles 在同一波数也有能量，两者无相关性叠加 → **能量谱被错误地翻倍**。

**目标**

设计一个 **频域协调器**，运行时分析当前 wave particle grid 的频谱（用 FFT 取其 power spectrum），从理论 Phillips 谱中**减去**这部分，然后用残差谱驱动 FFT 部分。这样总频谱与设计目标谱一致。

**baseline 对比**

- Uncharted 4 朴素叠加。
- 全 FFT。
- 全 wave particles。

测量：power spectral density vs 理论 JONSWAP/Phillips；视觉细节频谱 vs 真实河流照片的频谱（用拍摄数据）。

**可发表**：I3D / HPG / Eurographics short paper。

**工程价值**：直接落地到你们引擎，FFT pipeline 已有，复用度极高。

------

### 7.2 [推荐 ★★★★] GPU-Driven Wave Particle Spawning with Mesh Shaders

**研究问题**

Uncharted 4 的 wave particle 管理 CPU side 仍有显著开销（spawn / despawn / sort）。在大规模 open-world 河流（10 km+）下不可扩展。

**目标**

用 **task shader → mesh shader** pipeline 把 wave particle 生命周期管理完全 GPU-driven：

- task shader 根据 frustum / occlusion 决定哪些 chunks 需要激活 particles；
- mesh shader 直接 emit 粒子的 splat 几何 ；
- 用 indirect dispatch 在 GPU 上自我调度，CPU readback = 0。

**baseline 对比**：CPU-driven、CPU+GPU hybrid（Uncharted 4 当前）、纯 mesh shader。 测量：CPU time、GPU time、可扩展性（粒子数 100k / 1M / 10M）。

**可发表**：HPG / SIGGRAPH talk / GDC。

------

### 7.3 [推荐 ★★★★] FLIP-Baked Amplitude Field → Wave Profile Buffer 升级路径

**研究问题**

直接采用 Wave Profile Buffer (Grenier 2018) 有专利风险且没有 art-directable workflow。能否设计一个**"Uncharted 4 离线 FLIP → Grenier-style Amplitude Field"** 的烘焙 pipeline，使得：

- 输入仍是美术友好的 flow map + spline；
- 输出是 amplitude field A(x, θ) 而非粒子；
- 运行时用一个**专利无关的、更简单**的 wave profile evaluator。

**目标**

把 Wave Particle 升级为 Wavelet-like 表征，同时绕开 Grenier 专利的核心权利要求（具体绕法：不在 GPU 上做实时 advection-diffusion of A，而是**离线烘焙稳态 A** + 运行时小幅扰动 —— 这避开了专利 claim 1 中"computing wave advection / diffusion in pixel shader"的核心步骤）。

**baseline**：wave particles (UC4)、Wave Profile Buffer (Grenier)、本方案。 测量：pulsing / repetition 的 PSNR（与真实视频对比）、运行时成本、烘焙时间。

**可发表**：SIGGRAPH（如完成度高）/ I3D。

------

### 7.4 [推荐 ★★★] 神经压缩的 Flow Field 表征

**研究问题**

长河流（10 km+）的 flow grid 即便 1m / cell 也需要 10 MB+；若要 sub-meter 精度，存储吃紧。

**目标**

把 flow map + amplitude grid 编码成一个小型 MLP（如 NeRF-style 的 frequency-encoded MLP，或 Instant-NGP 的 hash grid），用神经网络压缩。运行时 vertex/pixel shader 中 inference。

研究点：

- 压缩比 vs 视觉质量；
- inference 在 vertex shader 中的成本（每顶点几次 ALU vs texture fetch）；
- 与现有 flow map 的兼容性（fallback 路径）。

**baseline**：原始 flow grid 纹理、JPEG/BC 压缩 flow grid、本方案 MLP。 测量：bpp、PSNR、SSIM；GPU ms/frame。

**可发表**：I3D / EGSR / 神经渲染相关 workshop。

------

### 7.5 [推荐 ★★★] 双向 Rigid-Wave Particle 耦合

**研究问题**

Uncharted 4 的 wave particles 是单向的（粒子影响水面，但物体进水只是 spawn 粒子，不影响已有粒子）。结果是船头不会"挤压"周围水形成正确的 bow wave 形状。

**目标**

在粒子 advection 步骤中加入"刚体排水"项：粒子靠近刚体时被推开/排斥，形成正确的 bow wave 与尾迹形状。

**技术细节**

- 用 SDF 表示刚体；
- 粒子 advect 时加上 SDF 法向方向的推力，权重正比于刚体在该粒子 cell 的"排水体积"；
- 守恒律：被排出的体积要在尾迹处补偿，避免水量丢失。

**baseline**：UC4（单向）、SPH/FLIP-based（双向但贵）。 测量：bow wave 形状与真实测量对比；性能。

**可发表**：I3D / EGSR / Eurographics short。

------

### 7.6 [候选 ★★] Differentiable River Rendering for Art-Direction

**研究问题**

flow map 通常由美术绘制 → 加噪生成 → 美术再修。耗时。能否让美术输入一张参考图（"我想要这样的水流模式"），系统反向求解出对应的 flow grid？

**目标**

构建可微的 wave particle pipeline，用 image-space loss（与参考图对比）反向传播到 flow map / 粒子初始分布。

**风险**：研究门槛较高（gradient through GPU sim），可能 6 个月做不完。

------

### 7.7 [候选 ★★] 与 Lumen / Path Tracing 的 caustics 耦合

如果引擎本身是 UE5-like 的 path-traced 管线，可以研究 wave particle field 与 caustic 的精确耦合（替代传统的 SSR caustic）。

------

### 7.8 专利与发表风险简要分析

| 方向                 | 专利风险                          | 发表难度 | 工程价值           |
| -------------------- | --------------------------------- | -------- | ------------------ |
| 7.1 频谱协调         | 低                                | 中       | 高（直接落地）     |
| 7.2 Mesh shader 调度 | 低                                | 中       | 高                 |
| 7.3 FLIP-baked WPB   | **中**（需绕过 US 11,010,509 B1） | 中高     | 高                 |
| 7.4 神经压缩         | 低                                | 中       | 中（实用）         |
| 7.5 双向耦合         | 低                                | 中       | 中（视觉提升明显） |
| 7.6 Differentiable   | 低                                | 高       | 中                 |

------

## 8. 给老师的"为什么不是其他方案"一段话

> 我们考察了 8 种主流/前沿河流渲染技术：
>
> - 单纯 Flow Map（Vlachos）已经无法满足 PBR / 高度感需求；
> - Gerstner / FFT 没有 advection，不能正确表达"水沿河道流动"；
> - SWE 是浅水长波近似，不解高频，只能做 flow baking 与 wake 局部，不能做主 displacement；
> - SPH/FLIP 是特效层方案，规模和成本不适合河面主体；
> - Water Surface Wavelets (Jeschke 2018) 与 Wave Profile Buffer (Grenier 2018) 在数学上更先进，但 shipping 案例少、显存高、Grenier 方案还有专利风险，作为 production baseline 风险高；
>
> Wave Particles + CDLOD（Uncharted 4 路线）是当前**唯一**同时满足：(1) 工业 shipping 验证，(2) 与已有 FFT clipmap pipeline 高复用，(3) 美术工作流成熟，(4) 性能可预测，(5) 解决"有高度感流动水"这一核心视觉问题，的方案。
>
> 在此 baseline 之上，研究方向不是简单复现：我们计划做 **频谱一致性混合（FFT + WP）**、**GPU-driven 粒子调度**、以及 **FLIP-baked amplitude field 升级路径**，这三项均有可发表的研究价值与工程落地价值。

------

## 9. 参考文献与延伸阅读

**几何**

- Strugar, F. "Continuous Distance-Dependent Level of Detail for Rendering Heightmaps". J. Graphics Tools, 2010.
- Losasso, F., Hoppe, H. "Geometry Clipmaps". SIGGRAPH 2004.

**Flow Map**

- Vlachos, A. "Water Flow in Portal 2 / Left 4 Dead 2". SIGGRAPH 2010 Advances in Real-Time Rendering.
- van der Burg, J. "Flow Tile Shader". 2009.

**Wave Particles**

- Yuksel, C., House, D., Keyser, J. "Wave Particles". SIGGRAPH 2007.
- Gonzalez-Ochoa, C. "Rendering Rapids in Uncharted 4". SIGGRAPH 2016 Advances in Real-Time Rendering.
- Gonzalez-Ochoa, C., Holder, D. "Water Technology of Uncharted". GDC 2012.

**Wave Profile Buffer / Wavelets**

- Grenier, J.-P. "River Editor: Water Simulation in Real-Time". 80lv, 2019 (demo + writeup).
- US Patent 11,010,509 B1 (Grenier / Unity).
- Jeschke, S., Skrivan, T., Müller-Fischer, M., Chentanez, N., Macklin, M., Wojtan, C. "Water Surface Wavelets". SIGGRAPH 2018.
- Jeschke, S., Wojtan, C. "Water Wave Packets". SIGGRAPH 2017.

**SWE / Pipe Model**

- Mei, X., Decaudin, P., Hu, B.-G. "Fast Hydraulic Erosion Simulation and Visualization on GPU". Pacific Graphics 2007.
- Brodtkorb, A., et al. "Efficient shallow water simulations on GPUs". Computers & Fluids, 2012.

**FFT / Tessendorf**

- Tessendorf, J. "Simulating Ocean Water". SIGGRAPH 2001 course notes.
- Tessendorf, J. "iWave". SIGGRAPH 2008 (refresh of Eurographics 2004).

**生产案例 / GDC talks**

- Tcheblokov, T., Mihelich, M. "Wakes, Explosions and Lighting: Interactive Water Simulation in Atlas". GDC 2019.
- "Water Technology of Uncharted" GDC Vault.
- Rare technical talks on Sea of Thieves water (SIGGRAPH 2017 / 2018 community summaries).

**实现/开源参考**

- `ACskyline/Wave-Particles-with-Interactive-Vortices` (DX12, Wave Profile Buffer 复现)
- `LanLou123/waveparticle` (Wave Particles 复现)
- `wave-harmonic/water-resources` (技术资源索引)

------

*文档版本：v1.0 / 2026-05-24*