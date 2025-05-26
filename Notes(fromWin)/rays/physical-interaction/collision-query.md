相关文件：

- 

#### ocean-pass 

对应的collision_query_pass在ocean_pass中初始化。

```setup_wave_related_parameters_for_collision```设置有关波浪的参数。

```setup_shoreline_wave```设置有关shoreline_wave的参数。

之后设置一些其他参数（计算着色器参数、reverse-z等)

调用```set_buffer_then_update_queries```

#### simple-collision-query



```update_query_points```



```retrieve_results```



```calculate_velocities```



```set_buffer_data_for```



```refresh_buffer```



**以下是向外暴露的函数**

---

```query```

按顺序执行update_query_points - > retrieve_results -> caculate_velocities，并记录相关状态，最后返回result.

```set_buffer_then_update_queries```

如果当前帧有查询点，按顺序执行set_buffer_data_for - > refresh_buffer.

```retrieve_succeed```

检查结果查询状态

```velocity_retrieve_succeed```

检查速度结果的查询状态

#### shader

```
for (int i = 0; i < 4; i++) {
    displacement = sample_displacement(undisplacement_xz) * wave_opacity;
vec2 error = (undisplacement_xz + displacement.xz) - data.xy;
undisplacement_xz -= error;
}
```

>根据波浪数据，进行迭代逼近。
>
>(1)我们可以通过A1计算得到A2点的偏移数据，A2点与初始点A1水平偏移为0.6。
>
>(2)根据水平偏移0.6，这一次将计算点A1水平移动−0.6得到B1=(0.4,0) 去计算偏移，计算得到B2，其与初始点A1水平偏移为−0.4。 
>
>(3)根据水平偏移−0.4，这一次将计算点B1水平移动0.4得到C1=(0.8,0) 去计算偏移，计算得到C2，也就是最后的所需结果。

![image-20241209194831600](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20241209194831600.png)

最后输出，偏移和法线的数据。

```
imageStore(query_results, ivec2(id * 2, 0), vec4(displacement, 0.0));
imageStore(query_results, ivec2(id * 2 + int(data.w + 0.1), 0), vec4(normal, 0.0));
```

