假设一个三角形三个顶点分别有属性：
$$
a_0,\ a_1,\ a_2
$$
比如纹理坐标、颜色、法线等。

如果你在屏幕空间直接按重心坐标线性插值：
$$
a = \lambda_0 a_0 + \lambda_1 a_1 + \lambda_2 a_2
$$
那么在透视投影下会错。

------

# 4. 为什么直接线性插值会错？

因为投影变换不是仿射变换，而是含有除法的射影变换。

也就是说：

- 顶点在 3D 空间线性变化
- 映射到屏幕后，不再保持线性

所以如果你想让属性在 3D 几何意义下“正确”地变化，不能直接在屏幕空间插值属性本身，而必须做 **perspective-correct interpolation**。

------

# 5. 透视正确插值的公式

设三角形三个顶点的 clip-space `w` 分别是：
$$
w_0,\ w_1,\ w_2
$$
片元在屏幕空间对应的重心系数是：
$$
\lambda_0,\ \lambda_1,\ \lambda_2
$$
那么属性 $a$ 的正确插值公式是：
$$
a
=
\frac{
\lambda_0 \frac{a_0}{w_0}
+
\lambda_1 \frac{a_1}{w_1}
+
\lambda_2 \frac{a_2}{w_2}
}{
\lambda_0 \frac{1}{w_0}
+
\lambda_1 \frac{1}{w_1}
+
\lambda_2 \frac{1}{w_2}
}
$$
注意分母：
$$
\lambda_0 \frac{1}{w_0}
+
\lambda_1 \frac{1}{w_1}
+
\lambda_2 \frac{1}{w_2}
$$
这就是那个关键量。

OpenGL 把它作为片元内建量暴露出来：
$$
gl\_FragCoord.w
=
\lambda_0 \frac{1}{w_0}
+
\lambda_1 \frac{1}{w_1}
+
\lambda_2 \frac{1}{w_2}
$$
也就是：

> **片元位置对应的 $1/w_c$**