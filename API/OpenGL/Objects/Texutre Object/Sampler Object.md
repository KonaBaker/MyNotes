# Sampler Object

一种openGL object,用于存储texture的采样参数。

## usage

` void glBindSampler(GLuint unit, GLuint sampler);`

这里的unit只能是**texture image unit**，不能是image unit。

因为一些环绕、mipmap等参数对shader中image变量没用，sampler object的参数只规定了sampler变量的行为方式/

`glSamplerParameter(GLuint sampler, GLenum pname, T param);`

## parameters

### filtering

`GL_TEXTURE_MAG_FILTER` **[放大/近/纹理分辨率低/一纹素多像素]**

> minecraft中的方块

- `GL_NEAREST`最近邻选择距离采样点最近的texel

- `GL_LINEAR`对采样点周围的4个texel插值



`GL_TEXTURE_MIN_FILTER` **[缩小/远/纹理分辨率高/一像素多纹素]**

<img src="./assets/image-20260223131643289.png" alt="image-20260223131643289" style="zoom: 50%;" />



使用mipmap。如果不使用，可能会出现闪烁或者摩尔纹。

- `GL_LINEAR`
- `GL_NEAREST`

- `GL_NEAREST_MIPMAP_NEAREST`
- `GL_LINEAR_MIPMAP_LINEAR`
- ...

mag filter和min filter在linear和nearest的方法完全是一样的，这两种模式和远近无关。区别就在于min filter可以选择mipmap

### 各项异性过滤

为了解决不规则纹理，一个倾斜的地板，一个屏幕像素在左右方向可能只覆盖一个，但是在垂直方向上可能覆盖很多。

默认情况下，会照顾“压缩的最厉害的那个方向”，选择最小的mipmap层级，那么左右方向上，就会模糊了。

设置最大采样次数`GL_TEXTURE_MAX_ANISOTROPY` [1, `GL_MAX_TEXTURE_MAX_ANISOTRPY`]

大于1.0f的值都表示开起了各项异性过滤。数值越大，代表情况越（极端，倾斜角度越大）。

这是建立在mipmap上的增强技术，不能单独工作。

为获得最佳效果应将各项异性过滤配合 min_filter的`GL_LINEAR_MIPMAP_LINEAR`使用。

开启各项异性过滤的情况下，会选择左右方向的mipmap层级，但是垂直方向就会闪烁，此时会沿着垂直方向，再进行多次采样

### LOD range

`GL_TEXTURE_MIN_LOD` 和 `GL_TEXTURE_MAX_LOD`

限制mipmap层级的选取范围。最后算出了选取level x。这两个参数会将x钳制在范围内。

**区别**

`GL_TEXTURE_BASE_LEVEL`:这个是结构性的，指定某一级为level 0。

**例子**

纹理流式加载

不会去读范围之外的mipmap。

不同mipmap层级缓慢加载，限制的Lod也随着加载而改变。

### LOD bias

`GL_TEXTURE_LOD_BIAS`

$ λ_{final}=λ_{calculated}+LOD_{bias} $

**例子**：

- 对抗TAA bias -0.5 让其看起来更尖锐一些
- 泛光：设置正值，模糊更晕染。

## comparison mode

> **Comparison Mode** 是 OpenGL 送给开发者的一个 **“硬件级 PCF 滤镜”**。

通常采样纹理的目的是获取值。但在comparison mode下，变成了获取测试结果。

`GL_TEXTURE_COMPARE_MODE`

- `GL_NONE` 

  直接获取值，一般用于SSAO需要要直接获取具体深度的场景。

- `GL_COMPARE_REF_TO_TEXTURE` 

  给一个参考值，进行比较，返回比较结果 0.0 false或者1.0 true。

  一般用于阴影映射。先比较，再linear -> 软阴影。

  启用时需要使用sampler2DShadow。此时texture()增加一维参考值。

`GL_TEXTURE_COMPARE_FUNC`

- `GL_ALWAYS`
- `GL_LESS`
- `GL_GREATER`
- 等等...

## edge

针对纹理坐标不在[0.0, 1.0]的范围的情况。

不同**纹理维度**：

`GL_TEXTURE_WRAP_{S|T|R}`

**方法**有：

- `GL_REPEAT`  循环 -0.2 = 0.8
- `GL_MIRRORED_REPEAT`  -0.2 = 0.2
- `GL_CLAMP_TO_EDGE` 钳制在0~1
- `GL_CLAMP_TO_BORDER` 钳制，但是边缘纹素会和一个恒定的border color进行混合
- `GL_MIRROR_CLAMP_TO_EDGE` 0 ~ 1镜像，钳制在 -1 ~ 1

**Border Color**:
`GL_TEXTURE_BORDER_COLOR` 

四分量需要使用v。需要和纹理的image format保持一致。

