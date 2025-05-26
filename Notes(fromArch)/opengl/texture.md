## texture

### 1. 理论

纹理是一个或多个图像的容器。具有三个特征：纹理类型、纹理大小和纹理保存的图像格式。

对于纹理类型：

- GL_TEXTURE_1/2/3D
- RECTANGLE 没有mipmap 二维的，纹理坐标未进行归一化处理。
- BUFFER 没有mipmap 一维的，数据的存储来自buffer
- cubemap/1d2d[array]
- multisample[array]没有mipmap，图像中的像素值包含多个样本。

对于纹理大小：

维度最大尺寸：GL_MAX_TEXTURE_SIZE

数组最大长度：GL_MAX_ARRAY_TEXTURE_LAYERS 

3d特殊维度：GL_MAX_3D_TEXTURE_SIZE

建议使用2的次幂作为纹理大小

对于纹理格式：

内部格式和外部格式。

mipmaps:

0层最大，依次减小。

### 2.Texture Objects

![Anatomy of a Texture](https://www.khronos.org/opengl/wiki_opengl/images/Anatomy_of_a_Texture.png)



# 关于mipmap

开启opengl mipmap机制可以根据相机距离的远近自动选择合适的mipmap层级。

本质是通过计算相邻像素之间的梯度来选取mipmap层级。（相邻像素在gpu中会同一时刻并行运行，所以可以使用相邻数据）

在顶点着色器中就无法自动计算了可以使用textureLod或者textureGrad自行计算梯度或者Lod来选取mipmap等级。

