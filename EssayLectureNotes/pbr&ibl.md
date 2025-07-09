# IBL

## some terms

**Radiant Flux**(watts):
一个光源释放的所有能量的总和。

**Radiant Intensity**:

radiant flux per solid angle

一个光源可能向四面八方散射能量。用来衡量某一方向发射的能量。

**Radiance**:
$$
L=dϕ^2/dAdωcosθ
$$
radiant flux per solid angle per area

光源向某一方向射出的能量，并且在这个方向到达某一平面。这个平面在单位面积接收的能量（考虑了夹角），这个夹角是转换过程中的几何修正。

**Irradiance**:
对于一个接收点，Radiance在半球上的总和。



## 渲染方程

最好基于物理的模拟光的方程：渲染方程：
$$
L_o(p,ω_o)=∫_Ωfr(p,ω_i,ω_o)L_i(p,ω_i)n⋅ω_idω_i
$$
告诉我们如何mix all the incoming 'colored light'

这里入射角考虑是光线贡献的权重，和Radiance的夹角不一样，不冲突。



- 找到合适的形式去表示场景中所有的radiance
- 实时的快速积分



对于第一个，可以使用environment maps.
$$
L(p_i,ω_i)=texCUBE(cubemap,ω_i)
$$
两个方法去减少错误并节省内存消耗：

- cubemap不止一张，在场景中创建多张，对于不同点p选取最近的点（中心）的cubemap.

- 然后为了进一步减少错误可以对采样方向进行修正



对于第二个：

首先看Lambert BRDF:
$$
L_o(p,ω_o)=∫_Ωc/πL_i(p,ω_i)(n⋅ω_i)dω_i=
L_o(p,ω_o)=c/π∫_ΩL_i(p,ω_i)(n⋅ω_i)dω_i
$$
我们可以对积分进行预计算（比如使用蒙特卡洛方法），将结果保存到另一张cubemap中。这张cubemap是卷积后的irradiance cubemap上面那一张是radiance cubemap。
$$
L_o(p,θ_o,ϕ_o)=\frac{c}{π}\frac{2π}{N_1}\frac{π}{2N_2}\sum^{N1}\sum^{N2}L_i(p,θ_i,ϕ_i)cos(θ_i)sin(θ_i)
$$

$$
L_o(p,θ_o,ϕ_o)=\frac{πc}{N_1N_2}\sum^{N_1}\sum^{N_2}L_i(p,θ_i,ϕ_i)cos(θ_i)sin(θ_i)
$$



区别如下：（左边是radiance cubemap 右边是卷积后的irradiance cubemap）

![img](http://www.codinglabs.net/public/contents/article_physically_based_rendering/images/envmaps.jpg)
$$
L(p,ω_o)=texCUBE(lambertCubemap,n)
$$

## 镜面IBL

$$
L_o(p,ω_o)=∫_Ω(k_s\frac{DFG}{4(ω_o⋅n)(ω_i⋅n)}L_i(p,ω_i)n⋅ω_idω_i=∫_Ωf_r(p,ω_i,ω_o)L_i(p,ω_i)n⋅ω_idω_i
$$

Cook-Torrance的镜面部分，比刚刚的公式要复杂，涉及的变量较多，实时耗时太大。



如果不分割：

```
float3 SpecularIBL( float3 SpecularColor , float Roughness, float3 N, float3 V )
{
    float3 SpecularLighting = 0;
    const uint NumSamples = 1024;
    for( uint i = 0; i < NumSamples; i++ )
    {
        float2 Xi = Hammersley( i, NumSamples );
        4
        float3 H = ImportanceSampleGGX( Xi, Roughness, N );
        float3 L = 2 * dot( V, H ) * H - V;
        float NoV = saturate( dot( N, V ) );
        float NoL = saturate( dot( N, L ) );
        float NoH = saturate( dot( N, H ) );
        float VoH = saturate( dot( V, H ) );
        if( NoL > 0 )
        {
            float3 SampleColor = EnvMap.SampleLevel( EnvMapSampler , L, 0 ).rgb;
            float G = G_Smith( Roughness, NoV, NoL );
            float Fc = pow( 1 - VoH, 5 );
            float3 F = (1 - Fc) * SpecularColor + Fc; //specularcolor = f0
            // Incident light = SampleColor * NoL
            // Microfacet specular = D*G*F / (4*NoL*NoV)
            // pdf = D * NoH / (4 * VoH)
            SpecularLighting += SampleColor * F * G * VoH / (NoH * NoV);
        }
    }
    return SpecularLighting / NumSamples;
}

```



需要使用分割求和近似法(split sum approximation)来进行简化。
$$
L_o(p,ω_o)=∫_ΩL_i(p,ω_i)dω_i∗∫_Ωf_r(p,ω_i,ω_o)n⋅ω_idω_i
$$
拆成了这样的两个部分。
$$
\frac{1}{N}\sum_{k=1}^{N}\frac{L_i(l_k)f(l_k,v)cos\theta_{l_k}}{p(l_k,v)} = (\frac{1}{N}\sum_{k=1}^{N}L_i(l_k))(\frac{1}{N}\sum_{k=1}^{N}\frac{f(l_k,v)cos\theta_{l_k}}{p(l_k,v)})
$$


第一个部分称为prefiltered envmap，但是这次考虑了粗糙度，有五个不同mipmap级别来存储不同粗糙度。

第二部分是brdf积分贴图(lut)横坐标是法向量和输入向量夹角的余弦值，纵坐标是粗糙度。

### prefiltered envmap

通过蒙特卡洛和重要性采样来获取。

这里在计算的时候做了仅此，n=v=r

```
float3 PrefilterEnvMap( float Roughness, float3 R )
{
    float3 N = R;
    float3 V = R;
    float3 PrefilteredColor = 0;
    const uint NumSamples = 1024;
    for( uint i = 0; i < NumSamples; i++ )
    {
        float2 Xi = Hammersley( i, NumSamples );
        float3 H = ImportanceSampleGGX( Xi, Roughness, N );
        float3 L = 2 * dot( V, H ) * H - V;
        float NoL = saturate( dot( N, L ) );
        if( NoL > 0 )
        {
            PrefilteredColor += EnvMap.SampleLevel( EnvMapSampler , L, 0 ).rgb * NoL;
            TotalWeight += NoL;
        }
    }
    return PrefilteredColor / TotalWeight;
}
```

在这之后进行mipmap的制作即可

### BRDF LUT

```
float2 IntegrateBRDF( float Roughness, float NoV )
{
    float3 V;
    V.x = sqrt( 1.0f - NoV * NoV ); // sin
    V.y = 0;
    V.z = NoV; // cos
    float A = 0;
    float B = 0;
    const uint NumSamples = 1024;
    for( uint i = 0; i < NumSamples; i++ )
    {
        float2 Xi = Hammersley( i, NumSamples );
        float3 H = ImportanceSampleGGX( Xi, Roughness, N );
        float3 L = 2 * dot( V, H ) * H - V;
        float NoL = saturate( L.z );
        float NoH = saturate( H.z );
        float VoH = saturate( dot( V, H ) );
        if( NoL > 0 )
        {
            float G = G_Smith( Roughness, NoV, NoL );
            float G_Vis = G * VoH / (NoH * NoV);
            float Fc = pow( 1 - VoH, 5 );
            A += (1 - Fc) * G_Vis;
            B += Fc * G_Vis;
        }
    }
    return float2( A, B ) / NumSamples;
}

```

float NdotV, float roughness lut的横纵坐标。

### 最终：

```
float3 ApproximateSpecularIBL( float3 SpecularColor , float Roughness, float3 N, float3 V )
{
    float NoV = saturate( dot( N, V ) );
    float3 R = 2 * dot( V, N ) * N - V;
    float3 PrefilteredColor = PrefilterEnvMap( Roughness, R );
    float2 EnvBRDF = IntegrateBRDF( Roughness, NoV );
    return PrefilteredColor * ( SpecularColor * EnvBRDF.x + EnvBRDF.y );
}

```

