**std::type_info**

是typeid()**运算符**的返回类型,主要用于运行时类型识别，可以判断是否相等（C++20以后移除了!=判定），不可复制构造和赋值。可以调用.name()获取类型的名字。

未定义一些< >=运算符。

before()函数用来比较两个类型的顺序。比如typeid(int).before(typeid(double))返回true。int类型排在double类型前面。这个顺序是编译器决定的。

**typeid()**

返回一个type_info类型的对象的引用。

https://blog.csdn.net/gatieme/article/details/50947821

**std::type_index**

为了解决type_info的一些局限性，如不能赋值。可以理解为封装了一个指向type_info的指针。

也具有.name函数。

本身具有顺序判断，可以用作关联容器（有序或者无序均可）的索引。

---

例：当构造map容器时

type_info

```
struct compare {
    bool operator ()(const type_info* a, const type_info* b) const {
        return a->before(*b);
    }
};

std::map<const type_info*, std::string, compare> m;

void f() {
    m[&typeid(int)] = "Hello world";
}
```

type_index

```
std::map<std::type_index, std::string> m;

void f() {
	m[typeid(int)] = "Hello World";
}
```

type_info是全局对象的一个引用（由编译器创建），所以要const修饰指针，保证对象不被修改。

而type_index做了一个封装，所以不用。



