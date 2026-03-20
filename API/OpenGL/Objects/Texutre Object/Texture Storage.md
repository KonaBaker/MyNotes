# Texture Storage

纹理存储是纹理对象中实际包含像素数据的那一部分。

## 存储结构

存储包含一个或者多个images，每种纹理的存储有特定的images排列方式。每个mipmap层级都拥有一组独立的图像。

多个images的定位：

- mipmap **level**
- array **layer**
- cubemap **face**

### Image sizes

每层mipmap的一组images，大小都是相同的。

### 存储类型

- 可变

- 不可变

一次性分配所有images,level,layer,face，并设定image format。所有操作在一次调用完成。存储本身无法更改，但是纹理可删。

**注意**： 这里的不可变是指 内存的分配方式，而不是内存的内容。类似于**指针常量**，指针本身不可更改，但其中内容可更改。

- buffer storage

只有buffer texture才能用，存储空间来自buffer object

---

## 不可变存储

`glTextureStorageXD(Multisample)`

不可变存储分配。会根据指定的level和size以及internalformat来分配存储空间。

internal format就是image format如`GL_RGBA16F`等。

Multisample用于MSAA。对于fixedsamplelocations一般为`GL_TRUE`,子像素点的采样在固定位置，比如左上。

### texture views

不可变存储还可以在多个texture objects之间共享。

类似于**智能指针**和**共享内存**

`glTextureView(GLuint texture, GLenum target, GLuint origtexture, GLenum internalformat, GLuint minlevel, GLuint numlevels, GLuint minlayer, GLuint numlayers)`

`texture`是没有存储空间的新的纹理。

`origtexture`是拥有不可变存储的纹理。

**注意**:由于这个函数需要target，所以`texture`不能由DSA也就是glcreate来创建。target不必与`origtexture`匹配

视图可以仅是**一部分**。

【更多规则见https://wikis.khronos.org/opengl/Texture_Storage】



**不可变存储优点**：

- 方便、省事、不易出错。
- 显卡驱动可以更好的优化布局。
- 可以在多个texture objects间进行共享。

---

## 可变存储

`glTexImage`

**注意**：由于在DSA中强调动作解耦，所以基本上推行不可变存储 + 数据上传的模式，所以不再介绍。

---

## 存储内容

分配存储之后，可以通过各种函数修改或者访问存储的内容。

### mipmap生成

`void glGenerateTextureMipmap(GLuint texture);`

在调用之前mipmap的base层级必须已经建立。会读取`GL_TEXTURE_BASE_LEVEL`的数据，自动计算。

`GL_TEXTURE_MAX_LEVEL`控制有效mipmap范围。

过滤模式必须匹配。

### 上传数据

`glTextureSubImage`

- 在未绑定PBO的情况下，数据来源于CPU控制的RAM
- 绑定PBO的情况下，数据来源是PBO，且data传入的是一个整数偏移量。

### 下载数据

`glGetTextureImage`

将数据从GPU从CPU拉回内存。传入的是接收数据的指针。如果不适用PBO，同样也会阻塞。

```c++
void downloadTextureToCPU(GLuint textureID, int width, int height) {
    size_t dataSize = width * height * 4 * sizeof(GLubyte);
    std::vector<GLubyte> textureData(dataSize);
    glGetTextureImage(
        textureID, 
        0,                  // Level 0
        GL_RGBA,            // 格式
        GL_UNSIGNED_BYTE,   // 类型
        (GLsizei)dataSize,  // 容器容量
        textureData.data()  // 目标
    );
}
```

### framebuffer

【详细见Framebuffer Objects】

---

## buffer storage

buffer texture的数据直接来源于buffer objects，是一维的。用于允许着色器访问由buffer object管理的大型内存表。

`GL_TEXTURE_BUFFER` 调用`gl*Image`系列函数都会导致错误。

`void glTextureBuffer( GLuint texture, GLenum internalformat, GLuint buffer);`

无需创建存储空间，直接通过上面这个函数绑定一个buffer object就行了。internalformat是用来描述buffer object中存储的数据的。

访问限制 `GL_MAX_TEXTURE_BUFFER_SIZE`个纹素。

### range

`glTextureBufferRange`

绑定部分范围的buffer object。

### image formats

普通纹理的内存通常是tiled或者swizzled，便于访问。

但是buffer texture的内存是线性的。

所以只能支持直接线性读取的格式。一些image format是不支持的。

分量的字节序（大小端）和cpu平台原生字节序一致。

### parameters

在buffer texture上设置任何参数都是无效的。sampler object也和它无关。

### access in shaders

只能使用`texelFetch`

```c++
layout(binding = 0) uniform samplerBuffer u_mat;

void main() {
    vec4 res = texelFetch(u_mat, index);
}
```

sampler type是`gsamplerbuffer`

### limitations

- 不支持mipmap
- 不支持filter
- 无法附加到帧缓冲对象。

**本质是访问大型数据数组的一种方式。**

例子：骨骼动画矩阵存储，存储的东西UBO装不下，但是又不复杂，结构简单（用不着SSBO）。
