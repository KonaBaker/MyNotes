# multisampling

用于减少rasterized primitives边缘锯齿的过程

## aliasing

当模拟信号转换为数字信号时（连续到离散），由于采样点不足，导致的一种异常现象，会产生aliasing。

## antialiasing(SSAA)

最简单但是最耗性能的方法就是以某种方式增加采样数量。

**texture filtering**是一种抗锯齿形式，专门处理因访问纹理而产生的锯齿。mipmap纹素都相当于多个采样点（采样更高层级）。纹理过滤只处理因访问纹理或者基于此类访问的计算而产生的锯齿。不处理图元边缘的锯齿。

更通用的抗锯齿形式：高分辨率渲染，然后平均其中的像素值。这就是**超采样(super-sampling)**。就是把高分辨率图像的像素当作采样点。

当开启supersampling的时候，在光栅化时为每个像素分解为多个采样点去采样primitive。会为每个sample生成一个fragments。

缺点很明显：高分辨率渲染，而且最后还要额外做平均。

## multisampling(MSAA)

多重采样对超采样进行了一个小修改，更关注于**几何**边缘的抗锯齿。

多重采样仍为每个sample points生成光栅化数据，per-sample test顾名思义，也是按照每个sample来进行的。

区别是在fs中不是per-sample的。一把来说是每4个采样点执行一次，具体取决于实现和硬件。

- 对shading共享结果per-fragments
- depth/stencil test\几何覆盖是per-sample的

对于这一组采样点，选择其中一个执行，然后这4个采样点获得一样的处理后值。

### coverage

被primitive覆盖的采样点就是代表了这个片段的coverage。

一个sample的depth test/stencil test失败的时候，会修改片段的coverage。

fs可以访问/修改这个coverage。

- input: gl_SampleMaskIn[]（bitmask 代表这个片段中被覆盖的samples）
- output: gl_SampleMask（设置coverage）只能写实际覆盖范围以内的采样点。

### edges

刚刚说到fs在执行的时候会选择一个sample代替这fragment所有，这个sample可能正好选择到图元之外，那么这sample的相关属性仍然可以通过插值而来（但是不具备几何意义了），可能得到负值（而你在fs中可能要开根号）。

glsl中的`centroid`限定符限制只能在图元区域内进行插值。`centroid in vec2 uv`

### Fixed sample location

sample在pixel中的位置[0,1]，左下角原点。当我们使用gltexturestorage创建multisample texture/rbo时，可以将最后一个参数`fixedsamplelocations`设为`GL_TRUE`. 保证了每个fragment的sample的位置布局以及数量是相同的。很多实现为了减少某些走样，会让 sample 布局在图像中变化。

### resolve

multisample FBO blit到 single-sample FBO

### per-sample shaing

MSAA -> SSAA

如何开启：

- fs内部使用特定输入变量
- `glEnable(GL_SAMPLE_SHADING)`

通过`glMinSampleShading`指定百分比，比如0.3,则30%的sample是per-sample，1.0就是完全per-sample

这30%是哪30%由具体实现定义

---

# usage

需要使用`glEnable(GL_MULTISAMPLE)`（一般都默认开启） 并且 rendertarget是multisample的(FBO或者default)(一般无法是default,其由外部窗口创建，一般都是单采样)。

```
GLuint msaaFbo = 0;
GLuint colorRbo = 0;
GLuint depthStencilRbo = 0;

int width = 1280;
int height = 720;
int samples = 4; 

glCreateFramebuffers(1, &msaaFbo);

glCreateRenderbuffers(1, &colorRbo);
glNamedRenderbufferStorageMultisample(
    colorRbo,
    samples,
    GL_RGBA8,
    width,
    height
);

glCreateRenderbuffers(1, &depthStencilRbo);
glNamedRenderbufferStorageMultisample(
    depthStencilRbo,
    samples,
    GL_DEPTH24_STENCIL8,
    width,
    height
);

glNamedFramebufferRenderbuffer(
    msaaFbo,
    GL_COLOR_ATTACHMENT0,
    GL_RENDERBUFFER,
    colorRbo
);
glNamedFramebufferRenderbuffer(
    msaaFbo,
    GL_DEPTH_STENCIL_ATTACHMENT,
    GL_RENDERBUFFER,
    depthStencilRbo
);


glBindFramebuffer(GL_FRAMEBUFFER, msaaFbo);
glViewport(0, 0, width, height);

// GL_MULTISAMPLE 默认就是开着的，但显式写也可以
glEnable(GL_MULTISAMPLE);
glEnable(GL_DEPTH_TEST);

glClearColor(0.1f, 0.1f, 0.12f, 1.0f);
glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

glUseProgram(program);
glBindVertexArray(vao);
glDrawArrays(GL_TRIANGLES, 0, 3);


// 从 multisample FBO blit 到默认 framebuffer
glBindFramebuffer(GL_READ_FRAMEBUFFER, msaaFbo);
glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);

glBlitFramebuffer(
    0, 0, width, height,
    0, 0, width, height,
    GL_COLOR_BUFFER_BIT,
    GL_NEAREST
);

// 然后交换窗口缓冲
// glfwSwapBuffers(window);
```

**Q:如果开启了多重采样，color attachment是multisample的但是depth/stencil不是会发生什么？**

A: framebuffer会验证附件完整性，这是不合规的。
