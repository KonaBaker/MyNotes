cascade就是多层级的L(FFT的patch大小)。

### 一、单个 FFT patch 的波数集合

设 FFT 网格分辨率为 $N \times N $，patch 在世界空间中的边长为 $L $（即 length_scale）。把 patch 离散化为 $N \times N $ 个采样点：
$$
\mathbf{x}_{p,q} = \left( \frac{p L}{N},\ \frac{q L}{N} \right), \qquad p, q \in \{0, 1, \dots, N-1\}
$$
相邻采样点的空间间距为：
$$
\Delta x = \frac{L}{N}
$$
为了让 IFFT 得到的高度场在世界空间中以 $L $ 为周期平铺，波矢必须满足周期边界条件 $e^{i\mathbf{k} \cdot \mathbf{x}} = e^{i\mathbf{k} \cdot (\mathbf{x} + L\hat{\mathbf{e}})} $，即 $\mathbf{k} \cdot \hat{\mathbf{e}} \cdot L = 2\pi m $。这给出离散波矢：
$$
\mathbf{k}_{n,m} = \left( \frac{2\pi n}{L},\ \frac{2\pi m}{L} \right), \qquad n, m \in \left\{ -\frac{N}{2},\ -\frac{N}{2}+1,\ \dots,\ \frac{N}{2}-1 \right\}
$$
**频域分辨率**（相邻波数的间距）：
$$
\Delta k = \frac{2\pi}{L}
$$

### 二、最大最小波长的严格界

#### 2.1 最大波长（最低频）

最长可表示的波出现在最小非零 $|\mathbf{k}| $ 处。最小的非零波数模长是 $\Delta k $ 本身，对应：
$$
\lambda_{\max} = \frac{2\pi}{k_{\min}} = \frac{2\pi}{\Delta k} = L
$$
所以 **patch 边长就是最大可表示波长**。这是周期性边界条件的直接后果——比 $L $ 还长的波装不进周期为 $L $ 的盒子里。

#### 2.2 最小波长（Nyquist 上限）

按 Nyquist–Shannon 采样定理，要在间距为 $\Delta x $ 的网格上无歧义地表示波长 $\lambda $ 的正弦波，必须满足 $\Delta x \le \lambda / 2 $。代入 $\Delta x = L/N $：
$$
\lambda_{\min}^{\text{Nyquist}} = 2 \Delta x = \frac{2L}{N}
$$
对应最大波数：
$$
k_{\max}^{\text{Nyquist}} = \frac{2\pi}{\lambda_{\min}^{\text{Nyquist}}} = \frac{\pi N}{L}
$$

#### 2.3 各向异性的修正

上面假设波沿轴向。对一般方向 $\mathbf{k} = (k_x, k_y) $，波数模长为 $k = \sqrt{k_x^2 + k_y^2} $。在 $N \times N $ 离散波矢方阵的角点 $(n, m) = (\pm N/2, \pm N/2) $ 处取得最大模长：
$$
k_{\max}^{\text{diag}} = \sqrt{\left(\frac{\pi N}{L}\right)^2 + \left(\frac{\pi N}{L}\right)^2} = \frac{\pi N \sqrt{2}}{L}
$$
但仍以轴向 Nyquist $\pi N / L $ 作为安全界限——超过这个值的对角分量虽然存在，但容易出现采样伪影，工程实现里通常按轴向处理。

### 三、级联划分的频带覆盖问题

#### 3.1 单 patch 的可用频带

对于 cascade $i $，其能表示的波数集合是：
$$
\mathcal{K}_i = \left\{ \mathbf{k} : k_{\min}^{(i)} \le |\mathbf{k}| \le k_{\max}^{(i)} \right\}, \qquad k_{\min}^{(i)} = \frac{2\pi}{L_i},\quad k_{\max}^{(i)} = \frac{\pi N}{L_i}
$$
**关键观察**：单个 cascade 的频带跨度（用波数比表示）是固定的：
$$
\frac{k_{\max}^{(i)}}{k_{\min}^{(i)}} = \frac{\pi N / L_i}{2\pi / L_i} = \frac{N}{2}
$$
也就是说，一个 cascade 不论怎么选 $L_i $，它在对数频率轴上覆盖的"宽度"恒为 $\log_2(N/2) $ 个倍频程。对 $N = 256 $，是 7 个倍频程。

#### 3.2 工程上的安全余量

理论 Nyquist $k_{\max} = \pi N/L $ 只是数学下界，实际渲染中需要两层余量：

**最高频端**（避免 aliasing）：取一个安全因子 $\alpha > 2 $（代替 Nyquist 的 2），定义实际最大可用波数
$$
k_{\text{cut}}^{(i)} = \frac{2\pi}{\alpha \cdot \Delta x_i} = \frac{2\pi N}{\alpha L_i}
$$
对应"最短可用波长" $\lambda_{\text{cut}}^{(i)} = \alpha L_i / N $。代码中 $\alpha = $ `smallest_wave_multiplier_auto = 4`。

**最低频端**（避免离散波数太稀疏导致明显 tiling）：要求 cascade 至少容纳 $\beta $ 个最小波数采样，定义实际最小可用波数
$$
k_{\text{floor}}^{(i)} = \beta \cdot \Delta k_i = \frac{2\pi \beta}{L_i}
$$
对应"最长被用波长" $\lambda_{\text{floor}}^{(i)} = L_i / \beta $。代码中 $\beta = $ `min_waves_cascade_auto = 6`。

注释掉的 cutoff 代码就是这一层：

cpp

```cpp
boundary_i = 2π / L[i] * 6.0f  =  k_floor^(i)
```

### 四、级联递推公式的严格推导

#### 4.1 频带无缝拼接条件

要求相邻 cascade 频带"端对端"对接：cascade $i $ 的高频截止 = cascade $i+1 $ 的低频起点。
$$
k_{\text{cut}}^{(i)} = k_{\text{floor}}^{(i+1)}
$$
代入：
$$
\frac{2\pi N}{\alpha L_i} = \frac{2\pi \beta}{L_{i+1}}
$$
整理得到：
$$
\boxed{ L_{i+1} = \frac{\alpha \beta}{N} \cdot L_i }
$$
代入 $\alpha = 4 $, $\beta = 6 $, $N = 256 $：
$$
L_{i+1} = \frac{24}{256} L_i = \frac{3}{32} L_i \approx 0.09375 \cdot L_i
$$
这正是代码里的递推。每级缩小因子 $r = \alpha\beta/N $。

#### 4.2 等价的对数尺度形式

取对数：
$$
\log L_{i+1} = \log L_i + \log\left(\frac{\alpha\beta}{N}\right)
$$
每级在对数尺度上前进 $|\log_2(N/(\alpha\beta))| $ 个倍频程。代入数值：$\log_2(256/24) \approx 3.42 $ 个倍频程。

而单个 cascade 覆盖 $\log_2(N/(\alpha\beta)) \approx 3.42 $ 倍频程的有用频带（从 $k_{\text{floor}} $ 到 $k_{\text{cut}} $，比值为 $\frac{2\pi N / (\alpha L)}{2\pi \beta / L} = \frac{N}{\alpha\beta} $）。两者相等不是巧合——这正是"无缝拼接"约束 $k_{\text{cut}}^{(i)} = k_{\text{floor}}^{(i+1)} $ 的几何含义。

#### 4.3 一般化的递推

通项公式：
$$
L_i = L_0 \cdot r^i = L_0 \cdot \left(\frac{\alpha\beta}{N}\right)^i
$$
频带边界：
$$
k_{\text{floor}}^{(i)} = \frac{2\pi\beta}{L_0 r^i}, \qquad k_{\text{cut}}^{(i)} = \frac{2\pi N}{\alpha L_0 r^i}
$$
在对数频率轴上，$N_c $ 个 cascade 总共覆盖：
$$
k_{\text{floor}}^{(0)} \le k \le k_{\text{cut}}^{(N_c - 1)}
$$
总频带跨度（倍频程数）：
$$
\log_2 \frac{k_{\text{cut}}^{(N_c-1)}}{k_{\text{floor}}^{(0)}} = N_c \cdot \log_2\frac{N}{\alpha\beta}
$$

### 五、代入具体值的完整频带表

参数：$L_0 = 10 $ m，$N = 256 $，$\alpha = 4 $，$\beta = 6 $，$r = 24/256 = 0.09375 $。

| $i $ | $L_i $ (m) | $\Delta k_i = 2\pi/L_i $ | $k_{\text{floor}}^{(i)} $ | $k_{\text{cut}}^{(i)} $ | $\lambda_{\text{floor}}^{(i)} = L_i/\beta $ | $\lambda_{\text{cut}}^{(i)} = \alpha L_i / N $ |
| ---- | ---------- | ------------------------ | ------------------------- | ----------------------- | ------------------------------------------- | ---------------------------------------------- |
| 0    | 10         | 0.628                    | 3.77                      | 40.2                    | 1.667 m                                     | 0.1563 m                                       |
| 1    | 0.9375     | 6.70                     | 40.2                      | 429                     | 0.1563 m                                    | 0.01465 m                                      |
| 2    | 0.0879     | 71.5                     | 429                       | 4577                    | 14.65 mm                                    | 1.373 mm                                       |
| 3    | 0.008240   | 762.3                    | 4577                      | 48820                   | 1.373 mm                                    | 0.1287 mm                                      |

可以看出：

1. **每行的 $\lambda_{\text{cut}}^{(i)} $ 等于下一行的 $\lambda_{\text{floor}}^{(i+1)} $**（精确等于 0.1563、0.01465、0.001373）——这就是无缝拼接。
2. **每行 $k_{\text{cut}}^{(i)} = k_{\text{floor}}^{(i+1)} $**（精确为 40.2、429、4577）——同一拼接的频域对偶视角。

### 六、级联数量与最大有用频带的选择

#### 6.1 物理上限

Tessendorf 论文指出 2 cm 以下波动会进入表面张力（capillary）regime，FFT 重力波模型不再适用。对应物理 cutoff：
$$
\lambda_{\text{phys}} \approx 0.02 \text{ m}, \qquad k_{\text{phys}} \approx 314 \text{ rad/m}
$$

#### 6.2 渲染上限

屏幕像素决定的 cutoff：在距相机 $d $ 处，一个像素覆盖的世界空间长度约为 $d / f $（$f $ 是焦距像素数）。波长小于这个尺度的位移采样后会变成噪声，不再贡献有意义的视觉信号。

#### 6.3 选择最优 $N_c $

合理的级联数应满足：
$$
k_{\text{cut}}^{(N_c - 1)} \approx \min\left(k_{\text{phys}},\ k_{\text{render}}\right)
$$
代入递推：
$$
\frac{2\pi N}{\alpha L_0 r^{N_c - 1}} = k_{\text{target}}
$$
代入物理 cutoff $k_{\text{target}} = 314 $，$L_0 = 10 $，$N = 256 $：
$$
N_c = 1 + \frac{\log_2(2\pi \cdot 256 / (4 \cdot 10 \cdot 314))}{\log_2(256/24)} = 1 + \frac{\log_2(0.128)}{3.42} = 1 + \frac{-2.96}{3.42} \approx 0.13
$$
负数说明：**给定 $L_0 = 10 $，单个 cascade 就已经能覆盖到物理截止以下了**——cascade 0 的 $k_{\text{cut}} = 40.2 $ 对应波长 15.6 cm，已经接近毛细波 regime。再加 cascade 1 严格说也是为了高频细节（mm 级毛细波区，非物理但视觉上提供"水面纹理"），cascade 2、3 几乎纯属计算浪费。

如果把 $L_0 $ 提到 250 m（gasgiant 的典型值）：
$$
N_c = 1 + \frac{\log_2(2\pi \cdot 256 / (4 \cdot 250 \cdot 314))}{3.42} = 1 + \frac{\log_2(0.00513)}{3.42} \approx 1 + \frac{-7.61}{3.42} \approx 3.22
$$
需要约 4 个 cascade 才能从 250 m 一路覆盖到 2 cm。这才是 4 个级联设计的合理使用场景。

### 七、$L_0 $ 的物理选择

$L_0 $ 取最大有意义波长。Pierson–Moskowitz 谱的峰值波数为：
$$
k_p = \frac{0.879 g}{V^2}, \qquad \lambda_p = \frac{2\pi V^2}{0.879 g}
$$
要让谱峰被 cascade 0 覆盖，需要 $L_0 \ge \lambda_p $。例如 $V = 10 $ m/s 风速：$\lambda_p \approx 71 $ m，应取 $L_0 \approx 100\sim200 $ m。$L_0 = 10 $ m 对应的隐含风速 $V \approx \sqrt{0.879 g L_0 / (2\pi)} \approx 3.7 $ m/s——微风条件，海面只有小型涌浪。

### 八、级联设计的判定准则总结

要判断一个 cascade 配置是否合理，依次检查：

**第一**，无缝拼接：$L_{i+1} / L_i = \alpha\beta / N $ 应当成立（或对应的 cutoff 代码生效）。代码里递推公式正确，但 cutoff 被注释掉，导致频段在能量上重叠。

**第二**，最大波长够用：$L_0 \ge \lambda_p(V) $，覆盖谱峰。当前 $L_0 = 10 $ m 偏小。

**第三**，最高频不超物理界：$k_{\text{cut}}^{(N_c-1)} \le k_{\text{phys}} $。当前 cascade 2、3 大幅超过毛细波边界，纯属计算浪费。

**第四**，相邻 $L_i $ 互不可整除（避免 tiling）。当前比例 0.09375 = 3/32 是有理数，存在公因子，理论上仍会有 tile 共振——不过尺度差太大（10 m vs 0.94 m），视觉上很难察觉。

按这套准则，最合理的修正应当是：把 $L_0 $ 提到 100~250 m 量级，$N_c $ 改为 3，恢复那段 cutoff 代码。当前配置在视觉上"看起来对"是因为 $L_0 = 10 $ m 的小尺度恰好与近距离视角匹配，配合 LOD 权重把高频 cascade 在远处衰掉，掩盖了能量重叠和低频缺失。