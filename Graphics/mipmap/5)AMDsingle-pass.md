# one pass mipmap（SPD)

https://gpuopen.com/fidelityfx-spd/

> AMD FidelityFX™ Single Pass Downsampler (SPD) provides an AMD RDNA™  architecture-optimized solution for generating up to 12 MIP levels of a  texture.

每个线程组先把自己负责的一个 `64×64` 输入 tile 一路缩到 `1×1`，产出前 6 级 mip；然后所有线程组通过一个全局原子计数器竞争，只有“最后完成”的那个线程组继续接手，把由各线程组产出的那张更小的图再缩到最终 `1×1`。这样就能在一次 compute dispatch 里做完整条 mip 链.

**Notes**:

1) **对NPOT的情况无法处理**，需要自己做border handline，也就是说只针对大尺寸的2次方纹理有很好的处理。
2) wave operations = subgroup shuffle
3) LDS = shared memory

一次dispatch最多处理12级mipmap。

一个group 256个线程。

每个group处理自己划分的64x64的tile。

前六级：处理完之后产生1x1的结果，通过shared memory共享，然后barrier。

后六级：找到最后一个完成的线程组处理剩下的不一定是六级。

**对于非64的整倍数问题，需要自行处理“边角料”**

SPD!=nvpro 6-level *2,SPD是一种前六级分布式完成后面跨组同步。

