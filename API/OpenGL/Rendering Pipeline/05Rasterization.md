> **Rasterization** is the process whereby each individual [Primitive](https://wikis.khronos.org/opengl/Primitive) is broken down into discrete elements called [Fragments](https://wikis.khronos.org/opengl/Fragment), based on the sample coverage of the primitive.

光栅化是将每个独立的图元，根据其采样覆盖率，分解为称为片元的离散元素的过程。

**sample coverage**

一个像素不一定只有一个采样点，比如开启MSAA后，一个像素就会有多个采样点。

光栅化会检查图元是否覆盖这些sample。

coverage就是覆盖率。

