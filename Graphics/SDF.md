# 1 SDF

## 1.1 overview

每个像素/体素记录自己与距离自己最近物体之间的距离。物体内为负值，边界上为0。主要用于:

- ray marching
- 梯度计算
- CSG

SDF包括2D/3D方法：

2D:(都是实时的)

- SDF FONT  灰度纹理
- MSDF  解决锐角失真
- MTSDF

3D:

- mesh distance field 离线对每个网格体素化，生成3D体积纹理  **/离线预计算**
- global distance field mesh DF运行时合并成粗粒度clipmap。 **/实时**
- 体积SDF  **/复杂度依赖/有限实时**

### samples

**lumen中主要应用于**:( 动态形变 Mesh、蒙皮骨骼 Mesh 不会自动更新 Mesh DF（代价太高）；)

- DFAO **/实时**
- DFSS，软阴影，性能优于PCSS **/实时**
- software lumen  /mesh + global

**unity HDRP**

- SDF字体 textmeshpro(MSDF)

**Godot**

- SDFGI 比较接近lumen的做法.更适用于低端硬件。

## 1.2 basic & 2D

### 8ssedt

类似于 动态规划/最短路。

- 自身是物体边界，那么sdf值就为0
- 其他的像素点，根据自己周围的像素点，进行更新`minSDF(n.sdf, distance(now, n));` 不是简单的取最小，而是一个具体的计算函数。

首先就是遍历图像，两个grid,将物体内和物体外的点标记出来,标记相反，首先生成grid1的SDF值，可以算出所有后物体外的SDF值。之后对于grid2(其物体内外的值跟grid1正好相反）。计算`grid1(pixel).sdf - grid2(pixel).sdf`就能得到完整的SDF。

**generate**过程：

先跑一遍从左到右，从上到下，传递来自左上方四个格子的信息。再跑一遍相反的，传递来自右下方所有格子的信息。

**应用**

- 比如一些文字或者标志，生成一个贴图的SDF，然后使用shader根据SDF值进行渲染，这样可以减少模糊。bitmap存储的是每个像素的颜色。两者在渲染的时候使用的插值的几何意义是不同的，一个插值距离，一个插值颜色
- 还可以用于过渡。根据SDF进行插值，用于阴影等。

### MSDF

【待补充】

### samples for antiAA

【待补充】https://drewcassidy.me/2020/06/26/sdf-antialiasing/

## 1.3 3D

### Voxelization



### jumpflooding



### CDT



# 2 Samples 

## 2.1 compressed SDF for cloud

## 2.2 Lumen

### mesh DF

### global DF

## 2.3 SDFGI

# 3 Conclusion

