https://zhuanlan.zhihu.com/p/700432461

https://catlikecoding.com/unity/tutorials/procedural-meshes/cube-sphere/

也是proland中地形渲染地球的方法。

一些其他球体渲染算法：

- uv sphere

  将$x,y,z$映射到球坐标系$\phi,\theta$

  通过双重循环遍历$\phi,\theta$构造顶点。
  
  但是构造出来的顶点有一个缺点，就是在南北极点变得密集，三角形细长。

- 二十面体细分球

  （后续补充）



立方体球：



