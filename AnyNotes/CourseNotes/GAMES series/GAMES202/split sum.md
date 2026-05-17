### 重要性采样和 split-sum 是两件事

**重要性采样（IS）本身只是 Monte Carlo 的方差缩减技术**，它和 split-sum 没有任何关系。在没有 split-sum 的 ground truth 渲染里你也会用 IS：
$$
L_o(\mathbf{v}) \approx \frac{1}{N}\sum_k \frac{L_i(\mathbf{l}_k)\, f_r(\mathbf{l}_k,\mathbf{v})(\mathbf{n}\cdot\mathbf{l}_k)}{p(\mathbf{l}_k)}
$$
这里 $\mathbf{l}_k$ 从某个 PDF $p$ 抽样（通常用 GGX NDF），分母上的 $p(\mathbf{l}_k)$ 做权重补偿，保证估计无偏。这一步**本身没有任何"模糊"**——它只是高方差的离线计算，要几百上千 spp 才能收敛。

所以你说"如果不用 split-sum，整个半球采样本来就是重要性采样"——对的。IS 是底层方法，与是否拆分无关。

### Split-sum 出现的真正动机

问题不是"采样"，是**预计算**。实时渲染的诉求是：能不能把这个昂贵的 MC 估计**提前算好、存起来、runtime 直接查**。

直接预计算困难在于积分依赖太多参数：$L_i $（环境）、 $\mathbf{n} $、$\mathbf{v} $、$\alpha $、$F_0$ 全部耦合在一起。一张表存不下。

Split-sum 的作用是**把这个耦合积分近似拆成两个独立积分的乘积**：
$$
\underbrace{\frac{1}{N}\sum L_i \cdot \frac{1}{N}\sum \frac{f_r(\mathbf{n}\cdot\mathbf{l})}{p}}_{\text{两个独立平均的乘积}}
$$
拆完之后，第一项只依赖 $L_i$ 和采样分布（即依赖 $\mathbf{r}$ 和 $\alpha$），可以预计算成 mipmapped cubemap；第二项只依赖 BRDF 参数，可以预计算成 2D LUT。**这才是 split-sum 的全部目的：让两半都可预计算。**

### "模糊"是什么

现在回到你最关心的问题：模糊从哪儿来？

第一项 $\frac{1}{N}\sum_k L_i(\mathbf{l}_k)$ 写成积分形式：
$$
\text{PreFilter} = \frac{\int L_i(\mathbf{l})\, D(\mathbf{l})(\mathbf{n}\cdot\mathbf{l})\, d\mathbf{l}}{\int D(\mathbf{l})(\mathbf{n}\cdot\mathbf{l})\, d\mathbf{l}}
$$
这就是一个**带权重的加权平均**——也就是用 $D \cdot \cos$ 作为 kernel 对环境光做卷积。从信号处理角度看，加权平均就是低通滤波，所以视觉上呈现为"模糊"。

但是！这个"模糊"**不是 split-sum 凭空创造出来的**。它本来就以另一种形式存在于原始积分里——只是原本它和 BRDF、和具体 shading point 的 $\mathbf{v}$ 一起耦合着，每次 shading 都得现场算。Split-sum 的功劳是把这个加权平均**从 runtime 解耦出来**，使它只依赖 $(\mathbf{r}, \alpha)$ 这两个参数，于是可以预计算。

换句话说：

- **重要性采样** → 决定了用哪些方向（按 GGX lobe 集中在 $\mathbf{r}$ 周围）。
- **Split-sum** → 允许这些样本的光照部分单独平均，从而把"加权平均"提到积分外面，形成可预计算的卷积。
- **模糊（卷积）** → 是"加权平均"的视觉表现，是 split-sum 让它显式化、可预存的结果。

所以"这个模糊是 split-sum 造成的数学结果"——更准确地说：模糊一直都隐含在 BRDF 的 lobe 结构里，split-sum 把它**显式拆出来**变成了一张可查的表。

### 一个对照可能更清楚

不用 split-sum，runtime 渲染流程是：

> 对当前 shading point，按 GGX 重要性采样 N 个方向 → 对每个方向去 cubemap 采 $L_i$、算 $f_r$、加权求和。

用 split-sum，runtime 渲染流程是：

> 对当前 shading point，算 $\mathbf{r}$ 和 $\alpha$ → 在 pre-filtered cubemap 上按 $\mathbf{r}$ 采一次（mip 由 $\alpha$ 决定）→ 在 BRDF LUT 上按 $(\cos\theta_v, \alpha)$ 采一次 → 两者相乘。

预计算把"几百次采样 + 加权"压缩到了"两次纹理读取 + 一次乘法"。模糊化的 cubemap 就是那"几百次加权平均"提前做好的产物。

### 回到你的原话校准一下

> "前一项，通过模糊就可以预计算"

更精确：**前一项本身就是一个加权平均（卷积），它的预计算过程就是离线对 cubemap 做这个卷积**。"模糊"是这个卷积的别名，不是预计算的"手段"，而是预计算的"内容"。

> "重要性采样到底是在哪一步应用的"

两个地方都用：

1. 离线生成 pre-filtered cubemap 时，用 GGX IS 去估计上面那个卷积积分（因为这个积分本身也得 MC 算）。
2. 如果你做 ground truth 不拆分，runtime 也用 IS。

> "这个模糊是 split-sum 造成的数学结果？"

模糊（=带权重的方向平均）原本就在积分里。Split-sum 是把它从耦合的大积分里**分离出来、显式化**，使其可以脱离 runtime 参数被预计算成一张表。可以说"模糊作为一张可查的表"是 split-sum 的产物，但"模糊"这个现象本身是 BRDF lobe 加权的自然结果。