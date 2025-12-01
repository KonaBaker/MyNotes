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

> 关于这里的组成是针对传统（普遍）意义的，对于opengl4.5+，现在有独立的sampler对象，负责存储采样规则。opengl也明确定义了如果纹理单元绑定了sampler对象，则使用sampler的采样参数。否则使用纹理对象自带的采样参数。

### 关于mipmap

开启opengl mipmap机制可以根据相机距离的远近自动选择合适的mipmap层级。

本质是通过计算相邻像素之间的梯度来选取mipmap层级。（相邻像素在gpu中会同一时刻并行运行，所以可以使用相邻数据。像素块渲染）。

在顶点着色器中就无法自动计算了可以使用textureLod或者textureGrad自行计算梯度或者Lod来选取mipmap等级。

**一些api**：

``` texture```

纹理坐标[0,1]

```textureLod```

同上，需要指定lod级别

```texelFetch```

传入的坐标范围[0, texturesize - 1]

返回值是原始像素值，**没有过滤**，一般用于计算着色器。（过滤指插值结果）

```textureGrad```

纹理坐标[0,1]

- 有mipmap时

gpu自动会计算梯度并选择mipmap层级，但是这里手动指定梯度。

这个梯度指的是纹理坐标在**屏幕空间**x方向和y方向的偏导数。是uv到texel坐标的一个映射。然后对这个映射函数求偏导数。

本身没有各向异性过滤的效果，等同于textureLod()，只是用来制定选择lod的层级。

- 无mipmap时

等效于texure()梯度没有作用

**mipmap占用空间**：

每一级别的原始分辨率是上一级的四分之一（每一维度的一半）。

Mipmap 内存占用 =  M/4 + M/16 + M/64 + ... 

求和的到三分之一。



### 关于filter

- nearest最近邻选择距离采样点最近的texel
- linear对采样点周围的4个texel插值

生成mipmap（适用于MIN_FILTER）

还有针对mipmap的插值方式。

- 各向异性过滤，对于当视角和表面夹角过大，采样的时候x,y方向梯度变化不同，所以要采用各向异性的mipmap





### 区分

**unit:**（资源槽）

 GL_TEXTUREX 纹理单元或image unit。对于uniform image就不多说了，设置image unit.

uniform sampler的value就是texture unit，表示从哪一个纹理单元去采样。

一个texture unit可以同时有一个texture和一个sampler object.

layout(binding)就是用来设置这个unit（value)

**location:**（uniform自身属性）

用于在程序中找到这个uniform,由编译器分配或者使用layout(location)

**注意：** image和texture不共用unit,有image unit和texture unit

| 绑定操作                                  | 层级                              | 职责                                               | 说明                           |
| ----------------------------------------- | --------------------------------- | -------------------------------------------------- | ------------------------------ |
| `glUniform1i()` / `layout(binding)`       | **Shader 层 → Texture Unit**      | 告诉 shader：这个 sampler uniform 对应哪号纹理单元 | 它只是编号映射，不涉及具体纹理 |
| `glBindTextureUnit()` / `glBindTexture()` | **Texture Unit → Texture Object** | 把纹理对象挂在某个单元上                           | 决定采样数据来源               |
| `glBindSampler()`                         | **Texture Unit → Sampler Object** | 把采样参数（wrap/filter 等）挂到单元上             | 决定采样方式                   |

传统做法：

```
glactivetexutre
glbindtexture
glbindsampler
gluniform1i
```

现在：

```
glbindtextureunit
glbindsampler
```



绑定点设置遵循后覆盖原则。

layoutbinding发生在编译阶段，gluniform发生在运行阶段，所以后者会覆盖前者。

