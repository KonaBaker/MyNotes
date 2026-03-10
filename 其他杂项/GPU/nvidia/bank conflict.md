

# bank conflict

https://zhuanlan.zhihu.com/p/659142274

**概念**

存储不是一个整体，而是划分为多个bank(存储体)，多个线程可以并行对bank进行访问。**bank 的目的不是“把内存分区方便存放”，而是“让连续访问能并行”。**

所以连续的内存一般 都是跨bank的。 **交叉编址 / 交错存放**。bank内部也是有内偏移的。 （连续访问的优化方式）

<img src="./assets/v2-448e786124b33e683ba2c24ce27267b1_1440w.jpg" alt="img" style="zoom:200%;" />

理想情况访问就是stride=1,连续反问，并行访问。

- 当多个线程同时访问一个bank的时候就会触发bank conflict.

- 会由硬件把内存读写请求，拆分成 **conflict-free requests**，进行顺序读写 
- 多个线程读同一个数据时，仅有一个线程读，然后broadcast到其他线程 
- 多个线程写同一个数据时，仅会有一个线程写成功（不过这里没有提及是否会将写操作执行多次（即a. 多个线程写入，最后一个线程随机写完; or b. 随机挑选一个线程执行写入），具体流程存疑）

数据地址到bank的映射规则：

物理地址 = （bank, offset) = address

$ bank=(\frac{address}{word\_size})\mod count $

$ offset = (\frac{address}{word\_size}) / count $

这里的word_size就是只连续多长的数据映射到一个bank上，也就是交叉编址的stride(和后面的stride不是一个)。

**典型案例：**

矩阵按行存储，按列访问。

```C++
shared float tile[32][32];   // 容易在按列访问时冲突
shared float tile[32][33];   // 常用来避免冲突
```

第一个矩阵就是一个stride = 32的访问，也就是32-way conflict

stride mod count和 count 有公因子且不为1的时候，就会出现conflict。



**导致**：memory吞吐下降，延迟变高，kernel的运行变慢

$O(N/B)$ ->  $ O(M * N/B) $

N是从访问此处 B是划分的count数量，M是同一个bank的内存访问请求数量。



**解决办法**：

- 广播，比如多个线程都要访问某一个bank，硬件可以广播，把数据发给所有线程。**只适用于读写同一个bank中相同地址的数据)**
- 尽量按照stride = 1 或调整为其他stride进行访问
- 使用padding进行填充
- 改内存排布，和改代码访问顺序一样，就是为了做好映射关系的分布。



