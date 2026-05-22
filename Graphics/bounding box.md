# 计算机图形学中的 Bounding Box 完全指南

> 从零开始：定义、构造、相交测试，到 GPU 端的视锥剔除与遮挡剔除。 所有内容附严格数学推导，关键算法配 C++ / GLSL 示例。

------

## 目录

1. 为什么我们需要 Bounding Box
2. 数学符号与基础约定
3. **AABB (Axis-Aligned Bounding Box)**
4. **Bounding Sphere**
5. **OBB (Oriented Bounding Box)**
6. **k-DOP**
7. 统一相交框架：分离轴定理 (SAT)
8. Ray–AABB：Slab 方法
9. 应用一：视锥剔除 (Frustum Culling)
10. 应用二：遮挡剔除 (Occlusion Culling)
11. 应用三：BVH 与光线追踪
12. 工程实践与常见陷阱

------

## 0. 为什么我们需要 Bounding Box

任何严肃的几何处理——碰撞检测、光线追踪、空间查询、剔除——直接在原始几何（成千上万的三角形）上做都是不可承受的。我们用一个**简单的几何代理 (proxy)** 把复杂物体包起来，先在代理上做廉价测试：

- 若代理测试**否定**（不相交 / 不可见），就可以**100% 安全地跳过**真实几何。
- 若代理测试**肯定**，再用真实几何做精确测试（或干脆直接当作通过）。

这就是所谓的**保守 (conservative) 剔除/测试**：宁可放过 (false positive)，绝不漏杀 (false negative)。Bounding Box 是这套范式里最常用的代理。

**核心权衡**：

| 代理类型    | 紧密度 (tightness) | 测试开销 | 构造/更新开销  |
| ----------- | ------------------ | -------- | -------------- |
| Sphere      | 差                 | 极低     | 低             |
| AABB        | 中                 | 低       | 极低           |
| OBB         | 好                 | 高       | 中（一次性高） |
| k-DOP       | 较好               | 中       | 中             |
| Convex Hull | 极好               | 极高     | 高             |

工程上**90% 以上的场合用 AABB**，剩下的根据需要选 Sphere 或 OBB。

------

## 1. 数学符号与基础约定

- 三维欧氏空间 $\mathbb{R}^3$，列向量约定。
- 点 / 向量用粗体小写：$\mathbf{p}, \mathbf{v}$；矩阵大写：$M$。
- 一个点集 $S = {\mathbf{p}_1, \dots, \mathbf{p}_n} \subset \mathbb{R}^3$。
- 向量分量用下标：$\mathbf{p} = (p_x, p_y, p_z)$ 或 $(p_0, p_1, p_2)$。
- 点积 $\mathbf{a}\cdot\mathbf{b}$，叉积 $\mathbf{a}\times\mathbf{b}$。

**保守性 (conservativeness) 的形式定义**：代理 $B$ 包围几何 $G$ 意味着 $G \subseteq B$。任何在 $B$ 上的"否定"测试结果对 $G$ 也成立；但"肯定"结果不保证 $G$ 也肯定。

------

## 2. AABB (Axis-Aligned Bounding Box)

### 2.1 定义

AABB 是与世界坐标轴对齐的最小长方体：

$$ \text{AABB}(S) = { \mathbf{x} \in \mathbb{R}^3 : \mathbf{m} \le \mathbf{x} \le \mathbf{M} } $$

其中 $\le$ 按分量比较，

$$ \mathbf{m}*i = \min*{\mathbf{p}\in S} p_i, \qquad \mathbf{M}*i = \max*{\mathbf{p}\in S} p_i. $$

### 2.2 两种等价表示

| 表示             | 存储                                                         | 优点               |
| ---------------- | ------------------------------------------------------------ | ------------------ |
| `min/max`        | $\mathbf{m}, \mathbf{M}$                                     | 构造、合并直观     |
| `center/extents` | $\mathbf{c}=\tfrac{\mathbf{m}+\mathbf{M}}{2}, \mathbf{e}=\tfrac{\mathbf{M}-\mathbf{m}}{2}$ | 变换、SAT 测试方便 |

两者随时可互换，工程上常常**两者都存**或选最常用的那个。

### 2.3 从点集构造

$O(n)$ 一遍扫描即可：

```cpp
struct AABB {
    glm::vec3 mn, mx;

    static AABB FromPoints(const glm::vec3* pts, size_t n) {
        AABB b;
        b.mn = glm::vec3( std::numeric_limits<float>::infinity());
        b.mx = glm::vec3(-std::numeric_limits<float>::infinity());
        for (size_t i = 0; i < n; ++i) {
            b.mn = glm::min(b.mn, pts[i]);
            b.mx = glm::max(b.mx, pts[i]);
        }
        return b;
    }

    glm::vec3 Center()  const { return 0.5f * (mn + mx); }
    glm::vec3 Extents() const { return 0.5f * (mx - mn); } // 半长
    glm::vec3 Size()    const { return mx - mn; }
};
```

注意初始化要用 $\pm\infty$，**不要**初始化成第一个点，那样要做 `n-1` 次特殊判断。

### 2.4 基本操作

**合并 (Merge)**：两个 AABB 的并的最小 AABB。

```cpp
AABB Merge(const AABB& a, const AABB& b) {
    return { glm::min(a.mn, b.mn), glm::max(a.mx, b.mx) };
}
```

**点包含**：

```cpp
bool Contains(const AABB& b, glm::vec3 p) {
    return glm::all(glm::greaterThanEqual(p, b.mn))
        && glm::all(glm::lessThanEqual   (p, b.mx));
}
```

**AABB–AABB 相交**（重叠 / 不重叠）：

$$ A \cap B \neq \emptyset \iff \forall i:\ A.m_i \le B.M_i ,\wedge, A.M_i \ge B.m_i. $$

```cpp
bool Overlap(const AABB& a, const AABB& b) {
    return glm::all(glm::lessThanEqual   (a.mn, b.mx))
        && glm::all(glm::greaterThanEqual(a.mx, b.mn));
}
```

证明（必要性显然，充分性）：若每个轴上区间都重叠，则存在 $x_i \in [\max(A.m_i,B.m_i),\ \min(A.M_i,B.M_i)]$；构造的 $\mathbf{x}=(x_0,x_1,x_2)$ 同时在 $A$ 和 $B$ 中。$\square$

### 2.5 AABB 的变换：Arvo 方法（**重点**）

**问题**：物体的 AABB 在物体局部空间里算好了，现在物体被矩阵 $M$（仿射变换，含旋转/缩放）+ 平移 $\mathbf{t}$ 搬到了世界空间，**世界空间的 AABB 怎么算？**

**错误做法**：把 8 个角变换后取 min/max。能用，但有 8 次矩阵–向量乘法。

**Arvo 方法（1990）**：只需 1 次矩阵–向量乘法 + 9 次 `fabs` + 9 次 mul-add。

#### 推导

用 center/extents 表示原 AABB：任意原点可写为

$$ \mathbf{p} = \mathbf{c} + \mathbf{d}, \quad |d_j| \le e_j. $$

变换后

$$ \mathbf{p}' = M\mathbf{p} + \mathbf{t} = (M\mathbf{c}+\mathbf{t}) + M\mathbf{d}. $$

新中心显然是 $\mathbf{c}' = M\mathbf{c}+\mathbf{t}$。第 $i$ 个分量上的位移：

$$ (M\mathbf{d})*i = \sum_j M*{ij}, d_j. $$

绝对值放缩，

$$ |(M\mathbf{d})*i| \le \sum_j |M*{ij}|, |d_j| \le \sum_j |M_{ij}|, e_j. $$

而且这个上界**可达**：取 $d_j = e_j \cdot \mathrm{sign}(M_{ij})$ 即可。因此

$$ \boxed{\ e'*i = \sum_j |M*{ij}|, e_j\ } $$

即"**用 $|M|$ 乘以原 extents**"。

```cpp
AABB TransformAABB(const AABB& b, const glm::mat4& M) {
    glm::vec3 c  = b.Center();
    glm::vec3 e  = b.Extents();

    glm::mat3 R  = glm::mat3(M);                     // 取上 3x3
    glm::mat3 Ra(glm::abs(R[0]), glm::abs(R[1]), glm::abs(R[2]));

    glm::vec3 c2 = glm::vec3(M * glm::vec4(c, 1.0f));
    glm::vec3 e2 = Ra * e;                           // 重点

    return { c2 - e2, c2 + e2 };
}
```

#### 注意

- 该公式只在变换是**仿射**（线性 + 平移）时严格成立。投影变换会改变直线的相对位置，需要先做透视除法再算。
- 经过非轴对齐的旋转/缩放，新 AABB 一般**比原物体的真实最小 AABB 大**（因为我们包的是原 AABB，不是原几何）。每次 transform 都会"膨胀"，所以**长期累积变换的物体应当重算 AABB**，不要链式 `TransformAABB`。

------

## 3. Bounding Sphere

### 3.1 定义

包围球 $(\mathbf{c}, r)$ 满足 $\forall \mathbf{p}\in S: |\mathbf{p}-\mathbf{c}| \le r$。**最小包围球 (minimum enclosing sphere, MEB)** 是这样的球中半径最小者，由 Welzl 算法 $O(n)$ 期望复杂度求解。

工程上常用更便宜的近似——**Ritter 算法**，结果不是严格最小但通常只大 5%–20%，构造 $O(n)$。

### 3.2 Ritter 算法

**步骤**：

1. 一遍扫描，找出 $x, y, z$ 三方向上的极值点共 6 个，从中挑出**距离最远的一对** $(\mathbf{p}_a, \mathbf{p}_b)$。

2. 初始球：圆心 $\mathbf{c} = \tfrac{1}{2}(\mathbf{p}_a + \mathbf{p}_b)$，半径 $r = \tfrac{1}{2}|\mathbf{p}_a - \mathbf{p}_b|$。

3. 再扫描一遍：对每个点 $\mathbf{p}$，若 $|\mathbf{p}-\mathbf{c}| > r$，把球"扩展到刚好包住 $\mathbf{p}$"——

   $$ d = |\mathbf{p}-\mathbf{c}|,\quad r' = \tfrac{1}{2}(r+d),\quad \mathbf{c}' = \mathbf{c} + \tfrac{d-r}{d}(\mathbf{p}-\mathbf{c}) \cdot \tfrac{1}{2}. $$

   即沿 $\mathbf{c}\to\mathbf{p}$ 方向把球心平移到新中点。

```cpp
struct Sphere { glm::vec3 c; float r; };

Sphere RitterBoundingSphere(const glm::vec3* pts, size_t n) {
    // Step 1: 6 个极值点
    glm::vec3 xmin = pts[0], xmax = pts[0];
    glm::vec3 ymin = pts[0], ymax = pts[0];
    glm::vec3 zmin = pts[0], zmax = pts[0];
    for (size_t i = 1; i < n; ++i) {
        if (pts[i].x < xmin.x) xmin = pts[i];
        if (pts[i].x > xmax.x) xmax = pts[i];
        if (pts[i].y < ymin.y) ymin = pts[i];
        if (pts[i].y > ymax.y) ymax = pts[i];
        if (pts[i].z < zmin.z) zmin = pts[i];
        if (pts[i].z > zmax.z) zmax = pts[i];
    }
    auto d2 = [](glm::vec3 a, glm::vec3 b){ return glm::dot(a-b, a-b); };
    float dx = d2(xmax, xmin), dy = d2(ymax, ymin), dz = d2(zmax, zmin);
    glm::vec3 pa = xmin, pb = xmax;
    if (dy > dx && dy > dz) { pa = ymin; pb = ymax; }
    if (dz > dx && dz > dy) { pa = zmin; pb = zmax; }

    Sphere s;
    s.c = 0.5f * (pa + pb);
    s.r = glm::length(pb - s.c);

    // Step 2: 扩展
    for (size_t i = 0; i < n; ++i) {
        glm::vec3 d = pts[i] - s.c;
        float dist = glm::length(d);
        if (dist > s.r) {
            float newR = 0.5f * (s.r + dist);
            float k    = (newR - s.r) / dist;
            s.c += k * d;
            s.r  = newR;
        }
    }
    return s;
}
```

### 3.3 球–球相交

$$ |\mathbf{c}_a - \mathbf{c}_b| \le r_a + r_b. $$

**实践提示**：平方化以避免 sqrt。

```cpp
bool Overlap(const Sphere& a, const Sphere& b) {
    glm::vec3 d = a.c - b.c;
    float rs = a.r + b.r;
    return glm::dot(d, d) <= rs * rs;
}
```

### 3.4 AABB ↔ Sphere

判断球与 AABB 是否相交：找 AABB 内距离球心最近的点 $\mathbf{q}$，比较 $|\mathbf{q}-\mathbf{c}| \le r$。

```cpp
bool Overlap(const AABB& a, const Sphere& s) {
    glm::vec3 q = glm::clamp(s.c, a.mn, a.mx);
    glm::vec3 d = s.c - q;
    return glm::dot(d, d) <= s.r * s.r;
}
```

------

## 4. OBB (Oriented Bounding Box)

### 4.1 定义

OBB 是任意朝向的长方体，由：

- 中心 $\mathbf{c}$
- 三个正交单位轴 $\mathbf{u}_0, \mathbf{u}_1, \mathbf{u}_2$
- 三个半长 $e_0, e_1, e_2$

构成。OBB 内任意点：$\mathbf{c} + \sum_i \alpha_i \mathbf{u}_i,\ |\alpha_i|\le e_i$。

它比 AABB 紧得多——对于"长条形"或"斜放"的物体差距尤其大。代价是相交测试要做 15 轴的 SAT（见 §6）。

### 4.2 PCA 构造法（最常用的工程方法）

**思路**：取点集的协方差矩阵的特征向量作为局部坐标系，再在该坐标系下取轴对齐包围盒。

#### 推导

设点集 $S$ 的质心 $\bar{\mathbf{p}} = \tfrac{1}{n}\sum_i \mathbf{p}_i$。**协方差矩阵**：

$$ C = \frac{1}{n}\sum_{i=1}^{n} (\mathbf{p}_i - \bar{\mathbf{p}})(\mathbf{p}_i - \bar{\mathbf{p}})^T \in \mathbb{R}^{3\times 3}. $$

$C$ 是对称半正定矩阵，可对角化为 $C = U \Lambda U^T$，$U$ 的列即为正交特征向量 $\mathbf{u}_0,\mathbf{u}_1,\mathbf{u}_2$，对应点集主成分方向。

取这三个轴作为 OBB 坐标系，把所有点变到该坐标系下做 AABB，再变回世界：

```cpp
struct OBB { glm::vec3 c, u[3], e; };

OBB BuildOBB_PCA(const glm::vec3* pts, size_t n) {
    // 1. 均值
    glm::vec3 mean(0);
    for (size_t i=0;i<n;++i) mean += pts[i];
    mean /= float(n);

    // 2. 协方差
    glm::mat3 C(0);
    for (size_t i=0;i<n;++i) {
        glm::vec3 d = pts[i] - mean;
        C += glm::outerProduct(d, d);
    }
    C /= float(n);

    // 3. 特征分解 (省略：Jacobi 迭代或 SVD)
    glm::mat3 U; glm::vec3 lambda;
    SymmetricEigenSolve(C, U, lambda);   // 自行实现 / Eigen / DirectXMath

    // 4. 在 U 坐标系下做 AABB
    glm::vec3 lo( std::numeric_limits<float>::infinity());
    glm::vec3 hi(-std::numeric_limits<float>::infinity());
    for (size_t i=0;i<n;++i) {
        glm::vec3 q = glm::transpose(U) * (pts[i] - mean);
        lo = glm::min(lo, q);
        hi = glm::max(hi, q);
    }

    OBB o;
    glm::vec3 cl = 0.5f*(lo+hi);
    o.c    = mean + U * cl;
    o.u[0] = U[0]; o.u[1] = U[1]; o.u[2] = U[2];
    o.e    = 0.5f*(hi - lo);
    return o;
}
```

**注意**：PCA 对点的**分布**敏感，不是对**几何形状**敏感。一个长条物体表面均匀采样和顶点密集分布在某一端时，结果不一样。生产引擎里如果对 OBB 紧度要求高，常采用 [Larsson 的 DiTO](https://www.jcgt.org/published/0008/02/04/) 或穷举旋转的最小体积法。

### 4.3 OBB–OBB 相交（SAT，15 轴）

详见下一节。

------

## 5. k-DOP

k-DOP (k-Discrete Oriented Polytope) 是 AABB 的推广：选定 $k/2$ 对预定义方向 $\mathbf{n}_i$，对每对存一段投影区间 $[\min_i, \max_i]$。物体被 $k$ 个平行平面对夹住。

- 6-DOP 就是 AABB（坐标轴方向）。
- 14-DOP：6 轴方向 + 8 个体对角线方向。
- 18-DOP：6 轴 + 12 棱方向。
- 26-DOP：6 + 8 + 12。

优点：比 AABB 紧（尤其对斜面物体），构造仍 $O(n)$。 缺点：相交测试要查 $k/2$ 个轴。 应用：早期的实时碰撞库（如 V-COLLIDE）、毛发/布料模拟。

现代游戏引擎里 k-DOP 用得不算多，因为 AABB 配合 BVH 已经足够好。

------

## 6. 统一相交框架：分离轴定理 (SAT)

### 6.1 定理叙述

> **分离轴定理**：两个**凸**多面体 $A, B$ 不相交，**当且仅当**存在一条直线 $L$，使两者在 $L$ 上的投影区间不相交。

这条直线的方向向量称为**分离轴 (separating axis)**。

### 6.2 哪些轴需要测试

对于 3D 凸多面体，**理论上**要遍历所有方向——但有定理保证：**只需检查面法线和棱叉积方向**。

具体到 OBB–OBB（两个 OBB 各 3 个面法线 = 3 条轴；棱方向也是 3 条；面对面共 $3+3=6$ 个面轴；棱对棱共 $3\times 3 = 9$ 个叉积轴）：共需 **15 条候选轴**。

对 AABB–AABB，三对面法线都是世界坐标轴，棱方向也是世界坐标轴，叉积要么是零要么共线 ⇒ 只需 **3 条轴**——和 §2.4 的"逐分量比较"等价。

### 6.3 投影半径公式

对一条单位轴 $\mathbf{L}$，OBB 在其上投影的半长（半径）：

$$ r = \sum_{i=0}^{2} e_i \cdot |\mathbf{u}_i \cdot \mathbf{L}|. $$

**推导**：OBB 上的点 $\mathbf{c} + \sum_i \alpha_i \mathbf{u}_i$ 投到 $\mathbf{L}$ 上的偏移为 $\sum_i \alpha_i (\mathbf{u}_i\cdot\mathbf{L})$，$|\alpha_i|\le e_i$，三角不等式给出最大幅度。

AABB 是 OBB 的特例（$\mathbf{u}_i$ 是世界坐标轴），所以

$$ r_{\text{AABB}} = \sum_i e_i |L_i|. $$

### 6.4 OBB–OBB SAT

```cpp
bool OverlapOBB(const OBB& a, const OBB& b) {
    // Bullet/RTCD 风格实现
    glm::mat3 R, AbsR;
    // R: b 各轴在 a 坐标系中的表示
    for (int i=0;i<3;++i)
        for (int j=0;j<3;++j)
            R[i][j] = glm::dot(a.u[i], b.u[j]);

    glm::vec3 t = b.c - a.c;
    t = glm::vec3(glm::dot(t, a.u[0]),
                  glm::dot(t, a.u[1]),
                  glm::dot(t, a.u[2]));  // t 转到 a 坐标系

    // 加微小 epsilon 防止两 OBB 的棱平行时叉积接近 0
    const float EPS = 1e-6f;
    for (int i=0;i<3;++i)
        for (int j=0;j<3;++j)
            AbsR[i][j] = std::fabs(R[i][j]) + EPS;

    // 测试轴 L = a.u[i]
    for (int i=0;i<3;++i) {
        float ra = a.e[i];
        float rb = b.e[0]*AbsR[i][0] + b.e[1]*AbsR[i][1] + b.e[2]*AbsR[i][2];
        if (std::fabs(t[i]) > ra + rb) return false;
    }
    // 测试轴 L = b.u[j]
    for (int j=0;j<3;++j) {
        float ra = a.e[0]*AbsR[0][j] + a.e[1]*AbsR[1][j] + a.e[2]*AbsR[2][j];
        float rb = b.e[j];
        float tj = t[0]*R[0][j] + t[1]*R[1][j] + t[2]*R[2][j];
        if (std::fabs(tj) > ra + rb) return false;
    }
    // 测试轴 L = a.u[i] x b.u[j]，共 9 条
    // 由于 L 不是单位向量，公式两边同乘 |L|，无影响（只比较大小关系）
    // (具体 9 条展开略，可见 Ericson, Real-Time Collision Detection §4.4)
    // ...
    return true;
}
```

**SAT 的早退 (early-out)**：一旦找到一条分离轴就返回 `false`，越早越好。实际数据中大多数 OBB 对在前几条轴就被分开了，平均开销远小于 15 轴。

------

## 7. Ray–AABB：Slab 方法

### 7.1 问题

光线 $\mathbf{P}(t) = \mathbf{O} + t\mathbf{D}$，$t \ge 0$。AABB 用 min/max 表示。求是否相交，以及最小相交 $t$。

### 7.2 推导

把 AABB 看成 **3 对平行平面（slab）的交**：

$$ B = \bigcap_{i=0}^{2} {\mathbf{x}: m_i \le x_i \le M_i}. $$

对每对 slab，光线进入 / 离开的参数：

$$ t_{i,\text{near}} = \frac{m_i - O_i}{D_i}, \qquad t_{i,\text{far}} = \frac{M_i - O_i}{D_i}. $$

若 $D_i < 0$，要交换 near/far。

光线"同时"在三对 slab 内，意味着

$$ t_{\text{enter}} = \max_i t_{i,\text{near}}, \qquad t_{\text{exit}} = \min_i t_{i,\text{far}}. $$

**相交条件**：$t_{\text{enter}} \le t_{\text{exit}}$ 且 $t_{\text{exit}} \ge 0$。

### 7.3 处理 $D_i = 0$

按公式直接给出 $\pm\infty$。IEEE 754 浮点天然支持：`1.0f / 0.0f = +inf`，`-1.0f / 0.0f = -inf`，后续 `max/min` 对 $\pm\infty$ 行为正确——所以**不要写 if 判断**，让浮点替你工作。

唯一要警惕的角点：光线起点正好在 slab 平面上**且** $D_i=0$，得到 `0/0 = NaN`，比较会全 false。生产代码常用 `tmin = std::max(tmin, -inf)` 与 NaN-safe 的 `min/max`，或直接用 Williams 等的"slab 改进版"。

### 7.4 实现

```cpp
// 返回是否相交；交点 t 写入 *tHit（取 tEnter，若 tEnter<0 则取 tExit，即射线起点在盒内）
bool IntersectRayAABB(const glm::vec3& O, const glm::vec3& D,
                      const AABB& b, float tMax, float* tHit)
{
    glm::vec3 invD = 1.0f / D;                        // 含 ±inf
    glm::vec3 t0 = (b.mn - O) * invD;
    glm::vec3 t1 = (b.mx - O) * invD;
    glm::vec3 tNear = glm::min(t0, t1);
    glm::vec3 tFar  = glm::max(t0, t1);

    float tEnter = glm::compMax(tNear);               // max of 3 components
    float tExit  = glm::compMin(tFar);

    if (tEnter > tExit || tExit < 0.0f || tEnter > tMax)
        return false;
    *tHit = (tEnter < 0.0f) ? tExit : tEnter;
    return true;
}
```

在 GPU 上（GLSL）此函数是 BVH 遍历核心，几乎每个 ray-tracer kernel 都长这样。

------

## 8. 应用一：视锥剔除 (Frustum Culling)

### 8.1 视锥的平面表示

视锥是 6 个半空间（near、far、left、right、bottom、top）的交集。每个半空间由平面

$$ \pi: \mathbf{n}\cdot\mathbf{x} + d = 0, \quad \mathbf{n}\cdot\mathbf{x} + d \ge 0 \text{ 为"内侧"} $$

定义（内法线指向视锥内部）。

### 8.2 从 VP 矩阵提取平面（**经典技巧**）

设 $M = P\cdot V$ 是 view-projection 矩阵，$\mathbf{x}_h = (\mathbf{x}, 1)$ 为齐次坐标。变换后的裁剪空间点 $\mathbf{x}_c = M\mathbf{x}_h$。

**裁剪空间**里视锥就是 $-w_c \le x_c, y_c, z_c \le w_c$（OpenGL；DirectX/Vulkan 的 z 是 $0 \le z_c \le w_c$）。

把每一条不等式拉回世界空间：例如 $w_c + x_c \ge 0$，

$$ w_c + x_c = M_{4*}\mathbf{x}*h + M*{1*}\mathbf{x}*h = (M*{1*} + M_{4*})\cdot \mathbf{x}_h \ge 0 $$

（$M_{i*}$ 表 $M$ 的第 $i$ 行）。这正是世界空间一个平面的方程，平面参数 $(\mathbf{n}, d) = M_{i*} + M_{4*}$ 的前三个分量 / 第四个分量。

**OpenGL（z ∈ [-1,1]）的六平面**：

| 平面   | 系数 (a,b,c,d)    |
| ------ | ----------------- |
| Left   | $M_{4*} + M_{1*}$ |
| Right  | $M_{4*} - M_{1*}$ |
| Bottom | $M_{4*} + M_{2*}$ |
| Top    | $M_{4*} - M_{2*}$ |
| Near   | $M_{4*} + M_{3*}$ |
| Far    | $M_{4*} - M_{3*}$ |

**DirectX/Vulkan（z ∈ [0,1]）的 near**：$M_{3*}$（其他相同）。

每个平面除以 $|\mathbf{n}|$ 归一化，便于后面计算"有符号距离"。

```cpp
struct Plane { glm::vec3 n; float d; }; // n·x + d = 0
struct Frustum { Plane p[6]; };

Frustum ExtractFrustumGL(const glm::mat4& M) {
    // GLM 是列主序，M[col][row]
    Frustum F;
    auto row = [&](int i){
        return glm::vec4(M[0][i], M[1][i], M[2][i], M[3][i]);
    };
    glm::vec4 r1=row(0), r2=row(1), r3=row(2), r4=row(3);

    glm::vec4 planes[6] = {
        r4 + r1,  // Left
        r4 - r1,  // Right
        r4 + r2,  // Bottom
        r4 - r2,  // Top
        r4 + r3,  // Near (GL)
        r4 - r3   // Far
    };
    for (int i=0;i<6;++i) {
        glm::vec3 n(planes[i]);
        float len = glm::length(n);
        F.p[i] = { n / len, planes[i].w / len };
    }
    return F;
}
```

### 8.3 AABB vs Plane 测试（**核心**）

给定平面 $\pi: \mathbf{n}\cdot\mathbf{x} + d = 0$ 和 AABB（center $\mathbf{c}$, extents $\mathbf{e}$）。

中心到平面的有符号距离：

$$ s = \mathbf{n}\cdot\mathbf{c} + d. $$

AABB 在 $\mathbf{n}$ 上的**投影半径**（同 §6.3 的公式，应用到 AABB）：

$$ r = \sum_i e_i |n_i| = |\mathbf{n}|\cdot \mathbf{e} \text{（按分量取绝对值后点乘）}. $$

三种情况：

| 关系       | 判定         |
| ---------- | ------------ |
| 完全在内侧 | $s \ge r$    |
| 完全在外侧 | $s \le -r$   |
| 跨平面     | $-r < s < r$ |

### 8.4 视锥 vs AABB

对 6 个平面**逐个测试**：

- 若 AABB 完全在某平面外侧 ⇒ **保证**不可见，剔除。
- 否则保守地通过（可能"角落擦过"也算可见，不要紧——保守即可）。

```cpp
enum class Visibility { Out, In, Intersect };

Visibility TestAABB(const Frustum& F, const AABB& b) {
    glm::vec3 c = b.Center(), e = b.Extents();
    bool intersect = false;
    for (int i = 0; i < 6; ++i) {
        const Plane& p = F.p[i];
        float s = glm::dot(p.n, c) + p.d;
        float r = glm::dot(glm::abs(p.n), e);
        if (s < -r) return Visibility::Out;   // 完全外侧
        if (s <  r) intersect = true;          // 跨该平面
    }
    return intersect ? Visibility::Intersect : Visibility::In;
}
```

### 8.5 进阶优化：p-vertex / n-vertex

对每个平面，AABB 八个角中**朝向平面内法线最远**的那个角叫 **p-vertex (positive)**，最远向外的叫 **n-vertex (negative)**。

- 若 **n-vertex 都在内侧** ⇒ AABB 完全可见；
- 若 **p-vertex 在外侧** ⇒ AABB 完全不可见。

只需测 1~2 个角，比测 8 个角节省 75%。p/n 顶点由平面法线的符号位选出：

```cpp
// 给定平面 p（法线 n）, AABB (mn, mx)
// p-vertex: 沿 n 方向最深的角
glm::vec3 P(
    p.n.x >= 0 ? b.mx.x : b.mn.x,
    p.n.y >= 0 ? b.mx.y : b.mn.y,
    p.n.z >= 0 ? b.mx.z : b.mn.z);
// n-vertex 反之
glm::vec3 N(
    p.n.x >= 0 ? b.mn.x : b.mx.x,
    p.n.y >= 0 ? b.mn.y : b.mx.y,
    p.n.z >= 0 ? b.mn.z : b.mx.z);

if (glm::dot(p.n, P) + p.d < 0) /* 完全外侧 */;
if (glm::dot(p.n, N) + p.d > 0) /* 完全内侧（对此平面）*/;
```

这套技巧在 CPU 端可以加速 2–3 倍；GPU 端因为不爱分支，常常还是用 §8.4 的对称形式。

### 8.6 引擎里的实际流水线

```
CPU: 每帧
  1. 提取视锥 6 个平面
  2. 遍历场景树（BVH/Octree），对每个节点的 AABB 做剔除
  3. 通过的物体进入 draw list
GPU (现代 GPU-driven 渲染): 上述步骤在 compute shader 中完成
```

------

## 9. 应用二：遮挡剔除 (Occlusion Culling)

视锥剔除剔的是"看不到的"，遮挡剔除剔的是"被挡住的"。后者贵得多，所以引擎里两者结合：先视锥再遮挡。

工业界三大流派：

1. **CPU 软光栅 occluder**（如 Unreal 的 SoftwareOcclusion、Frostbite 的"Masked Software Occlusion Culling"）
2. **GPU 硬件 Occlusion Queries**（OpenGL `GL_SAMPLES_PASSED` / D3D `Occlusion Query`），现已少用
3. **Hi-Z (Hierarchical-Z) Buffer Occlusion Culling**（现代主流）

我们重点讲 Hi-Z，因为它和 bounding box 配合得最直接。

### 9.1 硬件遮挡查询（速览）

**思路**：把候选物体的 bounding box 渲染一次，关掉颜色 / 深度写入，只查询"有多少 fragment 通过了 depth test"。0 ⇒ 完全遮挡。

**致命缺点**：CPU 必须等 GPU 返回查询结果（stall），通常延迟 1–2 帧 ⇒ 引入 lag、闪烁。Hi-Z 出现后基本退役。

### 9.2 Hi-Z Buffer Occlusion Culling（**现代主流**）

#### 9.2.1 原理

我们已经渲染了**部分场景**（例如最近的、最大的几个物体作为 occluder，或上一帧的深度），得到一张 depth buffer。

构造 **depth pyramid (Hi-Z)**：对 depth buffer 做 mipmap，但每一级不是平均，而是**最大值**（反向 z / 深度越大越远的约定下）：

$$ D_{l+1}(x, y) = \max\Bigl(D_l(2x, 2y),\ D_l(2x{+}1, 2y),\ D_l(2x, 2y{+}1),\ D_l(2x{+}1, 2y{+}1)\Bigr). $$

这样 mip $l$ 的每个 texel 存储了对应 $2^l \times 2^l$ 屏幕区域内**最远**的深度。

#### 9.2.2 用 Hi-Z 测试 AABB

**步骤**：

1. 把物体的世界空间 AABB 投影到屏幕空间，得到 **屏幕空间 AABB** $(s_{min}, s_{max})$ 和**最近深度** $z_{\min}$。
2. 计算该屏幕 AABB 的像素宽高 $w, h$。
3. 选 mip level $l = \lceil \log_2(\max(w, h)) \rceil$。在此 mip 上，屏幕 AABB 最多覆盖 $2\times 2$ 个 texel。
4. 取这 $2\times 2$ 个 texel 中的 **最大** 深度 $d^*$（即"该屏幕区域中目前已知最远的深度"）。
5. 若 $z_{\min} > d^*$ ⇒ 物体所有像素都在已有像素**之后**（更远），被**完全遮挡**，剔除。

**保守性**：mip 取 max 保证 $d^*$ 不会比真实情况近，因此判定为 occluded 一定是真 occluded（无 false negative）。✓

```glsl
// GLSL: compute shader 形式的 Hi-Z 遮挡剔除（核心思想）
// 假设 Hi-Z 已经构造好，绑定为 sampler2D hizMap;

layout(binding=0) uniform sampler2D hizMap;
uniform mat4 uViewProj;
uniform vec2 uHiZSize;       // mip 0 的分辨率

bool OccludedByHiZ(vec3 aabbMin, vec3 aabbMax) {
    // 1. 投影 8 个角到 NDC
    vec3 corners[8];
    corners[0] = vec3(aabbMin.x, aabbMin.y, aabbMin.z);
    corners[1] = vec3(aabbMax.x, aabbMin.y, aabbMin.z);
    corners[2] = vec3(aabbMin.x, aabbMax.y, aabbMin.z);
    corners[3] = vec3(aabbMax.x, aabbMax.y, aabbMin.z);
    corners[4] = vec3(aabbMin.x, aabbMin.y, aabbMax.z);
    corners[5] = vec3(aabbMax.x, aabbMin.y, aabbMax.z);
    corners[6] = vec3(aabbMin.x, aabbMax.y, aabbMax.z);
    corners[7] = vec3(aabbMax.x, aabbMax.y, aabbMax.z);

    vec3 ndcMin = vec3( 1e9);
    vec3 ndcMax = vec3(-1e9);
    for (int i = 0; i < 8; ++i) {
        vec4 clip = uViewProj * vec4(corners[i], 1.0);
        if (clip.w <= 0.0) return false;       // 横跨相机，保守不剔
        vec3 ndc = clip.xyz / clip.w;
        ndcMin = min(ndcMin, ndc);
        ndcMax = max(ndcMax, ndc);
    }

    // 2. NDC -> 屏幕 UV
    vec2 uvMin = ndcMin.xy * 0.5 + 0.5;
    vec2 uvMax = ndcMax.xy * 0.5 + 0.5;
    float zMin = ndcMin.z;                     // 物体最近深度（depth-test 通过的最浅）

    // 3. 选 mip level
    vec2 size  = (uvMax - uvMin) * uHiZSize;   // 屏幕像素覆盖
    float mip  = ceil(log2(max(size.x, size.y)));

    // 4. 在该 mip 上采样 4 个角，取 max
    float d00 = textureLod(hizMap, vec2(uvMin.x, uvMin.y), mip).r;
    float d10 = textureLod(hizMap, vec2(uvMax.x, uvMin.y), mip).r;
    float d01 = textureLod(hizMap, vec2(uvMin.x, uvMax.y), mip).r;
    float d11 = textureLod(hizMap, vec2(uvMax.x, uvMax.y), mip).r;
    float dMax = max(max(d00, d10), max(d01, d11));

    // 5. 比较（注意深度约定：这里假设标准 GL，深度越大越远）
    return zMin > dMax;
}
```

#### 9.2.3 完整 GPU-Driven 流水线

现代引擎（Unreal Nanite、idTech7、Frostbite、Unity HDRP 等）大致这样组织：

```
[Frame N]

  ┌─ Frame N-1 的 depth buffer 或当前帧的 early-Z pass ─┐
                            │
                            ▼
              GPU: 构造 Hi-Z pyramid (mipmap with max-reduce)
                            │
                            ▼
       GPU compute: 对所有 instance 做 视锥剔除 + Hi-Z 剔除
              输出 visible instance list (indirect draw args)
                            │
                            ▼
                GPU: glMultiDrawIndirect / vkCmdDrawIndirect
```

整条链路 **CPU 0 介入**，对几十万 instance 也能稳跑。

#### 9.2.4 关键工程细节

- **跨视锥的物体**：AABB 部分在相机后方，齐次坐标 $w \le 0$，**不要**做 perspective divide（结果错误），保守地不剔。
- **occluder 选择**：理想的 occluder 是大且近的物体。两种主流方案：
  - **Two-pass**：先画一些保险物体（大房子、地形），构造 Hi-Z，再剔其余。
  - **Temporal**：用上一帧最终 depth 重投影做 Hi-Z（要处理相机移动 → 引入 disocclusion 误差，但通常可接受）。
- **HZB 与 Reversed-Z**：reversed-z 下"近 = 1，远 = 0"，max-reduce 要改成 min-reduce，比较方向反转。
- **mip 选择**：上面公式选 mip 使屏幕 AABB ≤ 2×2 texel；这是经典 4-tap 版本。也有 1-tap 版本（选择更高 mip 直到 1 texel 覆盖），更省但更不紧。

------

## 10. 应用三：BVH 与光线追踪

### 10.1 BVH (Bounding Volume Hierarchy)

把场景中所有物体的 AABB 按二叉树组织：每个内部节点的 AABB 包住其所有后代。这样可以在 $O(\log n)$ 期望复杂度内做光线 / 范围查询：

```
Ray r:
  stack ← { root }
  while stack not empty:
    node ← pop
    if not Intersect(r, node.aabb): continue   // §7 的 Slab 测试
    if node is leaf:
      Intersect(r, primitives in node)
    else:
      push children
```

### 10.2 构造启发式：SAH（Surface Area Heuristic）

构造 BVH 时如何决定划分？SAH 给每个候选划分打分：

$$ \mathrm{Cost}(\text{split}) = C_t + \frac{A_L}{A_P},N_L,C_i + \frac{A_R}{A_P},N_R,C_i $$

其中 $A_P, A_L, A_R$ 是父节点 / 左 / 右子节点 AABB 的**表面积**，$N_L, N_R$ 是分到两侧的图元数，$C_t$ 是遍历常数（≈ 1），$C_i$ 是图元相交测试常数（≈ 1–2）。

直觉：表面积越大，光线击中此 AABB 的概率越高（这是几何概率论里"凸体面积 ∝ 随机直线击中概率"的结论）。SAH 让 BVH 在期望意义上最优。

### 10.3 GPU 光线追踪

NVIDIA RTX / DXR / Vulkan Ray Tracing 在硬件层加速：

- **BLAS (Bottom-Level Acceleration Structure)**：每个 mesh 的 BVH，叶子是三角形。
- **TLAS (Top-Level Acceleration Structure)**：所有 instance 的 BVH，叶子是对 BLAS 的引用 + transform。

底层全部是 **AABB + Ray Slab Test**。

------

## 11. 工程实践与常见陷阱

### 11.1 浮点精度

- AABB 在被反复 `transform` 后会单调膨胀（§2.5）。**每隔一段时间或大变换后重算**。
- Ray-AABB 用 `invD` 而不是 `1/D` 复用（每条光线一次除法）；BVH 遍历时把 `invD` 算一次就够。

### 11.2 边界条件

- 退化 AABB（一维为 0：纸片、墙）：合法，但要小心 `extents=0` 导致投影半径为 0 在 SAT 中被认为"分离"——其实是对的，但可能误剔薄物体。
- 空 AABB：用 `min = +inf, max = -inf` 表示"空"，合并操作天然处理（合并空和非空得到非空）。

### 11.3 数据布局（SoA vs AoS）

剔除是典型 SIMD-friendly 任务。**结构体数组 (AoS)** `struct { vec3 mn, mx; } box[N]` 不利于向量化；改成

```cpp
struct AABBSoA {
    std::vector<float> mn_x, mn_y, mn_z;
    std::vector<float> mx_x, mx_y, mx_z;
};
```

可以一次 SIMD 处理 4 / 8 个 box。AVX2 下视锥剔除有数倍加速。Frostbite 早期的论文（[Culling the Battlefield](https://www.ea.com/frostbite/news/culling-the-battlefield-data-oriented-design-in-practice)）就是这种思路。

### 11.4 选择哪种 Bounding Box

经验法则：

- **不知道选啥** ⇒ AABB。
- **物体是球形或近球形（角色、粒子、子弹）** ⇒ Sphere（注意它在旋转下不变，构造一次终身有效）。
- **细长 / 倾斜 / 旋转频繁** ⇒ OBB（但只在局部空间存一份，世界空间用 AABB 包 OBB 也常见）。
- **极致紧密、跨平台少改动** ⇒ k-DOP（在某些骨骼动画 / 布料场景）。

### 11.5 静态 vs 动态物体

- **静态**：离线构造紧致 AABB / OBB；BVH 一次建好。
- **动态**（蒙皮、变形）：每帧重算容易爆 CPU。常见折衷：
  - 用"骨骼包围球的并集"近似（保守、稳定）。
  - 用"绑定姿态下的 AABB"按全局矩阵 Arvo-变换（不紧但便宜）。
  - "Refit"：仅更新 BVH 中已有 AABB 的尺寸，不重建树形（[Lauterbach et al.]）。

### 11.6 不要重复造轮子

工业级实现可以直接读 / 参考：

- [DirectXMath](https://github.com/microsoft/DirectXMath): `BoundingBox`, `BoundingOrientedBox`, `BoundingFrustum`, `BoundingSphere`。
- [Bullet Physics](https://github.com/bulletphysics/bullet3) 的 `btAabbUtil2`、`btDbvt`。
- [meshoptimizer](https://github.com/zeux/meshoptimizer) 的 cluster bounding。
- [embree](https://github.com/RenderKit/embree)、[OptiX](https://developer.nvidia.com/optix) 的 BVH 实现。

经典读物：**Christer Ericson, \*Real-Time Collision Detection\*** —— 这本书前 5 章就把本文 §2–§7 讲得清清楚楚，是图形 / 物理工程师案头必备。

------

## 附：术语速查表

| 缩写  | 全称                                | 出现章节 |
| ----- | ----------------------------------- | -------- |
| AABB  | Axis-Aligned Bounding Box           | §2       |
| OBB   | Oriented Bounding Box               | §4       |
| MEB   | Minimum Enclosing Ball              | §3       |
| k-DOP | k-Discrete Oriented Polytope        | §5       |
| SAT   | Separating Axis Theorem             | §6       |
| BVH   | Bounding Volume Hierarchy           | §10      |
| Hi-Z  | Hierarchical-Z (depth pyramid)      | §9.2     |
| SAH   | Surface Area Heuristic              | §10.2    |
| HZB   | Hi-Z Buffer                         | §9.2     |
| TLAS  | Top-Level Acceleration Structure    | §10.3    |
| BLAS  | Bottom-Level Acceleration Structure | §10.3    |

------

**写在最后**：bounding box 看起来简单，但真正把它从"构造"用到"GPU 剔除"，会牵涉数值精度、变换连贯性、SIMD/GPU 数据布局、保守性证明等大量细节。建议你写一遍小 demo：

1. 加载 mesh，算 AABB（§2）。
2. 实现视锥剔除（§8），相机移动时观察通过率。
3. 实现 Hi-Z occlusion（§9.2），先用 CPU 渲染深度再上传 GPU；之后改成全 compute。

走完这三步，你对 bounding box 在引擎里的位置就有了"肌肉记忆"。