## res-01

### Texture

``` resource::Texture color; ```

- ``` enum struct Kind ``` 指定纹理类型
- ``` enum struct Format ``` 指定纹理格式
- ``` max_mip_level ``` <1 生成全mipmaps
- ``` multisample ``` >1 开启
- ``` save```调用imge的save，将数据写入文件
- ```copy_to_buffer```　

### Image_Layout

u8x1234 u16x1234 u32x1234 f32x1234

``` component_count ```有几个部分 u8x3 就是3

```bytes_per_component``` u8就是一个字节 u16两个

``` bytes_per_pixel``` ```bytes_per_component × component_count```

```Image_Vertical_Flip```

### Image

```
int w;
int h;
buffer_type buf;
Image_Layout il;
std::string src;
```

宽、高、布局、

源文件和buffer类型（都是字符串）

写入文件：

```wirte```本质调用save

```save```获取image_writer的实例调用writer的write

```builtin_image_writers::write()``` 

根据是否翻转调用　stbi_flip_vertically_on_write

调用 stbi_write写入image_buffer

从文件中读取：

```load```　本质调用stbi_load

### Image Binding

为了着色器的imageStore和imageLoad设置绑定，配合set_uniform一起使用。

``` enum struct Shader_Access ``` 指定访问权限：

- load_and_store
- load_only
- store_only

接收Texture参数，还有默认的layer,mip_level参数将其转换为image数据供使用。

例如：``` post_process_pass.set_uniform("dx_dz_dy_dxz", resource::Image_Binding::load_only(io.in_dx_dz_dy_dxz));```

### Effect_Resource_Provider

fxg中如果需要自定义resource的类型则需要继承这个接口，并实现一系列虚函数供引擎调用。

``` parse_declaration``` 返回一个默认的构造函数

``` create_resource {return declaration;}```

``` format_declaration {return {};}```

``` resource_ref_of {return std::ref(nonstd::any_cast<T&>(resource));}```

​	std::ref用于取某个变量的引用，解决一些传参问题。因为有一些传参是拷贝的，必须显式调用来绑定引用。

 ``` resource_ptr_of {return &nonstd::any_cast<T&>(resource);}```

在实现接口以后还需要使用Effect_Resource_Provider_Registry进行注册：

```
auto register_T_Name() -> void
{
    auto& reg = resource::Effect_Resource_Provider_Registry::instance();
    reg.add<T_Provider>("T name");
}
```





