下面给你一套**现实工程里非常常用**的总结例子：**MSAA GBuffer（多渲染目标）+ Depth/Stencil + Resolve 到可采样的单采样贴图**。我会**严格使用 DSA**（创建/配置/清理/拷贝全 DSA），并且把你前面学到的关键点都串起来。

> 说明：OpenGL 里“执行绘制”仍然需要把目标设为当前 draw framebuffer（`glBindFramebuffer(GL_DRAW_FRAMEBUFFER, …)`），这不是 bind-to-edit，而是“选择渲染目标”；除此之外都用 DSA。

------

# 目标与结构

- **MSAA FBO**：用于几何阶段写入（抗锯齿）。
  - Color attachments：MSAA **renderbuffer**（更常见、更省心）
  - Depth/Stencil：MSAA renderbuffer（`DEPTH24_STENCIL8`）
- **Resolve FBO**：单采样，attachments 是 **textures**，用于后续 lighting pass 采样
  - Color textures：albedo / normal / material（你按需扩展）
  - Depth texture：可选（若后处理要采样深度，否则可不存）

流程：

1. geometry pass 渲染到 **MSAA FBO**
2. 用 `glBlitNamedFramebuffer` 把 MSAA 的每个 color attachment resolve 到 **Resolve FBO 的 texture**
3. lighting pass 采样 resolve textures

------

# 一、资源创建（严格 DSA）

## 1) 创建 GBuffer resolve textures（单采样，可采样）

示例内部格式（工程常用的一套）：

- Albedo：`GL_SRGB8_ALPHA8`（如果你走线性工作流 + 输出到 sRGB）
- Normal：`GL_RG16F` 或 `GL_RGBA16F`（看你法线编码）
- Material：`GL_RGBA8`（rough/metal/ao/… packed）
- Depth：如果要采样深度：`GL_DEPTH_COMPONENT24`（或 32F）

```
GLuint texAlbedo, texNormal, texMaterial, texDepth;
glCreateTextures(GL_TEXTURE_2D, 1, &texAlbedo);
glCreateTextures(GL_TEXTURE_2D, 1, &texNormal);
glCreateTextures(GL_TEXTURE_2D, 1, &texMaterial);
glCreateTextures(GL_TEXTURE_2D, 1, &texDepth);

// immutable storage
glTextureStorage2D(texAlbedo,  1, GL_SRGB8_ALPHA8,  w, h);
glTextureStorage2D(texNormal,  1, GL_RG16F,         w, h);
glTextureStorage2D(texMaterial,1, GL_RGBA8,         w, h);
glTextureStorage2D(texDepth,   1, GL_DEPTH_COMPONENT24, w, h);

// 采样参数（也可用 sampler object；这里简单放在 texture 上）
glTextureParameteri(texAlbedo,   GL_TEXTURE_MIN_FILTER, GL_NEAREST);
glTextureParameteri(texAlbedo,   GL_TEXTURE_MAG_FILTER, GL_NEAREST);
glTextureParameteri(texNormal,   GL_TEXTURE_MIN_FILTER, GL_NEAREST);
glTextureParameteri(texNormal,   GL_TEXTURE_MAG_FILTER, GL_NEAREST);
glTextureParameteri(texMaterial, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
glTextureParameteri(texMaterial, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
glTextureParameteri(texDepth,    GL_TEXTURE_MIN_FILTER, GL_NEAREST);
glTextureParameteri(texDepth,    GL_TEXTURE_MAG_FILTER, GL_NEAREST);
```

## 2) 创建 resolve FBO，并把 textures 作为 attachments

```
GLuint fboResolve;
glCreateFramebuffers(1, &fboResolve);

glNamedFramebufferTexture(fboResolve, GL_COLOR_ATTACHMENT0, texAlbedo,   0);
glNamedFramebufferTexture(fboResolve, GL_COLOR_ATTACHMENT1, texNormal,   0);
glNamedFramebufferTexture(fboResolve, GL_COLOR_ATTACHMENT2, texMaterial, 0);
glNamedFramebufferTexture(fboResolve, GL_DEPTH_ATTACHMENT,  texDepth,    0);

// 指定 MRT 写路由（draw buffers）
{
  GLenum bufs[] = { GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1, GL_COLOR_ATTACHMENT2 };
  glNamedFramebufferDrawBuffers(fboResolve, 3, bufs);
}
```

> 你前面学的点：**attachment ≠ draw buffers**。attachment 只是挂载，draw buffers 才决定 FS outputs 写到哪些 color attachments。

------

## 3) 创建 MSAA renderbuffers，并 attach 到 MSAA FBO

这里用 MSAA RBO 作为 GBuffer（非常常见）：

```
GLuint rbAlbedoMS, rbNormalMS, rbMaterialMS, rbDepthStencilMS;
glCreateRenderbuffers(1, &rbAlbedoMS);
glCreateRenderbuffers(1, &rbNormalMS);
glCreateRenderbuffers(1, &rbMaterialMS);
glCreateRenderbuffers(1, &rbDepthStencilMS);

glNamedRenderbufferStorageMultisample(rbAlbedoMS,       samples, GL_SRGB8_ALPHA8,   w, h);
glNamedRenderbufferStorageMultisample(rbNormalMS,       samples, GL_RG16F,          w, h);
glNamedRenderbufferStorageMultisample(rbMaterialMS,     samples, GL_RGBA8,          w, h);
glNamedRenderbufferStorageMultisample(rbDepthStencilMS, samples, GL_DEPTH24_STENCIL8, w, h);

GLuint fboMSAA;
glCreateFramebuffers(1, &fboMSAA);

glNamedFramebufferRenderbuffer(fboMSAA, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rbAlbedoMS);
glNamedFramebufferRenderbuffer(fboMSAA, GL_COLOR_ATTACHMENT1, GL_RENDERBUFFER, rbNormalMS);
glNamedFramebufferRenderbuffer(fboMSAA, GL_COLOR_ATTACHMENT2, GL_RENDERBUFFER, rbMaterialMS);
glNamedFramebufferRenderbuffer(fboMSAA, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, rbDepthStencilMS);

{
  GLenum bufs[] = { GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1, GL_COLOR_ATTACHMENT2 };
  glNamedFramebufferDrawBuffers(fboMSAA, 3, bufs);
}
```

------

## 4) 完整性检查（建议调试期开启）

```
auto s1 = glCheckNamedFramebufferStatus(fboMSAA,   GL_FRAMEBUFFER);
auto s2 = glCheckNamedFramebufferStatus(fboResolve,GL_FRAMEBUFFER);
// assert(s1 == GL_FRAMEBUFFER_COMPLETE && s2 == GL_FRAMEBUFFER_COMPLETE);
```

------

# 二、Geometry Pass（写入 MSAA GBuffer）

### 1) 清理（严格 DSA）

你可以不 bind，直接清指定 FBO：

```
const float clear0[4] = {0,0,0,0};
const float clearN[4] = {0,0,0,0};
const float clearM[4] = {0,0,0,0};
float clearDepth = 1.0f;
int   clearStencil = 0;

glClearNamedFramebufferfv(fboMSAA, GL_COLOR, 0, clear0);
glClearNamedFramebufferfv(fboMSAA, GL_COLOR, 1, clearN);
glClearNamedFramebufferfv(fboMSAA, GL_COLOR, 2, clearM);
glClearNamedFramebufferfi(fboMSAA, GL_DEPTH_STENCIL, 0, clearDepth, clearStencil);
```

> 你学到的点：`glClearNamedFramebuffer*` **允许 0 表示 default**，也能对 FBO 清理；这里我们清的是 fboMSAA。

### 2) 选择绘制目标（执行绑定点）

```
glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fboMSAA);
glViewport(0, 0, w, h);
```

### 3) 使用你引擎的 program / pipeline（建议 uniform 全用 DSA）

- program pipeline：`glBindProgramPipeline(pipe);`
- uniform：用 `glProgramUniform*`（per-program，不依赖 active program）
- UBO/SSBO：用 `layout(binding=N)` + `glBindBufferBase`（绑定点全局一致）

然后 `glDraw*`。

------

# 三、MSAA Resolve（把多采样 RBO 解析到可采样 textures）

核心：对每个 attachment 做一次 resolve。**纯 DSA：用 `glBlitNamedFramebuffer`，不需要 bind。**

Resolve 颜色时，源端选择 **read buffer**（color buffer 选择器），目标端只需要它有对应 attachment（draw buffers 在 blit 里不作为“写路由表”，它直接按当前 mask/目标区域写入）。

```
auto blitColor = [&](int i){
  glNamedFramebufferReadBuffer(fboMSAA, GL_COLOR_ATTACHMENT0 + i);
  glBlitNamedFramebuffer(
      fboMSAA, fboResolve,
      0,0,w,h,
      0,0,w,h,
      GL_COLOR_BUFFER_BIT,
      GL_NEAREST // MSAA resolve 必须 NEAREST
  );
};

blitColor(0);
blitColor(1);
blitColor(2);
```

Depth（如果你也要 resolve depth 到 texDepth）：

- MSAA depth resolve 在 GL 里通常通过 `GL_DEPTH_BUFFER_BIT` blit；是否支持、以及 filter 限制与实现有关，工程上很多人只保留单采样 depth（不 resolve）或 geometry pass 直接写单采样 depth texture（不做 MSAA depth 采样）。
- 如果你确实要尝试：

```
glBlitNamedFramebuffer(
  fboMSAA, fboResolve,
  0,0,w,h,
  0,0,w,h,
  GL_DEPTH_BUFFER_BIT,
  GL_NEAREST
);
```

> 你学到的点：
>
> - **read buffer 只针对 color**（选择哪个 `GL_COLOR_ATTACHMENTi` 作为源）
> - depth/stencil 的 blit 不看 read buffer，靠 mask 决定（`GL_DEPTH_BUFFER_BIT`/`GL_STENCIL_BUFFER_BIT`）。

------

# 四、Lighting Pass（采样 resolve textures，输出到 default framebuffer）

1. 把 resolve textures 绑定到纹理单元（或用 bindless/DSA 方案按你引擎策略）
2. 绘制全屏三角形到 default framebuffer

执行目标选择（仍然是“选择”，不是 bind-to-edit）：

```
glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
glViewport(0, 0, winW, winH);
```

清 default（严格 DSA 清理可用 0）：

```
float clearScreen[4] = {0,0,0,1};
glClearNamedFramebufferfv(0, GL_COLOR, 0, clearScreen);
```

然后 draw lighting。