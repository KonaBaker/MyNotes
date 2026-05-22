ray marching

沿着光线方向一小步一小步的走，每一步检查是否撞到了什么。

完整的ray marching需要遍历整个场景，屏幕空间的ray marching就是利用现有的depth buffer，将其视为一个场景的粗糙近似。光线在

# Ray Marching 完全指南

> 一份系统性的教学文档：从数学基础，到各类变体，到工程应用

------

## 目录

**第一部分：基础与数学**

1. 什么是 Ray Marching
2. 与 Ray Tracing 的本质区别
3. 光线的数学描述
4. 一维信号的"求交"——一切的雏形

**第二部分：原始形态**

1. Naive Fixed-step Ray Marching
2. 自适应步长

**第三部分：距离场与 Sphere Tracing**

1. 有符号距离场（SDF）的定义
2. Sphere Tracing 算法
3. SDF 的原语与组合（CSG）
4. 从 SDF 推导法线
5. 软阴影、AO 的几何技巧

**第四部分：体积渲染**

1. 体积渲染方程的推导
2. Beer-Lambert 定律
3. 离散化与数值积分
4. 相函数（Henyey-Greenstein）
5. 应用：体积云渲染

**第五部分：屏幕空间 Ray Marching**

1. 用 G-Buffer 当作场景的近似
2. 应用：SSR（屏幕空间反射）
3. 应用：SSAO / SS Contact Shadow / SSGI
4. Hi-Z 加速

**第六部分：DDA 与体素遍历**

1. Amanatides & Woo 算法
2. 应用：体素地形 / Minecraft 风格渲染

**第七部分：进阶与优化**

1. 锥追踪（Cone Tracing）
2. 时序累积与降噪
3. 大气散射
4. Ray Marching 与栅格化的结合

**附录**：常用 SDF 公式表 / 推荐阅读

------

## 第一部分：基础与数学

### 1. 什么是 Ray Marching

Ray Marching（光线步进）是一类**用迭代采样代替解析求交**的渲染算法。一个数学上的等价描述：

> 给定一条光线 $\mathbf{r}(t) = \mathbf{o} + t\mathbf{d}$（$t \geq 0$），我们希望找到某个属性 $f(\mathbf{r}(t))$ 满足某个条件的 $t$ 值。Ray Marching 通过沿 $t$ 轴前进采样 $f$ 来近似这个 $t$。

不同的"属性 $f$"和"条件"造就了不同的 Ray Marching 变体：

| 变体               | $f$ 是什么                   | 条件                                |
| ------------------ | ---------------------------- | ----------------------------------- |
| SDF Sphere Tracing | 到最近表面的距离             | $f(\mathbf{r}(t)) \leq \varepsilon$ |
| 屏幕空间 SSR       | 当前点投影后的深度 vs 深度图 | 当前深度 > 场景深度                 |
| 体积渲染           | 介质的消光系数 $\sigma_t$    | 积分到光学厚度足够大或穿出介质      |
| 体素 DDA           | 网格中是否有体素             | 当前网格被占据                      |

理解这张表，就理解了整个 Ray Marching 家族的统一视角。

### 2. 与 Ray Tracing 的本质区别

- **Ray Tracing**：解析求解光线与几何体的相交方程。例如球面方程 $|\mathbf{p} - \mathbf{c}|^2 = r^2$ 代入 $\mathbf{p} = \mathbf{o} + t\mathbf{d}$，得到一个关于 $t$ 的二次方程，解析求 $t$。
- **Ray Marching**：不去解方程，而是"沿光线一步步走，反复测试"。

两者并非对立：

- Ray Tracing 适合**显式定义**的几何（三角形、隐式二次曲面），需要加速结构（BVH、KD-Tree）。
- Ray Marching 适合**不能写成简单方程**的"场"（SDF、体积密度场、深度图近似场）。

现代渲染管线常**混合**使用两者：例如硬件光追求三角形交点，然后从交点出发用 Ray Marching 处理体积雾。

### 3. 光线的数学描述

整篇文档统一采用如下记号：

$$ \mathbf{r}(t) = \mathbf{o} + t\mathbf{d}, \quad |\mathbf{d}| = 1, \quad t \geq 0 $$

其中 $\mathbf{o}$ 是起点（origin），$\mathbf{d}$ 是单位方向。$t$ 既是参数也是从起点出发沿光线前进的物理距离（因为 $\mathbf{d}$ 是单位向量）。

任何 Ray Marching 算法都可以写成如下模板：

```
t = 0
for i in 0..maxSteps:
    p = o + t * d
    if hit_condition(p):
        return p
    t = t + step(p)        # ← 不同算法的差别就在这里
    if t > tMax: break
```

整个算法体系的"灵魂"在 `step(p)`：怎么决定下一步走多远。

### 4. 一维信号的"求交"——一切的雏形

为了把后面的内容讲透，先看一个一维的玩具问题。

> 给定一个函数 $f: \mathbb{R} \to \mathbb{R}$，找到最小的 $t \geq 0$ 使 $f(t) = 0$。

**方法 A：固定步长扫描** $$ t_n = n\Delta t, \quad n = 0, 1, 2, \dots $$ 找到第一个使 $f(t_n) \cdot f(t_{n-1}) < 0$ 的 $n$（变号），交点在 $[t_{n-1}, t_n]$ 之间。

**方法 B：若已知 $f$ 的 Lipschitz 常数 $L$**（即 $|f(a) - f(b)| \leq L|a-b|$），可以让步长自适应： $$ t_{n+1} = t_n + \frac{|f(t_n)|}{L} $$ 为什么？因为 Lipschitz 条件保证：在 $t_n$ 附近 $\frac{|f(t_n)|}{L}$ 距离之内，$f$ 不会变到 $0$。所以这一步是"绝对安全"的。

**方法 C：若 $f$ 本身就是"到零点的距离"**，那么直接 $t_{n+1} = t_n + f(t_n)$。这就是 **Sphere Tracing** 的一维原型。

这三种方法对应了整个 Ray Marching 的三大流派：

- 固定步长（朴素 / 体积渲染）
- Lipschitz 自适应（部分 SDF、Hi-Z）
- 距离即步长（Sphere Tracing）

------

## 第二部分：原始形态

### 5. Naive Fixed-step Ray Marching

最朴素的版本：选定步长 $\Delta t$，每步推进固定距离。

```glsl
float marchNaive(vec3 ro, vec3 rd, float dt, int maxSteps) {
    float t = 0.0;
    for (int i = 0; i < maxSteps; ++i) {
        vec3 p = ro + t * rd;
        if (sceneDensity(p) > 0.5) return t;   // 任意命中判定
        t += dt;
    }
    return -1.0;
}
```

**问题**：

- $\Delta t$ 小则慢；$\Delta t$ 大则错过细节。
- 在显式表面上会产生明显的"分层"伪影（banding）。

**抖动（jittering）** 是廉价的缓解办法：每个像素起步时加一个 $[0, \Delta t)$ 范围内的随机偏移：

```glsl
float jitter = hash(pixelCoord);
float t = jitter * dt;
```

这样 banding 会变成噪声，再用时序滤波（TAA）累积就能消除大部分。

### 6. 自适应步长

如果我们对场景一无所知，固定步长是唯一选择。但只要我们能给出"在当前位置，下一步至少走多远是安全的"这种保证，就能加速。

下一节的 Sphere Tracing 就是这种"保证"最强的版本：**步长直接等于距离场的值**。

------

## 第三部分：距离场与 Sphere Tracing

这是 Ray Marching 在艺术、demo scene、几何建模领域大放异彩的核心技术。

### 7. 有符号距离场（SDF）的定义

设 $\Omega \subset \mathbb{R}^3$ 是一个集合（实体），$\partial \Omega$ 是它的表面。**有符号距离函数（SDF）** 定义为：

$$ \text{sdf}(\mathbf{p}) = \begin{cases}

- \min_{\mathbf{q} \in \partial \Omega} |\mathbf{p} - \mathbf{q}|, & \mathbf{p} \notin \Omega \

- \min_{\mathbf{q} \in \partial \Omega} |\mathbf{p} - \mathbf{q}|, & \mathbf{p} \in \Omega \end{cases} $$

即：到最近表面的距离，外部为正，内部为负，表面上为 0。

**关键性质**：SDF 是 **1-Lipschitz** 的：

$$ |\text{sdf}(\mathbf{a}) - \text{sdf}(\mathbf{b})| \leq |\mathbf{a} - \mathbf{b}| $$

> **证明思路**：设 $\mathbf{q}_a, \mathbf{q}_b$ 分别是 $\mathbf{a}, \mathbf{b}$ 在 $\partial \Omega$ 上的最近点。由三角不等式：
>
> $$\text{sdf}(\mathbf{a}) = |\mathbf{a} - \mathbf{q}_a| \leq |\mathbf{a} - \mathbf{q}_b| \leq |\mathbf{a} - \mathbf{b}| + |\mathbf{b} - \mathbf{q}_b| = |\mathbf{a} - \mathbf{b}| + \text{sdf}(\mathbf{b})$$
>
> 所以 $\text{sdf}(\mathbf{a}) - \text{sdf}(\mathbf{b}) \leq |\mathbf{a} - \mathbf{b}|$；对称地反过来也成立。证毕。

这条性质是 Sphere Tracing 正确性的全部依据。

### 8. Sphere Tracing 算法

由于 SDF 是 1-Lipschitz 的，从 $\mathbf{p}$ 出发，半径为 $\text{sdf}(\mathbf{p})$ 的球内**保证没有任何表面**。因此沿光线方向走 $\text{sdf}(\mathbf{p})$ 这么远是绝对安全的：

```glsl
float sphereTrace(vec3 ro, vec3 rd) {
    const float TMAX = 100.0;
    const float EPS  = 1e-4;
    const int MAX_STEPS = 128;

    float t = 0.0;
    for (int i = 0; i < MAX_STEPS; ++i) {
        vec3 p = ro + t * rd;
        float d = sdf(p);              // 到最近表面的距离
        if (d < EPS) return t;         // 命中
        t += d;                        // 走一个"安全距离"
        if (t > TMAX) break;
    }
    return -1.0;
}
```

**收敛性分析**：

- 在远离表面时，$\text{sdf}$ 很大，每步跨越很远，算法效率高。
- 越接近表面，步长越小，呈现**几何级数收敛**到表面。
- 最坏情况是光线**掠射**（grazing）表面：每一步只能往前推进 $\text{sdf}$，但 $\text{sdf}$ 的减小非常缓慢，需要很多步。

掠射的几何解释：设光线与表面的夹角为 $\theta$，光线行进 $\Delta t$ 后到表面的距离减小约 $\Delta t \sin \theta$。当 $\theta$ 接近 0，每一步收益极小。这就是 Sphere Tracing 在切面处性能下降的原因。

### 9. SDF 的原语与组合（CSG）

SDF 之所以好用，在于它能用**简单的代数运算**构造复杂形状。

**几个基本原语**：

```glsl
// 球（中心在原点，半径 r）
float sdSphere(vec3 p, float r) {
    return length(p) - r;
}

// 轴对齐盒子（半边长 b）
float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// 无限平面（法线为 n，n 已归一化）
float sdPlane(vec3 p, vec3 n, float h) {
    return dot(p, n) + h;
}

// 圆环（环面）
float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}
```

**布尔运算（CSG）**：

| 操作        | 公式                                |
| ----------- | ----------------------------------- |
| 并（A ∪ B） | $\min(\text{sdf}_A, \text{sdf}_B)$  |
| 交（A ∩ B） | $\max(\text{sdf}_A, \text{sdf}_B)$  |
| 差（A − B） | $\max(\text{sdf}_A, -\text{sdf}_B)$ |

⚠️ 严格地讲，$\min/\max$ 只在**表面附近**保持 1-Lipschitz 性质，离表面较远处可能给出大于真实距离的值（但不会超过真实距离，所以仍然是"保守的安全步长"）。Sphere Tracing 仍然正确，只是可能多走几步。

**平滑并（smooth min）** 是 SDF 建模的杀手锏：

$$ \text{smin}_k(a, b) = -\frac{1}{k}\ln(e^{-ka} + e^{-kb}) $$

或更常用的多项式版本：

$$ h = \text{clamp}\left(0.5 + \frac{0.5(b-a)}{k}, 0, 1\right), \quad \text{smin}_k(a, b) = \text{mix}(b, a, h) - k \cdot h(1-h) $$

它能让两个 SDF 在交界处产生光滑过渡（"blob"效果）。

**变换**：

- 平移：$\text{sdf}(\mathbf{p} - \mathbf{t})$
- 旋转：$\text{sdf}(R^{-1}\mathbf{p})$
- 均匀缩放 $s$：$s \cdot \text{sdf}(\mathbf{p}/s)$
- 重复（无限阵列）：$\text{sdf}(\text{mod}(\mathbf{p}, c) - 0.5c)$，这是 SDF 的另一个魔术——几行代码生成无限多个物体。

### 10. 从 SDF 推导法线

SDF 是距离函数，其梯度方向就是"离开表面最快的方向"，即表面法线：

$$ \mathbf{n}(\mathbf{p}) = \frac{\nabla \text{sdf}(\mathbf{p})}{|\nabla \text{sdf}(\mathbf{p})|} $$

实际渲染中用**中心差分**数值近似：

```glsl
vec3 calcNormal(vec3 p) {
    const float h = 1e-4;
    const vec2 k = vec2(1.0, -1.0);
    return normalize(
        k.xyy * sdf(p + k.xyy * h) +
        k.yyx * sdf(p + k.yyx * h) +
        k.yxy * sdf(p + k.yxy * h) +
        k.xxx * sdf(p + k.xxx * h)
    );
}
```

这种"四次采样的对称组合"称为 **tetrahedron normal**，是 6 次采样的中心差分的廉价替代。

### 11. 软阴影、AO 的几何技巧

**硬阴影**：从交点 $\mathbf{p}$ 朝光源方向再发射一条 ray march，若命中则在阴影中。

**软阴影**：经典技巧来自 Inigo Quilez —— 沿阴影光线追踪时，记录"最近一次距离场值与到当前位置距离之比"的最小值：

```glsl
float softShadow(vec3 ro, vec3 rd, float tMin, float tMax, float k) {
    float res = 1.0;
    float t = tMin;
    for (int i = 0; i < 64 && t < tMax; ++i) {
        float h = sdf(ro + t * rd);
        if (h < 1e-4) return 0.0;
        res = min(res, k * h / t);
        t += h;
    }
    return clamp(res, 0.0, 1.0);
}
```

**直观解释**：$h/t$ 是从光源角度看到的"光线掠过表面的张角"近似。越小则被遮挡越严重；保留沿途最小值即得软阴影系数。$k$ 是软度参数。

**Ambient Occlusion**：从表面点沿法线方向多采样几次 SDF，比较"理论上应该是的距离"和"实际 SDF 值"的差：

```glsl
float ao(vec3 p, vec3 n) {
    float occ = 0.0;
    float scale = 1.0;
    for (int i = 0; i < 5; ++i) {
        float h = 0.01 + 0.12 * float(i) / 4.0;
        float d = sdf(p + n * h);
        occ += (h - d) * scale;
        scale *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}
```

`h - d` 越大，说明表面比"应有距离"更近，遮蔽更强。

------

## 第四部分：体积渲染

体积渲染是 Ray Marching 在**离线和实时**都必不可少的应用：云、烟、雾、火焰、皮下散射、上帝光。

### 12. 体积渲染方程的推导

考虑一条光线穿过参与介质（云、雾），介质中每一点有：

- **吸收系数** $\sigma_a(\mathbf{p})$：单位长度被吸收的辐射能比例
- **散射系数** $\sigma_s(\mathbf{p})$：单位长度被散射出去的辐射能比例
- **消光系数** $\sigma_t = \sigma_a + \sigma_s$：总能量损失率
- **自发光** $L_e(\mathbf{p}, \mathbf{d})$：介质本身辐射的能量（火焰）
- **入散射** $L_s(\mathbf{p}, \mathbf{d})$：从其他方向被散射到 $\mathbf{d}$ 方向的能量

**从能量守恒出发**：沿光线 $\mathbf{r}(t) = \mathbf{o} + t\mathbf{d}$ 走 $dt$ 的距离，辐射亮度 $L(t)$ 的变化由四部分组成：

$$ \frac{dL}{dt} = \underbrace{-\sigma_t(t) L(t)}*{\text{吸收+外散射}} + \underbrace{\sigma_s(t) L_s(t)}*{\text{入散射}} + \underbrace{\sigma_a(t) L_e(t)}_{\text{自发光}} $$

这是著名的 **Radiative Transfer Equation（RTE）**。

**求解过程**：先考虑没有散射和自发光的情形：

$$ \frac{dL}{dt} = -\sigma_t(t) L(t) $$

这是一阶线性常微分方程，解为：

$$ L(t) = L(0) \exp\left(-\int_0^t \sigma_t(s) , ds\right) $$

定义**光学厚度（optical depth）**：

$$ \tau(a, b) = \int_a^b \sigma_t(s) , ds $$

则 **透射率（transmittance）**：

$$ T(a, b) = e^{-\tau(a, b)} $$

这就是 **Beer-Lambert 定律**（下一节单独再讲）。

**完整解**：把入散射和自发光当作"源项"，用积分因子法求解非齐次 ODE。设源项 $J(t) = \sigma_s(t) L_s(t) + \sigma_a(t) L_e(t)$，则：

$$ \boxed{L(D) = T(0, D) \cdot L(0) + \int_0^D T(t, D) \cdot J(t) , dt} $$

其中 $D$ 是光线穿出介质的距离。这就是 **体积渲染方程**。

物理含义直观：

- $T(0, D) \cdot L(0)$：背景光经过整段介质衰减后剩下的部分。
- $\int_0^D T(t, D) J(t) dt$：介质中每一点产生的光（自发光或被照亮的散射），再衰减到出射点。

### 13. Beer-Lambert 定律

Beer-Lambert 定律就是上面的特例：纯吸收介质下，透射率随光学厚度指数衰减：

$$ T = e^{-\int \sigma_t , ds} $$

**直观推导**：若一束光通过厚度 $dx$ 的薄层，损失比例为 $\sigma_t , dx$，则：

$$ \frac{dI}{I} = -\sigma_t , dx ;\Rightarrow; I(x) = I_0 e^{-\sigma_t x} $$

均匀介质下 $\sigma_t$ 是常数，非均匀介质下沿光线积分。

### 14. 离散化与数值积分

体积渲染方程是一个积分方程，**实时渲染不能解析地算**，必须数值地走。这就是体积 Ray Marching。

把光线分成 $N$ 段，每段长度 $\Delta t$，端点 $t_i = i \Delta t$。第 $i$ 段中点的密度记为 $\sigma_i$，源项 $J_i$。

**透射率离散化**：

$$ T_i = \exp\left(-\sum_{k=0}^{i-1} \sigma_k \Delta t\right) = \prod_{k=0}^{i-1} e^{-\sigma_k \Delta t} $$

**积分离散化**（中点法则）：

$$ L \approx \sum_{i=0}^{N-1} T_i \cdot J_i \cdot \Delta t $$

如果用更精确的"每段内 $\sigma_i, J_i$ 视为常数"的解析积分（**analytic step integration**）：

考虑单段内 $\sigma, J$ 为常数，则光从段头进，段尾出的关系：

$$ L_{\text{out}} = L_{\text{in}} e^{-\sigma \Delta t} + \frac{J}{\sigma}(1 - e^{-\sigma \Delta t}) $$

第二项即"该段对最终亮度的贡献"。这种形式对积分**保能量**更友好，是 Wrenninge、Frostbite 等引擎使用的版本。

**前向 vs 后向遍历**：

- **后向**（front-to-back，从相机出发）：累加亮度的同时维护当前透射率 $T$，当 $T$ 足够小（如 $< 0.01$）时**早停**。这是实时渲染的标准做法。

```glsl
vec3 L = vec3(0.0);
float T = 1.0;
for (int i = 0; i < N; ++i) {
    vec3 p = ro + (i + 0.5) * dt * rd;
    float sigma = density(p);
    vec3 J = lightContribution(p);     // 来自太阳的入散射
    float Ti = exp(-sigma * dt);
    L += T * J * (1.0 - Ti);           // 解析步内积分
    T *= Ti;
    if (T < 0.01) break;               // 早停
}
return vec4(L, 1.0 - T);               // alpha = 1 - 透射率
```

### 15. 相函数（Phase Function）

入散射项 $L_s$ 实际上是个对所有入射方向的积分：

$$ L_s(\mathbf{p}, \mathbf{d}) = \int_{S^2} p(\mathbf{d}, \mathbf{d}') L(\mathbf{p}, \mathbf{d}') , d\mathbf{d}' $$

其中 $p(\mathbf{d}, \mathbf{d}')$ 是**相函数**，描述从方向 $\mathbf{d}'$ 入射的光被散射到方向 $\mathbf{d}$ 的概率密度。它必须归一化：

$$ \int_{S^2} p(\mathbf{d}, \mathbf{d}') , d\mathbf{d}' = 1 $$

实时渲染中，通常只考虑太阳作为光源（delta 函数方向），积分退化为单次乘法。常用的相函数：

**各向同性**：$p = \frac{1}{4\pi}$

**Henyey-Greenstein**：

$$ p_{HG}(\cos\theta; g) = \frac{1}{4\pi} \cdot \frac{1 - g^2}{(1 + g^2 - 2g\cos\theta)^{3/2}} $$

参数 $g \in (-1, 1)$ 控制散射的方向性：

- $g > 0$：前向散射（向光的方向更亮）—— 云、雾
- $g = 0$：各向同性
- $g < 0$：后向散射

实时云通常用 $g \approx 0.6$ 模拟"对着太阳看，云的边缘特别亮"的效果（即 **silver lining**）。

**双瓣 HG**：把两个 $g$ 不同的 HG 函数加权混合，能更逼真：

$$ p_{\text{double}} = (1-\alpha) p_{HG}(g_1) + \alpha p_{HG}(g_2) $$

通常 $g_1 \approx 0.8$（强前向散射，太阳光晕），$g_2 \approx -0.5$（轻微后向），$\alpha \approx 0.5$。

### 16. 应用：体积云渲染

工业界的实时体积云大体上来自 Schneider 2015 在 GDC 的演讲（Horizon Zero Dawn 的云）。核心步骤：

**第一步：建模密度场**

密度场由几个噪声纹理组合：

- **Perlin-Worley 3D 纹理**：基础形状
- **更高频的 Worley 噪声**：边缘细节
- **天气图 2D 纹理**：覆盖率、云类型

伪代码：

```glsl
float cloudDensity(vec3 p) {
    // 高度衰减：底部硬边、顶部蓬松
    float h = (p.y - CLOUD_BOTTOM) / (CLOUD_TOP - CLOUD_BOTTOM);
    float heightGrad = remap(h, 0.0, 0.07, 0.0, 1.0)
                     * remap(h, 0.2, 1.0, 1.0, 0.0);

    // 天气图：(coverage, type, _)
    vec3 weather = texture(weatherMap, p.xz * WEATHER_SCALE).rgb;
    float coverage = weather.r;

    // 基础形状
    vec4 base = texture(noise3D, p * BASE_SCALE);
    float baseShape = remap(base.r, base.g * 0.625 + 0.25, 1.0, 0.0, 1.0);
    baseShape *= heightGrad;

    // 用 coverage 进一步遮罩
    float shaped = remap(baseShape, 1.0 - coverage, 1.0, 0.0, 1.0);

    // 高频细节侵蚀边缘
    vec3 detail = texture(detail3D, p * DETAIL_SCALE).rgb;
    float detailNoise = mix(detail.r, 1.0 - detail.r, smoothstep(0.0, 0.5, h));
    shaped -= detailNoise * 0.35 * (1.0 - shaped);

    return clamp(shaped * coverage, 0.0, 1.0);
}
```

**第二步：相机光线步进**

```glsl
vec4 renderClouds(vec3 ro, vec3 rd) {
    // 求光线与云层（两个高度平面之间）的相交段
    float tMin, tMax;
    intersectCloudLayer(ro, rd, tMin, tMax);

    int numSteps = 64;
    float dt = (tMax - tMin) / float(numSteps);

    vec3 L = vec3(0.0);
    float T = 1.0;
    float t = tMin + dt * hash(gl_FragCoord.xy);  // 抖动

    for (int i = 0; i < numSteps; ++i) {
        vec3 p = ro + t * rd;
        float sigma = cloudDensity(p) * DENSITY_SCALE;

        if (sigma > 0.0) {
            // 光照：从 p 朝太阳方向再 ray march 一段，估算 T_sun
            float Tsun = lightMarch(p);
            float mu = dot(rd, sunDir);
            float phase = doubleHG(mu);

            vec3 J = SUN_COLOR * Tsun * phase * sigma;
            float Ti = exp(-sigma * dt);
            L += T * J * (1.0 - Ti) / max(sigma, 1e-4);  // 解析步内积分
            T *= Ti;
            if (T < 0.01) break;
        }
        t += dt;
    }
    return vec4(L, 1.0 - T);
}
```

**第三步：阳光透射率 `lightMarch`**

从云内部一点出发向太阳方向，估算多少阳光能到达此点：

```glsl
float lightMarch(vec3 p) {
    const int LSTEPS = 6;
    float tau = 0.0;
    float dt = LIGHT_MARCH_LENGTH / float(LSTEPS);
    // 用越来越大的步长，远的密度对结果影响小
    float step = dt;
    for (int i = 0; i < LSTEPS; ++i) {
        vec3 q = p + sunDir * step * (float(i) + 0.5);
        tau += cloudDensity(q) * dt;
    }
    return exp(-tau * DENSITY_SCALE);
}
```

**进一步优化（实战）**：

1. **半分辨率渲染 + 时序重投影**：云每帧只追 1/16 的像素，靠上一帧填充剩下的。
2. **早停**：当 $T < 0.01$ 时退出。
3. **自适应步长**：在云外用大步长扫描，进入云内后切换成小步长。
4. **Powder 效应**：朝向太阳看时云内部更暗（被外层吸收），用经验公式 $1 - e^{-2\sigma t}$ 乘以 $T_{\text{sun}}$ 来近似多重散射的视觉效果。

------

## 第五部分：屏幕空间 Ray Marching

### 17. 用 G-Buffer 当作场景的近似

延迟渲染管线已经把屏幕上每个像素的几何信息存进了 G-Buffer：

- **深度图**：每个像素离相机最近的表面深度
- **法线图**：该表面的法线
- **颜色图**：该像素的着色结果（或材质属性）

把这三张图视为**"从相机视角能看到的场景的稀疏 1-层近似"**，就可以在屏幕空间做光线步进——不需要 BVH，不需要任何 3D 加速结构。

**代价**：

- 屏幕外的几何无法参与
- 被遮挡的几何（深度图记录的"后面"那一层）不存在
- 几何边缘会出错（薄表面无厚度信息）

但它**极快**，且能在光栅化管线下"白送"，因此成为 PBR 时代标配。

### 18. 应用：SSR（屏幕空间反射）

**算法骨架**：

```
对每个屏幕像素：
  1. 从深度+法线重建视空间位置 P 和法线 N
  2. R = reflect(-viewDir, N)
  3. 从 P 沿 R 在视空间或屏幕空间步进
  4. 每步把当前 3D 点投影回屏幕 → UV
  5. 比较 ray 的 depth 与 depthTex(UV)：若 ray 钻到表面后方，则命中
  6. 用 UV 采颜色返回
```

**关键代码（视空间步进，最简版）**：

```glsl
vec3 viewPosFromUVDepth(vec2 uv, float depth) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 v = invProj * ndc;
    return v.xyz / v.w;
}

vec4 SSR(vec2 uv) {
    float depth = texture(depthTex, uv).r;
    if (depth >= 1.0) return vec4(0.0);

    vec3 P = viewPosFromUVDepth(uv, depth);
    vec3 N = normalize(texture(normalTex, uv).xyz * 2.0 - 1.0);
    vec3 V = normalize(P);                 // 相机在视空间原点
    vec3 R = reflect(V, N);

    float t = 0.0;
    vec3 rayPos = P;
    for (int i = 0; i < MAX_STEPS; ++i) {
        rayPos += R * STEP_SIZE;
        vec4 clip = proj * vec4(rayPos, 1.0);
        if (clip.w <= 0.0) break;
        vec3 ndc = clip.xyz / clip.w;
        vec2 sUV = ndc.xy * 0.5 + 0.5;
        if (any(lessThan(sUV, vec2(0.0))) || any(greaterThan(sUV, vec2(1.0)))) break;

        float sceneDepth = texture(depthTex, sUV).r;
        vec3 scenePos = viewPosFromUVDepth(sUV, sceneDepth);

        float delta = rayPos.z - scenePos.z;     // 视空间下，z 越负越远
        if (delta < 0.0 && -delta < THICKNESS) {
            return vec4(texture(sceneColor, sUV).rgb, 1.0);
        }
    }
    return vec4(0.0);
}
```

**工程上必须做的几件事**：

1. **二分细化**：首次穿透后用二分查找精确化命中点。
2. **抖动**：消除条带。
3. **边缘淡出**：到屏幕边缘时把 alpha 平滑到 0。
4. **菲涅尔加权混合**：SSR 只是反射的一个来源，按菲涅尔系数与反射探针、平面反射、RT 反射混合。

由于上一轮已经详细写过 SSR，这里不再重复，重点在于把它放入整个 Ray Marching 体系中。

### 19. 应用：SSAO / SS Contact Shadow / SSGI

**SSAO（屏幕空间环境光遮蔽）**：不需要追真正的光线。在每个像素法线半球内随机采样若干个 3D 点，检查每个采样点投影到屏幕后的深度，是否被 G-Buffer 中的"前景表面"挡住。挡住的比例就是 AO。

这其实是 Ray Marching 的退化形式：步长 = 1 步（采样点本身就是终点）。

**SS Contact Shadow（屏幕空间接触阴影）**：从每个像素朝光源方向短距离 ray march 一段（通常 8–16 步），用以补足 shadow map 在物体接触处的精度缺失。这是**纯粹的屏幕空间 ray marching**，与 SSR 共用同一套深度比较逻辑，只是方向换成了光源方向。

**SSGI（屏幕空间全局光照）**：每个像素发若干条 ray 在屏幕空间步进，命中后采样该处的亮度作为间接光来源。比 SSR 多的是"二次反弹"和"基于法线半球的随机采样"。

可以看到，这三个 + SSR 共享同一套底层算法——**屏幕空间 ray marching**——只是初始方向和命中后的处理不同。

### 20. Hi-Z 加速

朴素屏幕空间 ray march 每步采一次深度图，步长由用户设定。**Hi-Z（Hierarchical-Z）** 提供了"自适应大步长"的能力。

**Hi-Z 是什么**：把深度图做成 mipmap，但每级**保存的是 2×2 块的最大深度**（注意是 max，不是平均；离相机最远的那个深度）。这样上层 mip 给出一个**保守的远端边界**——若 ray 在这一片区域的最深处仍未到达表面，那它在此 mip 等级下"安全可飞"。

**算法骨架**：

```
mip = 起始 mip 等级
while not terminated:
    在当前 mip 的格子内，沿 ray 方向走到下一个格子边界
    采样 Hi-Z(mip) 得到 d_max
    if ray.z 仍小于 d_max：
        ray 没碰到任何东西，提升 mip（更大步长）
    else:
        可能命中，降低 mip 仔细测
        若已在 mip 0 且确实命中 → 返回
```

这相当于把屏幕空间的深度图当成一个**保守距离场**用，每步走"最近一定空着"的距离。本质上回到了 Sphere Tracing 的思想，只不过距离来自 Hi-Z。

McGuire 的 2014 论文与 Uludag 在 GPU Pro 5 的章节是经典参考。

------

## 第六部分：DDA 与体素遍历

### 21. Amanatides & Woo 算法

当场景是**规则网格**（如体素世界），Ray Marching 退化成一个非常优雅的问题：找出光线依次穿过哪些格子。

经典算法是 Amanatides & Woo (1987) 的 3D 数字微分分析法（3D-DDA）。

**核心思想**：把光线参数 $t$ 推进到下一个格子边界，每次只跨越一个轴。

**初始化**：

设光线 $\mathbf{r}(t) = \mathbf{o} + t \mathbf{d}$，格子大小为 1。

- 当前格子坐标 $(i, j, k) = \lfloor \mathbf{o} \rfloor$
- 步进方向 $\text{step}_x = \text{sign}(d_x)$（同理 $y, z$）
- $tMax_x$ = 光线沿 x 轴穿过下一条 x 边界所需的 $t$ 值
- $tDelta_x = |1/d_x|$（沿 x 轴每跨一个格子所需的 $t$ 增量）

**循环**：

```glsl
while (在边界内) {
    if (grid[i,j,k] 被占用) return hit;

    if (tMax.x < tMax.y) {
        if (tMax.x < tMax.z) {
            i += step.x;
            tMax.x += tDelta.x;
        } else {
            k += step.z;
            tMax.z += tDelta.z;
        }
    } else {
        if (tMax.y < tMax.z) {
            j += step.y;
            tMax.y += tDelta.y;
        } else {
            k += step.z;
            tMax.z += tDelta.z;
        }
    }
}
```

这是 **精确** 的：不会错过任何格子，也不会重复访问；每次循环 $O(1)$。

GLSL 中的精简版：

```glsl
bool dda(vec3 ro, vec3 rd, out ivec3 hitCell, out vec3 hitNormal) {
    ivec3 cell = ivec3(floor(ro));
    vec3 step  = sign(rd);
    vec3 tDelta = abs(1.0 / rd);
    vec3 tMax  = (vec3(cell) + max(step, 0.0) - ro) / rd;

    for (int i = 0; i < 256; ++i) {
        if (isSolid(cell)) { hitCell = cell; return true; }

        // 选 tMax 最小的轴推进
        bvec3 mask = lessThanEqual(tMax.xyz, min(tMax.yzx, tMax.zxy));
        tMax += vec3(mask) * tDelta;
        cell += ivec3(mask) * ivec3(step);

        // 命中面的法线
        hitNormal = -vec3(mask) * step;

        if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, dims))) break;
    }
    return false;
}
```

### 22. 应用：体素地形

Minecraft、Teardown、Cyberpunk 的体素霓虹反射，都用了某种形式的 DDA。

**优点**：

- 不需要三角形，无 BVH
- 命中时直接知道格子坐标和击中的面（即法线）
- 完美适合稀疏八叉树（SVO）加速：当 ray 进入"全空"的大块时，可以直接用更大的步长跨过

**SVO 加速**：把 DDA 推广到层次结构上——若当前节点空，跳过整个节点；若非空且非叶子，下降一层。这是 Cyril Crassin 的 GigaVoxels 和 Sparse Voxel DAG 的核心。

------

## 第七部分：进阶与优化

### 23. 锥追踪（Cone Tracing）

到目前为止我们都把光线当作"零厚度的直线"。但在很多应用中（粗糙反射、间接光、AO），我们想知道的是**一个圆锥范围**内的平均情况。

**Voxel Cone Tracing (VCT)**：场景用 3D 纹理 + mipmap 存储辐射度。当沿锥前进时，每一步采样一个**和锥半径匹配的 mip 等级**。锥越宽，采样 mip 越高（越模糊）。

```glsl
vec4 coneTrace(vec3 origin, vec3 dir, float coneAngle) {
    vec4 acc = vec4(0.0);
    float t = VOXEL_SIZE;
    while (acc.a < 0.95 && t < MAX_DIST) {
        float radius = t * tan(coneAngle);
        float mip = log2(radius / VOXEL_SIZE);
        vec4 sampleVal = textureLod(voxelTex, origin + dir * t, mip);
        // front-to-back compositing
        acc.rgb += (1.0 - acc.a) * sampleVal.a * sampleVal.rgb;
        acc.a   += (1.0 - acc.a) * sampleVal.a;
        t += radius;     // 步长随锥扩张
    }
    return acc;
}
```

它把"在锥内积分大量光线"近似成"沿锥轴步进，每步用 mipmap 做体积平均"，是 Lumen 之前主流的实时 GI 方案之一。

### 24. 时序累积与降噪

Ray Marching 类算法的输出几乎总是带噪的（抖动、蒙特卡洛采样、屏幕空间不可见区域）。**TAA（时间抗锯齿）** 提供了"廉价超采样"：

$$ C_n = \alpha \cdot C_n^{\text{current}} + (1 - \alpha) \cdot C_{n-1}^{\text{reprojected}} $$

其中 $\alpha$ 通常取 $0.05 \sim 0.1$。$C_{n-1}^{\text{reprojected}}$ 是用 motion vector 把上一帧的像素位置变换到当前帧后的颜色。

配合**蓝噪声抖动**（每帧用不同的蓝噪声样本），TAA 能把 SSR、体积云、SSAO 的噪声降到肉眼几乎看不见。

### 25. 大气散射

大气是体积渲染的极限案例：地球半径量级的距离 + 海拔指数衰减的密度 + 双相函数（Rayleigh + Mie）。

核心思想仍是体积渲染方程的离散化 ray marching，但有几个特殊点：

1. 介质沿径向高度衰减：$\sigma(h) = \sigma_0 e^{-h/H}$，$H$ 是尺度高度（Rayleigh ≈ 8 km，Mie ≈ 1.2 km）。
2. 入射光在大气中**两次衰减**：先从太阳到散射点 $P$，再从 $P$ 到相机。
3. 用预计算 LUT 加速：Bruneton 2008 的方法把"光学厚度"做成 2D 纹理，把"单次散射"做成 4D 纹理（4D 用 3D 纹理切片存储），运行时只需查表。

伪代码（不查表的朴素版）：

```glsl
vec3 atmosphericScattering(vec3 ro, vec3 rd) {
    float tEnter, tExit;
    intersectAtmosphere(ro, rd, tEnter, tExit);

    vec3 rayleigh = vec3(0.0);
    vec3 mie = vec3(0.0);
    float opticalDepthR = 0.0;
    float opticalDepthM = 0.0;

    float dt = (tExit - tEnter) / N;
    for (int i = 0; i < N; ++i) {
        vec3 p = ro + rd * (tEnter + (i + 0.5) * dt);
        float h = length(p) - PLANET_RADIUS;
        float densityR = exp(-h / H_R) * dt;
        float densityM = exp(-h / H_M) * dt;
        opticalDepthR += densityR;
        opticalDepthM += densityM;

        // 朝太阳方向再次 ray march 一段，得到 sunOpticalDepth
        vec2 sunOptD = sunOpticalDepth(p, sunDir);

        vec3 tau = BETA_R * (opticalDepthR + sunOptD.x)
                 + BETA_M * 1.1 * (opticalDepthM + sunOptD.y);
        vec3 attn = exp(-tau);
        rayleigh += attn * densityR;
        mie      += attn * densityM;
    }

    float mu = dot(rd, sunDir);
    float phaseR = 3.0/(16.0 * PI) * (1.0 + mu*mu);
    float phaseM = phaseHG(mu, 0.76);

    return SUN_INTENSITY * (rayleigh * BETA_R * phaseR + mie * BETA_M * phaseM);
}
```

这里**双层嵌套** ray marching：外层沿视线，内层沿太阳方向。复杂度 $O(N^2)$，所以工业界几乎全用 LUT。

### 26. Ray Marching 与栅格化的结合

现代实时渲染管线（UE5 Lumen、Unity HDRP、Frostbite）几乎都不是"纯"光追或纯栅格化，而是混合：

| 阶段       | 用什么                                      |
| ---------- | ------------------------------------------- |
| 主可见性   | 栅格化（G-Buffer）                          |
| 反射       | SSR（屏幕空间 RM） + 反射探针 + 硬件 RT     |
| 接触阴影   | SS Contact Shadow（屏幕空间 RM）            |
| 间接光     | Surfel/Probe + screen probe + SS RM 修正    |
| 体积雾     | 视锥体素 + 体积 RM                          |
| 大气       | 预计算 LUT（积分自 RM）                     |
| 云         | 体积 RM（半分辨率 + 时序重投影）            |
| 软阴影补足 | RM in SDF（如 Lumen Distance Field Shadow） |

Lumen 中 **Distance Field Shadow** 和 **Distance Field AO** 就是经典 Sphere Tracing：场景里每个 mesh 烘焙了一个 SDF 体积纹理，运行时合并成一个"全局 SDF"，再用 sphere tracing 算软阴影和 AO。这把 SDF 从 demoscene 带回了 AAA 引擎。

------

## 附录 A：常用 SDF 公式表

```glsl
// 球
float sdSphere(vec3 p, float r) { return length(p) - r; }

// 盒子
float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// 圆角盒子
float sdRoundBox(vec3 p, vec3 b, float r) {
    return sdBox(p, b - r) - r;
}

// 环面
float sdTorus(vec3 p, vec2 t) {
    return length(vec2(length(p.xz) - t.x, p.y)) - t.y;
}

// 胶囊
float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// 平面
float sdPlane(vec3 p, vec3 n, float h) { return dot(p, n) + h; }
```

## 附录 B：CSG 运算

```glsl
float opUnion(float a, float b)        { return min(a, b); }
float opIntersect(float a, float b)    { return max(a, b); }
float opSubtract(float a, float b)     { return max(a, -b); }

float opSmoothUnion(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

vec3 opRepeat(vec3 p, vec3 c) {
    return mod(p + 0.5 * c, c) - 0.5 * c;
}
```

## 附录 C：推荐阅读

- **Inigo Quilez** 的个人站（iquilezles.org）：SDF 圣经
- **Shadertoy**：所有 Sphere Tracing 技巧的活体博物馆
- **GPU Pro 5, Chapter "Hi-Z Screen Space Tracing"**, Yasin Uludag
- **"Efficient GPU Screen-Space Ray Tracing"**, McGuire & Mara, 2014
- **"Real-Time Volumetric Cloudscapes"**, Schneider, GDC 2015
- **"Precomputed Atmospheric Scattering"**, Bruneton & Neyret, 2008
- **PBR Book, Chapter 11 "Volume Scattering"**：体积渲染方程的最权威推导
- **UE5 Lumen** 技术演讲（SIGGRAPH 2022）：实时 GI 中各类 RM 的工业级整合

------

## 结语：再看那张表

我们回到文章开头的"统一视角"表：

| 变体           | $f$ 是什么              | 条件                       |
| -------------- | ----------------------- | -------------------------- |
| Sphere Tracing | 到最近表面的距离        | $f \leq \varepsilon$       |
| 屏幕空间 SSR   | 投影后的深度 vs 深度图  | 钻到表面后方               |
| 体积渲染       | 介质消光系数 $\sigma_t$ | 光学厚度足够或穿出         |
| 体素 DDA       | 格子是否被占据          | 命中体素                   |
| 锥追踪         | mipmap 中的辐射度       | $\alpha \geq 0.95$（饱和） |

整个 Ray Marching 家族其实只在做一件事：**沿光线不断采样某种"场"，根据场的值决定下一步走多远，直到命中条件成立。** 不同变体的差别仅仅在于"场是什么"和"如何用场决定步长"。

理解了这一点，新的算法（无论是论文里的还是你自己设计的）都不过是这张表添一行。

—— 完