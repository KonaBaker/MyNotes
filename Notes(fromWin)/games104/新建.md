## 架构图

架构图我不太熟悉

可能是描述各个层次之间的关系？应该没有什么特别的规范。

<img src="C:\Users\Administrator\Downloads\IMG_2715.JPG" alt="IMG_2715" style="zoom: 25%;" />

## 交互关系图

应该是用来描述对象间消息的交互。uml应该叫通信图。注：

**时序图（顺序图）也是交互关系的一种，但是其具有时间上的关系和生命周期。**

主要元素有三种：对象、消息和链

<img src="C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240825180503203.png" alt="image-20240825180503203" style="zoom:67%;" />

对象：方块表示，可以是抽象的高层系统。

链：单向或者双向表示，也可以指向自身。

消息：短箭头表示，可以使具体的公式也可以是抽象向的文字。



## 接口示意图

**应该指的是组件图**：

组件就是系统设计的一个模块化部分，隐藏内部实现，对外提供一组接口：![image-20240825171251209](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240825171251209.png)

有具体两种接口：![image-20240825171359355](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240825171359355.png)

当两者距离较远的时候可以用虚线表示：![image-20240825175747789](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240825175747789.png)





## 数据流通图

数据流通图应该不属于uml的一部分。是软件设计时候的数据流图。主要表示系统间的数据流向。

![image-20240825181558652](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240825181558652.png)

实线+箭头表示数据流向。

周边的矩形表示外部实体或者组织，例如课程、老师。引擎包括工程师、客户等等。

圆角矩形和数字表示开发的系统，或者运行的任何功能，或者操作等等。

右侧开口的矩形表示数据库，或者任何可以进行数据存储的东西，例如引擎的场景图节点。

箭头上写传递的数据。

## 系统部署图

uml中的部署图。定义系统中软硬件的物理体系结构，包括运行环境等。

例子：<img src="C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240825175009325.png" alt="image-20240825175009325" style="zoom: 67%;" />

主要包括元素之间节点和节点之间的关联联系

![image-20240825175200892](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240825175200892.png)

节点表示：![image-20240825175231139](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240825175231139.png)

代表一个物理对象或者一个计算资源。一般就分为processor和device两类，

processor：代表具有计算能力的节点比如 主板、服务器、或者引擎内部计算等

device：代表一些输入输出设备、客户端或者一些外部链接的设备等。



在对应名字上加上<<processor>>或者<<device>>即可

关系一般用实线表示。一般不进行命名，也可以加上<<>>来进行一些简单说明。



## 基本结构图/信息结构图/功能结构图

一般来说上边的类图，组件图都属于结构图，我不太理解这里的结构图是特指什么？uml中没有这样的表述。

如果用来表示一些功能或者操作结构的可能是用例图？

<img src="C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240825182359477.png" alt="image-20240825182359477" style="zoom: 80%;" />

具体可以看[UML--用例图详解-CSDN博客](https://blog.csdn.net/cold___play/article/details/100824261)

包括参与者、关系和用例。

用例就是一系列活动的集合

关系：

![image-20240825182743944](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240825182743944.png)



