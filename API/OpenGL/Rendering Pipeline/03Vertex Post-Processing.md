# vertex post processing

## transform feedback

将vertex processing的output存储到buffer objects中，只有其中的最后一个stage(vs/tes/gs)才可以进行这一步

【详细见sub 3-1 transform feedback】

## primitive assembly

接收顶点流，根据draw call中指定的图元类型，转换成一系列图元。也可以discard，不渲染，配合transform feedback使用。

【具体见primitive assembly】

## clipping 视锥剔除

$ {\begin{aligned}-w_{c}&\leq x_{c}&\leq w_{c}\\-w_{c}&\leq  y_{c}&\leq w_{c}\\-w_{c}&\leq z_{c}&\leq w_{c}\end{aligned}} $

上一个阶段的图元被收集起来，被裁剪到视锥体内。

gl_Position就是顶点的clip-space的位置。

这个视锥体可以通过depth clamping和user-defined clip-planes进行修改。

**裁剪规则**

- points 在视锥体外，discard。根据点的中心位置进行判断。**nvidia特殊**：只会在完全移出的时候才会消失。
- lines 被截断，然后在边界上生成新的顶点。
- triangles  生成新的多边形，然后再三角化。

以上新的顶点的属性是通过对output(clip-space)线性插值生成的。

如果一个图元跨越多个裁剪平面，则会先对一个平面裁剪，再根据结果对另一个平面裁剪。

**depth clamping**
$ -w_{c}\leq z_{c}\leq w_{c} $

`glEnable(GL_DEPTH_CLAMP)` 决定是否被视锥体近远平面所裁剪。（近平面到相机之间不会被裁剪，但是相机后方仍然会被裁剪）

z值的计算正常进行

- 之前照样做投影
- 不clip
- 照样做透视除法
- 照样做depth range映射到window z

但是在计算出窗口空间的位置之后，z值将会被clamp到`glDepthRange(nearVal, farVal)`的范围内。

**note**:

clamp之后挤在一起的是depth buffer中的深度值，例如：超出原平面的所有顶点z值都会为1.但是只是深度值。

导致原本在 far plane 后面深度有先后关系的东西，现在都变成同一个 z。所以无法保证远处深度关系的正确。

它主要适合那些你宁愿牺牲深度精度，也不想被截断的场景，比如：

- infinite projection
- shadow volumes
- 某些特殊可视化

**user-defined clipping**
除了固定的6个平面以外。通过`gl_clipDistance`来进行指定。

> 对每个顶点提供一个“到某个裁剪平面/曲面边界的有符号距离”

例如：

```
gl_ClipDistance[0] = dot(worldPos, plane);

glEnable(GL_CLIP_DISTANCE0);
```

- `> 0`：在平面保留的一侧

- `< 0`：在被裁掉的一侧

- `= 0`：正好在平面上

`gl_ClipDistance[0]`就是一个额外的裁剪平面。

过程：和固定裁剪平面一样，每个顶点进行判断。

**cons:**
当一个drawcall内部不共享一个裁剪平面的时候，这个区域可能需要作为顶点属性，会占用空间。

对于这种方法可以使用UBO+索引。

**和discard的区别：**

发生阶段、是否影响early-z以及性能，是否改变几何、图元边界。

## 透视除法

clip-space到ndc[-1,1]

$  {\begin{pmatrix}x_{ndc}\\y_{ndc}\\z_{ndc}\end{pmatrix}}={\begin{pmatrix}{\tfrac {x_{c}}{w_{c}}}\\{\tfrac {y_{c}}{w_{c}}}\\{\tfrac  {z_{c}}{w_{c}}}\end{pmatrix}} $

## viewport变换

ndc space 到 window space。window space就是之后要光栅化的坐标。

```c++
void glViewport(GLint x, GLint y, GLsizei width, GLsizei height);
void glDepthRange(GLdouble nearVal, GLdouble farVal); 
```

$  {\begin{pmatrix}x_{w}\\y_{w}\\z_{w}\end{pmatrix}}={\begin{pmatrix}{\begin{aligned}{\tfrac {width}{2}}x_{ndc}&+x+{\tfrac {width}{2}}\\{\tfrac  {height}{2}}y_{ndc}&+y+{\tfrac {height}{2}}\\{\tfrac  {farVal-nearVal}{2}}z_{ndc}&+{\tfrac  {farVal+nearVal}{2}}\end{aligned}}\end{pmatrix}} $

- NDC z = -1 → window z = 0

- NDC z = 1  → window z = 1

$z_w$就是窗口空间的深度值。