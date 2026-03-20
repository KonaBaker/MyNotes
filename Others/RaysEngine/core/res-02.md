## res-02

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





