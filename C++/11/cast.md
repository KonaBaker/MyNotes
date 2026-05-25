### const_cast

可用于添加或者移除const。本质上是修改type system对一块内存的**访问权限认知**，不会产生任何副本，不会移动任何内存。编译器不会为其产生额外的机器码，只存在于**类型检查阶段**。

**例1**：包装旧api

```c++
void legacy_c_api(char* buf);
void modern_wrapper(const std::string& s) {
	legacy_c_api(const_cast<char*>(s.c_str()));
}
```

**例2**：成员函数版本复用

```c++
class TextBlock {
public:
    const char& operator[](std::size_t position) const {
        // 假设这里有非常多的代码
        return text[position];
    }

    char& operator[](std::size_t position) {
        return const_cast<char&>(static_cast<const TextBlock&>(*this)[position]);
    }
private:
    std::string text;
};
```

**Notes**

对原始变量使用是ub:

```c++
const int x = 42;
int* p = const_cast<int*>(&x);
*p = 100;  // ❌ UB
```

只能对底层对象本身不是const，但是通过某个“接口”(使用了const)表达了不修改的意图。

### static_cast

安全的类型转换。**编译时进行类型检查**。用于处理类型之间的隐式转换（int->float等)。

转型目标如果是**值类型**，则会构造一个该类型的临时对象，会产生**副本**。转型为指针或者引用的时候不会产生fu ben

### reinterpret_cast

不看语义，只看内存布局。把一块内存的bit重新解释为另一种类型，不产生副本，实质上没有转换，是最不安全的一种，应当尽量避免使用。

**例1**：json流解读

```c++
struct PacketHeader {
    uint16_t magic;
    uint16_t length;
    uint32_t checksum;
};
void parse(const uint8_t* buf) {
    const PacketHeader* hdr = reinterpret_cast<const PacketHeader*>(buf);
}
```

### dynamic_cast

运行时转型，通过**RTTI**（运行时类型信息）遍历继承树，判断转换是否合法，要求有vtable。专门用于处理多态性。可以进行各种转型（向上、向下和横向）

**例1**：横向转换

```c++
struct Flyable { virtual void fly() {} };
struct Duck : Animal, Flyable {};

Animal* a = new Duck;
// 从 Animal* 横跨到完全不相关的 Flyable*
Flyable* f = dynamic_cast<Flyable*>(a);  // ✅ 运行时检查继承树，成功
```

**例2**：

```c++
struct Animal  { virtual ~Animal() {} };
struct Dog     : Animal { void bark() {} };
struct Cat     : Animal { void meow() {} };
struct Labrador: Dog    { void fetch() {} };

Animal* a = new Labrador;
if (Dog* d = dynamic_cast<Dog*>(a)) {
    d->bark();          
}
```





