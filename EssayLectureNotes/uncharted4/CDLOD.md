# CDLOD

## introduction

主要是解决了不同LOD之间的平滑过渡问题。并且由于其网格是规则的，对数据结构和并行运算比较友好。

之前的lod算法大部分都是cpu-based的.

固定网格渲染，和clipmap一样在vs中通过高度图数据对顶点进行偏移。

通过四叉树结构和一种新的lod系统来管理。

通过使用细分，可以充分利用shader model 5.0的最新特性。

### lod function

clipmap算法的一个显著缺点是其lod是基于二维的。

直接使用摄像机到顶点的3d距离。

计算简单且稳定。

### lod transition

t-junction问题：

在不同lod之间使用一些“缝合”。而这些“缝合”除了会增加渲染开销，还会增加artifacts

或者导致一些半透明问题。不同Lod层级的过渡也会导致popping。

而cdlod就解决了这些问题。no seams no artifacts

### data organization and streaming

## algorithm implementation

### overview

将一个高度图组织到quadtree中，在不同的lod等级选择正确的quadtree节点。

实际渲染的时候，通过一个唯一的网格(base grid)（通过缩放变形）来渲染选定节点覆盖的区域，在vs中读取高度图并偏移。通过实例化的方式绘制。

quadtree一旦创建就不会改变。

每个节点包含四个子节点，和最大最小高度值。

在streaming中所有的其他数据都是隐式生成的，内存使用更少，但略微复杂一些。

### quadtree and node selection

渲染的第一步就是进行节点选择。每一帧都需要进行。

![image-20260115143440805](./assets/image-20260115143440805.png)

树的深度就对应lod的某一层级

四叉树的每一个结点都必须使用相同数量的三角形来进行渲染。

### LOD distances and morph areas

为了确定在哪里选择哪些节点，会预计算每个LOD层覆盖的距离。

range array:

![image-20260115161620436](./assets/image-20260115161620436.png)

每一个距离是上一级的两倍。每一个Lod之间会有一个morph area,这个area覆盖了最后15%~30%的距离。

<img src="./assets/image-20260113152723949.png" alt="image-20260113152723949" style="zoom:60%;" />

### quadtree traversal and node selection

从最顶层

```c++
// Beginning from the LODLevelCount and going down to 0;
// lodLevel 0 is the highest detailed level.
bool Node::LODSelect(int ranges[], int lodLevel, Frustum frustum)
{
    if (!nodeBoundingBox.IntersectsSphere(ranges[lodLevel]))
    {
        // No node or child nodes were selected; return false so that our
        // parent node handles our area.
        return false;
    }

    if (!FrustumIntersect(frustum))
    {
        // We are out of frustum, select nothing but return true to mark
        // this node as having been correctly handled so that our parent
        // node does not select itself over our area.
        return true;
    }

    if (lodLevel == 0)
    {
        // We are in our LOD range and we are the last LOD level.
        AddWholeNodeToSelectionList();
        return true; // We have handled the area of our node.
    }
    else
    {
        // We are in range of our LOD level and we are not the last level.
        // If we are also in range of a more detailed LOD level, then some
        // of our child nodes will need to be selected instead.
        if (!nodeBoundingBox.IntersectsSphere(ranges[lodLevel - 1]))
        {
            // We cover the required lodLevel range.
            AddWholeNodeToSelectionList();
        }
        else
        {
            // We cover the more detailed lodLevel range: some or all of our
            // four child nodes will have to be selected instead.
            foreach (childNode)
            {
                if (!childNode.LODSelect(ranges, lodLevel - 1, frustum))
                {
                    // If a child node is out of its LOD range, we need to
                    // make sure that the area is covered by its parent.
                    AddPartOfNodeToSelectionList(childNode.ParentSubArea);
                }
            }
        }

        return true; // We have handled the area of our node.
    }
}
```

在选择的过程中，我们要存储位置，size，lod level等等信息用于之后的渲染。

