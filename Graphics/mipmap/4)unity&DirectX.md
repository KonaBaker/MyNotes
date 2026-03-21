# DirectX-Graphics-Samples

https://github.com/Microsoft/DirectX-Graphics-Samples/blob/master/MiniEngine/Core/Shaders/GenerateMipsCS.hlsli

采用的方法是一次dispatch，不论奇偶最多连续生成4个mip层级.

```c++
[numthreads( 8, 8, 1 )]
void main( uint GI : SV_GroupIndex, uint3 DTid : SV_DispatchThreadID )
```

一个线程组，numthreads(8,8,1)，共64个线程。共享位置GI（自己线程的位置），使用shared memory共同协作。

处理整张纹理的时候会dispatch很多的线程组。`DTid.xy`是全局的像素输出坐标，每个线程负责一个`OutMip1[DTid.xy]`,后面层级的就由汇总的那个线程负责。

也就是说这8x8线程负责输出纹理中一块8x8区域（outMip1)

对于一个线程组负责的局部区域：（最多，不一定严格输出有效的像素） 

```
OutMip1: 8×8
OutMip2: 4×4
OutMip3: 2×2
OutMip4: 1×1
```

和nvpro不同的是，没有划分所谓的8x8tile，只是说一个线程组要负责一个区域。

每个层级之间并没有通过shuffle而是通过sharedmemory+barrier()。

---

**第一层**

每一个线程处理的，某一维度不是2:1的关系（如：15 -> 7)

根据维度的普通，选择采样在中间，还是0.25,0.75各采样一次作平均。

```C++
float2 UV1 = TexelSize * (DTid.xy + float2(0.25, 0.25));
float2 O = TexelSize * 0.5;
float4 Src1 = SrcMip.SampleLevel(BilinearClamp, UV1, SrcMipLevel);
Src1 += SrcMip.SampleLevel(BilinearClamp, UV1 + float2(O.x, 0.0), SrcMipLevel);
Src1 += SrcMip.SampleLevel(BilinearClamp, UV1 + float2(0.0, O.y), SrcMipLevel);
Src1 += SrcMip.SampleLevel(BilinearClamp, UV1 + float2(O.x, O.y), SrcMipLevel);
Src1 *= 0.25;
```

之后就是存储颜色然后作barrier()。

```
OutMip1[DTid.xy] = PackColor(Src1);
```

这一层做完了以后

---

**第二层**

这时候和nvpro一样，要做mask，每个部分的0号线程要取其周围三个线程的数值。

```C++
if ((GI & 0x9) == 0)
{
    float4 Src2 = LoadColor(GI + 0x01);
    float4 Src3 = LoadColor(GI + 0x08);
    float4 Src4 = LoadColor(GI + 0x09);
    Src1 = 0.25 * (Src1 + Src2 + Src3 + Src4);

    OutMip2[DTid.xy / 2] = PackColor(Src1);
    StoreColor(GI, Src1);
}

```

`0x9`是 001001,低三位是x，高三位是y。这就限制了，这个线程低三位和高三位的最后一位都必须是0,也就是x,y都是偶数，保证选到了每一个“0号线程”

- `0x9`：挑每个 2x2 block 的代表

- `0x1B`：挑每个 4x4 block 的代表

- `GI == 0`：挑整个 8x8 block 的代表

---

**第三层**

同理线程步长选择跨两个，坐标再缩小一半。

```c++
if ((GI & 0x1B) == 0)
{
    float4 Src2 = LoadColor(GI + 0x02);
    float4 Src3 = LoadColor(GI + 0x10);
    float4 Src4 = LoadColor(GI + 0x12);
    Src1 = 0.25 * (Src1 + Src2 + Src3 + Src4);

    OutMip3[DTid.xy / 4] = PackColor(Src1);
    StoreColor(GI, Src1);
}
```

---

第四层

```C++
if (GI == 0)
{
    float4 Src2 = LoadColor(GI + 0x04);
    float4 Src3 = LoadColor(GI + 0x20);
    float4 Src4 = LoadColor(GI + 0x24);
    Src1 = 0.25 * (Src1 + Src2 + Src3 + Src4);

    OutMip4[DTid.xy / 8] = PackColor(Src1);
}
```

---

**Notes**

1) bank conflicts的避免

```C++
groupshared float gs_R[64];
groupshared float gs_G[64];
groupshared float gs_B[64];
groupshared float gs_A[64];
```

bank是有word_size的，比如4B,也就是说连续的每4B数据放一个bank，如果写在一起

```c++
groupshared float4 gs[64];
```

那么一个数据成员gs[0]占16B.会放到不同的bank中。

这就会导致gs[n]的某个分量和gs[m]的某个分量落到同一个bank中，而且后面线程的访问还是有固定步长的当有不同线程访问的时候就会导致bank conflicts。

划分通道以后使用

```
gs_R[i] = c.r;
gs_G[i] = c.g;
gs_B[i] = c.b;
gs_A[i] = c.a;
```

对于 `gs_R[i]` 来说：

- 线程 0 访问 `gs_R[0]`
- 线程 1 访问 `gs_R[1]`
- ...
- 线程 63 访问 `gs_R[63]`



2) 对于是否走下一层使用`if (NumMipLevels == x)`这种判断，是不影响整个warp的，这是个常数参数，所有线程都一样，所有线程分支一样。

## 例子

假设当前 `SrcMip = 15×15`，要生成下一层 `OutMip1 = 7×7`

15 / 7 ≈ 2.14 不是严格的2:1

采样的区域应该是2.14 x 2.14，防止欠采样，一个线程采用更密集的样本去采样。

会有一些无效像素的覆盖，**也就是边角料的部分处理就这部分代码来说是错误的。**实际工程外应该要有**边界检查**。
