# 渲染方程与蒙特卡洛求解 — 图形学完整讲义

> 本讲义系统讲解 Kajiya (1986) 提出的渲染方程、其各项的物理含义、蒙特卡洛求解的数学原理、经典近似方法，以及不同 BRDF（diffuse/glossy）的对比分析。每一处都给出严格的数学推导。

---

## 目录

1. [辐射度量学预备知识](#1-辐射度量学预备知识)
2. [渲染方程及各项详解](#2-渲染方程及各项详解)
3. [BRDF: 双向反射分布函数](#3-brdf-双向反射分布函数)
4. [蒙特卡洛积分原理](#4-蒙特卡洛积分原理)
5. [蒙特卡洛求解渲染方程](#5-蒙特卡洛求解渲染方程)
6. [路径追踪算法](#6-路径追踪算法)
7. [经典近似方法](#7-经典近似方法)
8. [Diffuse vs Glossy 深度对比](#8-diffuse-vs-glossy-深度对比)

---

## 1. 辐射度量学预备知识

要理解渲染方程，必须先理解几个辐射度量。

### 1.1 立体角 (Solid Angle)

立体角是平面角在三维的推广，定义为：

$$
\Omega = \frac{A}{r^2} \quad [\text{sr (steradian)}]
$$

微分立体角在球坐标下：

$$
d\omega = \sin\theta \, d\theta \, d\phi
$$

整个球面的立体角为 $4\pi$，半球为 $2\pi$。

### 1.2 辐射通量 / 辐射强度 / 辐照度 / 辐射度

| 量 | 符号 | 单位 | 定义 |
|---|---|---|---|
| 辐射通量 (Flux) | $\Phi$ | W | 单位时间能量 |
| 辐射强度 (Intensity) | $I = \frac{d\Phi}{d\omega}$ | W/sr | 单位立体角的功率 |
| 辐照度 (Irradiance) | $E = \frac{d\Phi}{dA}$ | W/m² | 入射到单位面积的功率 |
| 辐射度 (Radiance) | $L = \frac{d^2\Phi}{dA\,\cos\theta\,d\omega}$ | W/(m²·sr) | 单位投影面积、单位立体角的功率 |

**Radiance 是最重要的量**，因为它沿光线传播时不变（在真空中）。

### 1.3 辐照度与辐射度的关系（关键推导）

入射辐照度由所有方向的入射辐射度积分得到：

$$
\boxed{ \; E(\mathbf{x}) = \int_{\Omega^+} L_i(\mathbf{x}, \omega_i) \cos\theta_i \, d\omega_i \; }
$$

**notes**:

在radiance中定义的cos正如lambert定律那样。但是这个推导公式中的cos是数学的推导结果。

Radiance 描述的是"沿光线方向、单位垂直截面流过多少能量"——这个量与接收表面怎么摆放无关。但是恰好，这样的推导结果符合了物理直觉，符合了lambert定律。

---

## 2. 渲染方程及各项详解

### 2.1 完整形式

Kajiya (1986) 提出的渲染方程：

$$
\boxed{
L_o(\mathbf{x}, \omega_o) \;=\; L_e(\mathbf{x}, \omega_o) \;+\; \int_{\Omega^+} f_r(\mathbf{x}, \omega_i, \omega_o)\, L_i(\mathbf{x}, \omega_i)\, (\omega_i \cdot \mathbf{n})\, d\omega_i
}
$$

### 2.2 逐项剖析

#### (1) $L_o(\mathbf{x}, \omega_o)$ — 出射辐射度
表面点 $\mathbf{x}$ 沿方向 $\omega_o$ 离开的辐射度。这是我们想要求解的未知量——相机像素接收到的就是这个量。

#### (2) $L_e(\mathbf{x}, \omega_o)$ — 自发光项
表面自身发出的辐射度（如灯、屏幕、太阳）。对于非光源表面 $L_e = 0$。这是渲染方程的"源"项。

#### (3) $\int_{\Omega^+} (\cdot)\, d\omega_i$ — 半球积分
$\Omega^+$ 表示以法线 $\mathbf{n}$ 为轴的上半球。积分意味着收集来自所有可能入射方向的贡献——这是渲染方程的物理本质：**任意方向的反射光都是所有入射光经过 BRDF 加权的总和**。

#### (4) $f_r(\mathbf{x}, \omega_i, \omega_o)$ — BRDF
双向反射分布函数，描述材质如何把入射方向 $\omega_i$ 的能量分配到出射方向 $\omega_o$。详见第 3 节。单位：$\text{sr}^{-1}$。

#### (5) $L_i(\mathbf{x}, \omega_i)$ — 入射辐射度
从方向 $\omega_i$ 到达 $\mathbf{x}$ 的辐射度。**这一项隐含了递归**：

$$
L_i(\mathbf{x}, \omega_i) \;=\; L_o\bigl( r(\mathbf{x}, \omega_i),\ -\omega_i \bigr)
$$

其中 $r(\mathbf{x}, \omega_i)$ 是光线投射函数（从 $\mathbf{x}$ 沿 $\omega_i$ 投射，命中的最近表面点）。

> **正是这一递归性使渲染方程是一个 Fredholm 第二类积分方程，无解析解，必须数值求解。**

#### (6) $(\omega_i \cdot \mathbf{n}) = \cos\theta_i$ — 几何项
朗伯余弦项，如 1.3 节所述。当 $\omega_i$ 接近表面切平面时，能量贡献趋于零。

### 2.3 算子形式

定义反射算子 $\mathcal{T}$：

$$
(\mathcal{T} L)(\mathbf{x}, \omega_o) = \int_{\Omega^+} f_r\, L(r(\mathbf{x},\omega_i), -\omega_i)\, \cos\theta_i\, d\omega_i
$$

则渲染方程可写为：

$$
L = L_e + \mathcal{T} L
$$

形式上的 **诺伊曼级数 (Neumann series)** 解：

其实就是**泰勒展开**
$$
L = (I - \mathcal{T})^{-1} L_e = L_e + \mathcal{T} L_e + \mathcal{T}^2 L_e + \mathcal{T}^3 L_e + \cdots
$$

物理意义：

- $L_e$：直接看到的光源
- $\mathcal{T} L_e$：经过一次反射的光（直接光照）
- $\mathcal{T}^2 L_e$：经过两次反射的光（一次间接反弹）
- $\mathcal{T}^k L_e$：$k$ 次反射

这正是 **路径追踪** 的理论基础。

---

## 3. BRDF: 双向反射分布函数

### 3.1 严格定义

$$
f_r(\mathbf{x}, \omega_i, \omega_o) \;\equiv\; \frac{dL_o(\mathbf{x}, \omega_o)}{dE_i(\mathbf{x}, \omega_i)} \;=\; \frac{dL_o(\mathbf{x}, \omega_o)}{L_i(\mathbf{x}, \omega_i)\,\cos\theta_i\,d\omega_i}
$$

物理含义：单位入射辐照度（来自方向 $\omega_i$）在出射方向 $\omega_o$ 产生多少辐射度。

完整的irradiance是没有方向的，是对整个半球积分的结果
$$
E=\int_{\Omega}L_i(\omega_i)cos\theta_id\omega_i
$$
但是对于微分的irradiance
$$
dE(\omega_i)=L_i(\omega_i)cos\theta_id\omega_i
$$
描述的是投递到表面上的radiance贡献。

**为什么分母选用irradiance?**

### 3.2 物理性质（任何合法 BRDF 必须满足）

1. **非负性**：$\;f_r(\omega_i, \omega_o) \geq 0$
2. **Helmholtz 互易性**：$\;f_r(\omega_i, \omega_o) = f_r(\omega_o, \omega_i)$
   （来自电磁波传播的时间反演对称性）
3. **能量守恒**：

$$
\int_{\Omega^+} f_r(\omega_i, \omega_o)\, \cos\theta_o\, d\omega_o \;\leq\; 1, \quad \forall\, \omega_i
$$

不等式表示部分能量可被吸收。等号成立时表示无吸收。

### 3.3 Diffuse (Lambertian) BRDF

完美漫反射假设：**$L_o$ 在所有出射方向都是常数**（与 $\omega_o$ 无关）。这就是物体看起来从任何角度亮度都一样的原因（如粉笔、纸）。

#### 严格推导 $f_r = \rho / \pi$

设入射 irradiance 为 $E_i$，反照率 (albedo) 为 $\rho \in [0,1]$,代表反射和入射的flux之比

**步骤 1**：能量守恒——出射总功率 = 入射 × 反照率：

$$
\int_{\Omega^+} L_o\, \cos\theta_o\, d\omega_o = \rho\, E_i
$$

**步骤 2**：因为 $L_o$ 是常数，可提出积分：

$$
L_o \cdot \int_{\Omega^+} \cos\theta_o\, d\omega_o = \rho\, E_i
$$

**步骤 3**：计算半球上的余弦积分（注意 $d\omega = \sin\theta\,d\theta\,d\phi$）：
$$
\int_{\Omega^+} \cos\theta_o\, d\omega_o
= \int_0^{2\pi}\!\!\int_0^{\pi/2} \cos\theta\,\sin\theta\, d\theta\, d\phi
= 2\pi \cdot \tfrac{1}{2} = \pi
$$

**步骤 4**：代回：

$$
L_o \cdot \pi = \rho\, E_i \;\;\Longrightarrow\;\; L_o = \frac{\rho}{\pi}\, E_i
$$

**步骤 5**：由 BRDF 定义 $L_o = f_r \cdot E_i$（对于固定入射方向），得：

$$
\boxed{\; f_r^{\text{Lambert}} = \frac{\rho}{\pi} \;}
$$

> **那个 $\pi$ 不是凭空出现的——它来自半球上 $\cos\theta$ 的积分。** 这是图形学中最容易被忽略也最重要的常数。

### 3.4 Glossy BRDF

#### (a) Phong 模型（归一化形式）

$$
f_r(\omega_i, \omega_o) = \frac{k_s\,(n+2)}{2\pi}\, (\mathbf{r}\cdot\omega_o)_+^n
$$

其中 $\mathbf{r}$ 是 $\omega_i$ 关于法线的反射方向，$n$ 是 shininess 指数。

**$(n+2)/(2\pi)$ 哪来的？** 来自归一化：要求在半球上对 $\omega_o$ 积分（不带 $\cos\theta_o$）等于 $k_s$，可证明 $\int_{\Omega^+}(\cos\alpha)^n \sin\alpha\, d\alpha\, d\phi = 2\pi/(n+1)$。如果带 $\cos\theta_o$ 项的归一化要求，则系数变为 $(n+2)/(2\pi)$（保证能量守恒）。

#### (b) Blinn-Phong 模型

使用半角向量 $\mathbf{h} = (\omega_i + \omega_o) / \|\omega_i + \omega_o\|$：

$$
f_r \propto (\mathbf{n} \cdot \mathbf{h})^n
$$

物理上比 Phong 更合理，且计算上更高效。

#### (c) Cook-Torrance 微表面模型（现代物理基础渲染的标准）

$$
\boxed{\; f_r(\omega_i, \omega_o) = \frac{D(\mathbf{h})\, F(\omega_i, \mathbf{h})\, G(\omega_i, \omega_o)}{4\,(\omega_i \cdot \mathbf{n})\,(\omega_o \cdot \mathbf{n})} \;}
$$

三项分别是：

- **$D(\mathbf{h})$ — 法线分布函数 (NDF)**：微表面法线对齐到 $\mathbf{h}$ 的概率密度。
  常用 GGX (Trowbridge-Reitz)：
  $$D_{\text{GGX}}(\mathbf{h}) = \frac{\alpha^2}{\pi\bigl[(\mathbf{n}\cdot\mathbf{h})^2(\alpha^2-1)+1\bigr]^2}$$
  其中 $\alpha = \text{roughness}^2$。

- **$F$ — 菲涅尔项**：反射比随入射角的变化。Schlick 近似：
  $$F(\omega_i, \mathbf{h}) \approx F_0 + (1 - F_0)\,(1 - \omega_i\cdot\mathbf{h})^5$$
  $F_0$ 是垂直入射时的反射率（金属约 0.5-1.0，电介质约 0.04）。

- **$G$ — 几何遮蔽函数**：微表面互相遮挡的比例。常用 Smith 模型，分为遮蔽 $G_1(\omega_o)$ 和阴影 $G_1(\omega_i)$：
  $$G(\omega_i, \omega_o) = G_1(\omega_i)\,G_1(\omega_o)$$

分母 $4(\omega_i\cdot\mathbf{n})(\omega_o\cdot\mathbf{n})$ 来自微表面的 Jacobian（微表面立体角到宏观立体角的变换），具体推导涉及微表面法线分布到反射方向的雅可比行列式 $|\partial\omega_h/\partial\omega_o| = 1/(4|\omega_o\cdot\mathbf{h}|)$。

---

## 4. 蒙特卡洛积分原理

### 4.1 为什么需要蒙特卡洛？

渲染方程是一个**高维积分**：

- 半球积分：2 维
- 递归一次：增加 2 维（4D）
- 递归 $k$ 次：$2k$ 维

传统数值方法（Simpson、Gauss）在高维下遭遇**维数灾难**：误差 $O(N^{-c/d})$，$d$ 是维度。蒙特卡洛的误差 $O(N^{-1/2})$ **与维度无关**！

### 4.2 基本估计器

要估计 $\;I = \int_D f(x)\, dx\;$，设 $X \sim p(x)$，$p > 0$ 在 $\{f \neq 0\}$ 上。则估计器：

$$
\hat{I}_N = \frac{1}{N}\sum_{i=1}^N \frac{f(X_i)}{p(X_i)}
$$

#### 无偏性证明：

$$
\mathbb{E}[\hat{I}_N] = \mathbb{E}\!\left[\frac{f(X)}{p(X)}\right] = \int_D \frac{f(x)}{p(x)} p(x)\, dx = \int_D f(x)\, dx = I \quad\checkmark
$$

#### 方差与收敛速度：

$$
\text{Var}[\hat{I}_N] = \frac{1}{N}\,\text{Var}\!\left[\frac{f(X)}{p(X)}\right] = \frac{\sigma^2}{N}
$$

由切比雪夫不等式或中心极限定理：

$$
|\hat{I}_N - I| = O\!\left(\frac{\sigma}{\sqrt{N}}\right)
$$

要降低 1 位精度（误差变 1/10）需要 100 倍样本。这就是为什么 MC 渲染又慢又有噪声。

### 4.3 重要性采样 (Importance Sampling)

**核心思想**：让 $p(x)$ 与 $f(x)$ 形状相近，可大幅降低方差。

理想极限：若 $p(x) = f(x)/I$，则 $f(x)/p(x) = I = \text{const}$，方差为 **零**。但这需要事先知道 $I$！实际中只能近似。

**理论依据**（用 Cauchy-Schwarz）：

$$
\sigma^2 = \int \frac{f^2}{p}\, dx - I^2
$$

最小化 $\int f^2/p \, dx$，受约束 $\int p\, dx = 1$，由拉格朗日乘子法得最优 $p^* \propto |f|$。

---

## 5. 蒙特卡洛求解渲染方程

### 5.1 单点估计器

对一个表面点 $\mathbf{x}$、出射方向 $\omega_o$，渲染方程的 MC 估计：

$$
\hat{L}_o(\mathbf{x}, \omega_o) = L_e(\mathbf{x},\omega_o) + \frac{1}{N}\sum_{k=1}^N \frac{f_r(\mathbf{x}, \omega_i^k, \omega_o)\, L_i(\mathbf{x}, \omega_i^k)\, \cos\theta_i^k}{p(\omega_i^k)}
$$

其中 $\omega_i^k \sim p(\omega)$ 是从某个半球分布采样的方向。$L_i$ 本身又通过递归 MC 估计。

### 5.2 采样策略详解

#### 策略 A：均匀半球采样

$$
p(\omega) = \frac{1}{2\pi}
$$

**推导反演法采样**：

设球坐标 $(\theta, \phi)$，$d\omega = \sin\theta\, d\theta\, d\phi$。则：

$$
p(\theta, \phi) = p(\omega) \cdot \sin\theta = \frac{\sin\theta}{2\pi}
$$

边缘 / 条件分布：

$$
p(\theta) = \int_0^{2\pi} \frac{\sin\theta}{2\pi} d\phi = \sin\theta, \quad p(\phi|\theta) = \frac{1}{2\pi}
$$

CDF：$F(\theta) = \int_0^\theta \sin t\, dt = 1 - \cos\theta$。

反演：令 $\xi_1 \sim U[0,1]$，则 $\cos\theta = 1 - \xi_1$。由对称性可用 $\cos\theta = \xi_1$。

最终采样公式：

$$
\boxed{\; \cos\theta = \xi_1, \quad \phi = 2\pi\xi_2 \;}
$$

#### 策略 B：余弦加权采样（重要性采样）

$$
p(\omega) = \frac{\cos\theta}{\pi}
$$

(分母 $\pi$ 是归一化常数，由 3.3 节计算 $\int_{\Omega^+}\cos\theta\,d\omega = \pi$)

**为什么用这个 pdf？** 渲染方程被积函数含 $f_r \cdot L_i \cdot \cos\theta$。对于 Lambert BRDF，$f_r = \rho/\pi$ 是常数，则被积函数 $\propto \cos\theta \cdot L_i$。如果 $L_i$ 大致均匀，最佳 $p \propto \cos\theta$，正是此分布。

**推导**：

$$
p(\theta, \phi) = \frac{\cos\theta \sin\theta}{\pi} = \frac{\sin(2\theta)}{2\pi}
$$

CDF：$F(\theta) = \sin^2\theta$。

反演：

$$
\boxed{\; \sin\theta = \sqrt{\xi_1},\quad \cos\theta = \sqrt{1-\xi_1},\quad \phi = 2\pi\xi_2 \;}
$$

**Lambert 反射的化简效果**：

$$
\frac{f_r \cos\theta_i}{p(\omega_i)} = \frac{(\rho/\pi)\cos\theta_i}{\cos\theta_i/\pi} = \rho
$$

估计器变为：

$$
\hat{L}_o = L_e + \frac{\rho}{N}\sum_{k=1}^N L_i(\omega_i^k)
$$

**美妙！** $\cos\theta$ 和 $1/\pi$ 全部约掉。这就是物理基础渲染中"反照率 × 平均入射光"的来历。

#### 策略 C：BRDF 重要性采样（用于 Glossy）

对于 Phong/Blinn-Phong/GGX 等具有方向性的 BRDF，应当让 $p(\omega) \propto f_r(\omega_i, \omega_o) \cos\theta_i$，使估计器分子分母相消。具体反演公式因 BRDF 而异（如 GGX 半角向量采样）。

### 5.3 多重重要性采样 (MIS)

当被积函数有多个"峰"（如 BRDF 的高光峰 + 强光源方向），单一 $p$ 难以兼顾。**MIS** (Veach 1995) 用多个采样策略的加权组合：

$$
\hat{I}_{\text{MIS}} = \sum_{s=1}^S \frac{1}{N_s}\sum_{k=1}^{N_s} w_s(X_{s,k}) \frac{f(X_{s,k})}{p_s(X_{s,k})}
$$

**Balance heuristic**：
$$
w_s(x) = \frac{N_s p_s(x)}{\sum_t N_t p_t(x)}
$$

**Power heuristic** (常用 $\beta=2$)：
$$
w_s(x) = \frac{(N_s p_s(x))^\beta}{\sum_t (N_t p_t(x))^\beta}
$$

在直接光照中将 BRDF 采样和光源采样组合，效果显著。

---

## 6. 路径追踪算法

### 6.1 算法骨架（伪代码）

```
function trace(ray):
    hit = scene.intersect(ray)
    if not hit: return background

    L = L_e(hit, -ray.dir)         # emission
    
    # Russian roulette
    p_continue = min(throughput.max(), 0.95)
    if random() > p_continue: return L
    
    # Sample BRDF / hemisphere
    omega_i, pdf = sample_direction(hit, -ray.dir)
    f_r = brdf(hit, omega_i, -ray.dir)
    cos_theta = max(0, dot(omega_i, hit.normal))
    
    # Recursive
    L_i = trace(Ray(hit.pos, omega_i))
    
    return L + (f_r * L_i * cos_theta / pdf) / p_continue
```

### 6.2 俄罗斯轮盘赌 (Russian Roulette)

为了无偏地终止递归（不能简单截断 —— 截断会引入偏差）：

$$
\hat{L} = \begin{cases} L'/p_c & \text{以概率 } p_c \\ 0 & \text{以概率 } 1-p_c \end{cases}
$$

#### 无偏性证明：

$$
\mathbb{E}[\hat{L}] = p_c \cdot \frac{L'}{p_c} + (1-p_c)\cdot 0 = L' \quad\checkmark
$$

代价：方差增加（$\sigma^2$ 增加 $\frac{1-p_c}{p_c}L'^2$），但期望计算量降低。$p_c$ 通常取与表面反照率相关的值。

### 6.3 直接光照分解（关键优化）

将渲染方程分为：

$$
L_o = L_e + \underbrace{\int_{\Omega^+} f_r\, L_{e,\text{light}}\, \cos\theta_i\, d\omega_i}_{L_{\text{dir}}} + \underbrace{\int_{\Omega^+} f_r\, L_{i,\text{ind}}\, \cos\theta_i\, d\omega_i}_{L_{\text{ind}}}
$$

**直接光照** 通过对光源面积直接采样估计，方差远低于半球均匀采样（光源面积远小于半球）。

#### 立体角→面积的变量替换

设光源点 $\mathbf{y}$，$d\mathbf{y}$ 是面积元。从 $\mathbf{x}$ 看 $\mathbf{y}$ 的立体角：

$$
d\omega = \frac{\cos\theta_y\, dA(\mathbf{y})}{\|\mathbf{x}-\mathbf{y}\|^2}
$$

其中 $\theta_y$ 是 $\mathbf{y}$ 法线与 $\mathbf{y}\to\mathbf{x}$ 方向的夹角。直接光照估计器：

$$
\hat{L}_{\text{dir}} = \frac{1}{N}\sum_{k=1}^N \frac{f_r(\omega_i)\, L_e(\mathbf{y}_k, \omega_i)\, \cos\theta_i\, \cos\theta_y\, V(\mathbf{x}, \mathbf{y}_k)}{\|\mathbf{x}-\mathbf{y}_k\|^2 \cdot p_A(\mathbf{y}_k)}
$$

$V$ 是可见性函数，$p_A$ 是面积上的 pdf。

---

## 7. 经典近似方法

完整路径追踪计算量大。在此之前，图形学发展了一系列近似。

### 7.1 局部光照模型（仅直接光）

舍弃间接反射，只算光源直接贡献：

$$
L_o \approx L_e + \sum_{l \in \text{lights}} f_r(\mathbf{x}, \omega_l, \omega_o)\, L_l\, \cos\theta_l\, V(\mathbf{x}, \mathbf{x}_l)
$$

这是 OpenGL 固定管线、Phong 着色的本质。**完全忽略间接反弹**——所以直接光照射不到的地方"漆黑一片"，需要加 ambient 项凑效果。

### 7.2 Phong 着色公式

$$
I = k_a I_a + \sum_l \bigl[k_d (\mathbf{n}\cdot\mathbf{l})_+ + k_s (\mathbf{r}\cdot\mathbf{v})_+^n \bigr] I_l
$$

其中：
- $k_a I_a$：环境项，对全局光照的极粗略近似（一个常数）
- $k_d (\mathbf{n}\cdot\mathbf{l})$：漫反射项
- $k_s (\mathbf{r}\cdot\mathbf{v})^n$：镜面项

**这本质是渲染方程在以下假设下的简化**：
1. 只有点光源（$L_i$ 为狄拉克 $\delta$ 函数）
2. 间接光近似为常数 $k_a I_a$
3. BRDF 用 Phong 形式

### 7.3 辐射度算法 (Radiosity, Goral et al. 1984)

**假设全场景为漫反射**。则 $L_o$ 与方向无关，可定义辐射度 $B(\mathbf{x}) = \pi L_o(\mathbf{x})$。渲染方程退化为：

$$
B_i = E_i + \rho_i \sum_j F_{ij} B_j
$$

其中 $F_{ij}$ 是 patch $i$ 到 $j$ 的**形式因子 (form factor)**：

$$
F_{ij} = \frac{1}{A_i} \int_{A_i}\int_{A_j} \frac{\cos\theta_i \cos\theta_j}{\pi r^2}\, V_{ij}\, dA_j\, dA_i
$$

这是渲染方程的有限元离散化，得到线性方程组 $(I - \rho F) B = E$，可用迭代法（Jacobi、Gauss-Seidel、Progressive Refinement）求解。

**优点**：视点无关，预计算后可自由移动相机。
**缺点**：仅限漫反射，无法处理镜面/高光。

### 7.4 环境光遮蔽 (Ambient Occlusion, AO)

近似漫反射环境光在表面点的可见性：

$$
AO(\mathbf{x}) = \frac{1}{\pi}\int_{\Omega^+} V(\mathbf{x}, \omega)\, \cos\theta\, d\omega
$$

是渲染方程在以下假设下的简化：
- $L_i$ 在所有方向相等（均匀环境）
- BRDF 为 Lambertian
- 只考虑近场遮挡的可见性

### 7.5 基于图像的光照 (IBL)

将远处环境视为只与方向有关的光：$L_i(\mathbf{x}, \omega) = L_{\text{env}}(\omega)$。则对漫反射表面：

$$
L_o(\mathbf{x}) = \frac{\rho}{\pi} \int_{\Omega^+} L_{\text{env}}(\omega)\, \cos\theta\, d\omega
$$

可对环境贴图**预计算辐照度图 (irradiance map)**——把每个法线方向对应的积分预先卷积存储，运行时直接查表。

### 7.6 球谐函数 (Spherical Harmonics)

将辐照度展开为球谐基：

$$
E(\mathbf{n}) = \sum_{l=0}^\infty \sum_{m=-l}^l c_{lm}\, Y_{lm}(\mathbf{n})
$$

**Ramamoorthi & Hanrahan (2001) 关键结果**：漫反射 BRDF 在球谐域是低通滤波器，**前 9 项 (l ≤ 2) 即可近似 99% 的辐照度信号**。这就是为什么手机游戏只用 9 个浮点数就能存储环境光照——这是渲染方程的傅里叶分析视角。

### 7.7 路径表达式 (Heckbert's Light Path Notation)

光从光源 $L$ 经路径到眼睛 $E$，每段表面分类为：
- $D$：diffuse 反射
- $S$：specular 反射

正则表达式描述算法能处理的路径：

| 算法 | 表达式 | 含义 |
|---|---|---|
| 光线追踪 (Whitted) | $LDS^*E$ | 光源 → 一次漫反射 → 任意镜面 → 眼睛 |
| 辐射度算法 | $LD^*E$ | 全漫反射 |
| 双向路径追踪 | $L(D\|S)^*E$ | 任意路径 |
| 焦散 (caustics) | $LS^+DE$ | 镜面聚焦后到漫反射面 |

经典近似的局限可以这样表达：辐射度算法处理不了 $S$，光线追踪处理不了 $D^+$。**只有完整 MC 路径追踪能处理所有路径**。

---

## 8. Diffuse vs Glossy 深度对比

### 8.1 BRDF 形状对比

**Diffuse**：$f_r = \rho/\pi$ 是**常数**，与 $\omega_i, \omega_o$ 都无关。

**Glossy**：$f_r$ 集中在镜面反射方向附近（Phong/Blinn-Phong 是绕 $\mathbf{r}$ 的 lobe，GGX 是绕 $\mathbf{h}$ 的 lobe）。

### 8.2 渲染特性全面对比

| 特性 | Diffuse | Glossy |
|---|---|---|
| BRDF 形式 | 常数 $\rho/\pi$ | 角度依赖，集中在反射方向 |
| 视角依赖性 | 无 | 强 |
| 视觉效果 | 均匀亮度，如粉笔、纸 | 高光，如塑料、抛光金属 |
| 频率 | 低频 | 中-高频（取决于粗糙度） |
| 球谐适用性 | 极佳（9 项足够） | 差（需要高阶或不适用） |
| 重要性采样策略 | cosine-weighted | BRDF lobe 采样 |
| 收敛速度 | 快 | 慢（需更多样本） |
| 噪点 | 较少 | 多，常见"萤火虫"伪影 |
| 焦散能力 | 无 | 有（光路如 $LSDE$ 中 $S$ 的角色） |
| 可预计算性 | 强（irradiance map, 辐射度算法） | 弱（视点相关） |

### 8.3 方差与样本数的定量分析

设积分 $I$ 不变。蒙特卡洛方差：

$$
\sigma^2 = \int_{\Omega^+} \frac{(f_r L_i \cos\theta)^2}{p(\omega)} d\omega - I^2
$$

**Diffuse + cosine 采样**：$f_r \cos\theta / p = \rho$ 是常数，方差仅由 $L_i$ 的变化决定，$\sigma$ 较小。

**Glossy + 均匀采样**：$f_r$ 在小范围立体角内非常大（如 $(n+2)/(2\pi)$ 对大 $n$），其他方向几乎为零。$p = 1/(2\pi)$ 在峰值附近"采样不足"。$\sigma$ 极大。

定量：若 BRDF lobe 立体角为 $\Delta\Omega$，则均匀采样有效样本数为 $N \cdot \Delta\Omega/(2\pi)$。glossy 高光只有约 $1\%$ 立体角，意味着 99% 的样本"无效"——方差是 diffuse 的约 100 倍。

### 8.4 在路径追踪中的实际影响

#### 终止概率

为了减少方差，俄罗斯轮盘 $p_c$ 应与 throughput 成比例。glossy 表面会让 throughput 在某些方向集中（峰值高），需要更精细的策略。

#### 间接光收集

漫反射表面的间接光积分较平滑，少量样本即可。glossy 的间接光集中在反射方向，若方向上没有光源（如间接到天花板），则收敛很慢。

#### MIS 的必要性

对于 glossy + 强光源的场景，单独 BRDF 采样或单独光源采样都会失败：
- 仅 BRDF 采样：很少命中小光源（光源 pdf 小）
- 仅光源采样：错过镜面高光的细微方向

**MIS 组合两者，是渲染 glossy 表面的必备技术**。

### 8.5 光路类型

Diffuse 表面贡献 $D$，Glossy 表面贡献 $S$（在路径表达式中）。

| 路径 | 含义 | 例子 |
|---|---|---|
| $LDE$ | 光源直接照射漫反射 | 普通墙面 |
| $LSE$ | 光源直接镜面反射 | 镜中光源 |
| $LDDE$ | 漫反射间接 | color bleeding |
| $LSDE$ | 焦散 | 玻璃聚焦在桌面 |
| $LDSE$ | 漫反射 → 镜面 | 镜中模糊物体 |

**只有 MC 路径追踪能无偏处理所有这些路径**。各种近似都在某些路径上失效。

---

## 9. 总结：理论金字塔

```
                  渲染方程 (Kajiya 1986)
                    L = L_e + 𝒯L
                          │
                          ▼
                Neumann 级数 = 路径求和
                          │
        ┌─────────────────┼──────────────────┐
        ▼                 ▼                  ▼
   蒙特卡洛积分      经典近似            重要性采样
   - 无偏估计      - Phong (LDS*E)        - cos-weighted
   - 方差降低     - Radiosity (LD*E)     - BRDF lobe
   - 维度无关     - AO, IBL, SH         - MIS
        │
        ▼
   路径追踪 (PT)
   - 双向路径追踪 (BDPT)
   - 光子映射 (Photon Mapping)
   - Metropolis Light Transport (MLT)
```

### 关键 takeaway

1. **渲染方程是物理上严格、数学上是积分方程的描述。** 各项都有明确的辐射度量学含义，$\cos\theta$ 不是"修正"而是 Lambert 余弦定律。

2. **递归性使其无解析解，必须数值求解。**

3. **蒙特卡洛是高维积分的最佳工具**，重要性采样是降方差的关键。

4. **经典近似各有局限**——Phong 缺少间接光，辐射度缺少镜面。它们都可视为渲染方程在特定假设下的简化。

5. **Diffuse 和 Glossy 的本质区别在于 BRDF 的"频率"**：低频信号易于采样、易于近似；高频信号难。这决定了所有渲染算法的表现。

6. **Cook-Torrance 微表面模型 + GGX + MIS + 路径追踪** 是当代物理基础渲染的标准工具组合。

---

*"渲染方程本身只是 19 行公式中的一行；理解它如何被求解，才是图形学的精髓。"*
