## chapter 1

### 01 federation

c++是一个同时支持过程、面向对象、泛型、元编程的语言。可以认为其具有多个sublanguage。

- C。指针、数组等传承自C语言。但是没有模板、重载等等较为高级的特性。高效编程
- Object-Oriented C++。面向对象等特性，封装、继承、多态等等。
- Template C++。这是 C++的泛型编程部分。TMP:模板元编程。
- STL。是一个模板库。算法、容器等等。

每种sublanguage的切换，需要更改自己的**”高效编程守则”**，例如：在使用C的时候，传值通常比传引用更高效。面向对象C++传引用通常更好。

### 02 use constexpr/enum/inline but #define

**使用constexpr**

```c++
#define ASPECT_RATIO 1.653
```

应替代为

```c++
constexpr auto aspect_ratio = 1.653;
```

因为`#define`并不被视作语言的一部分，编译器看不到，而是由预处理器来进行处理。也就是说其并不会被记录在symbol table内。

对于**class专属常量**

`#define`无法定义这个，因为其不重视定义域，无法封装。需要使用

```c++
class GamePlayer {
public:
    static constexpr auto numTurns = 5; // 声明而非定义
};
```

**使用enum**

也可以使用

```c++
class GamePlayer {
public:
    enum { numTurns = 5 };
};
```

enum hack pros:

- 其更像#define，对于constexpr来说是可以取地址的，但是enum就不可以。
- enum绝对不会导致非必要的内存分配，constexpr绝大部分情况也是这样，但是少数编译器或使用pointer/reference的时候，可能会有额外的存储空间

**使用inline**

对于宏定义的函数，有着很多缺点，应当使用template inline

```c++
template<typename T>
inline void CallWithMax(const T& a, const T& b) {
    f(a > b ? a : b);
}
```

### 03 use const

对于常量，如果只想让他只读，那么应该指定const。

对于迭代器

```c++
const std::vector<int>::iterator iter = vec.begin();    // 迭代器不可修改，数据可修改
std::vector<int>::const_iterator iter = vec.begin();    // 迭代器可修改，数据不可修改
```

面对函数声明时，如果你不想让一个函数的结果被无意义地当作左值，请使用const返回值：

```cpp
const Rational operator*(const Rational& lhs, const Rational& rhs);
```

例如：

`a * b = c`这种

**成员函数**

对成员函数本身声明cosnt，可以让我们作用于const对象。在其中不可更改非static的成员。

```c++
class TextBlock {
public:
    const char& operator[](std::size_t position) const {    // const对象使用的重载
        return text[position];
    }

    char& operator[](std::size_t position) {                // non-const对象使用的重载
        return text[position];
    }

private:
    std::string text;
};
```

```c++
void Print(const Textblock& ctb) {
    std::cout << ctb[0];            // 调用 const TextBlock::operator[]
}
```

bitwise constness，是编译器的态度，但是比如指针，我们只确保了指针不会改变，但是无法确保指针内容不会被客户端（调用函数返回这个指针）进行改变。（这个函数其实不应该被声明为const）。

logical constness。一个const成员函数可以修改某些内容：需要声明mutable

```c++
class CTextBlock {
public:
    std::size_t Length() const;

private:
    char* pText;
    mutable std::size_t textLength;
    mutable bool lengthIsValid;
};

std::size_t CTextBlock::Length() const {
    if (!lengthIsValid) {
        textLength = std::strlen(pText);    // 可以修改mutable成员变量
        lengthIsValid = true;               // 可以修改mutable成员变量
    }
    return textLength;
}
```

**避免重复**

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

### 04 initialize first

在我们使用一个对象之前，应该对其进行初始化。但是要区别初始化以及赋值。

在一个构造函数内部，进行的是赋值动作，而不是初始化，初始化动用发生在进入构造函数本体之前。

- 可以在成员定义的时候赋初值
- 也可以使用初始化列表（初始化次序按照声明顺序，而不是列表顺序）

**non-local static初始化次序**

static对象包括：（从构造开始，到程序结束时析构）

- global对象
- namespace内的对象
- class/file作用域内被声明为static的对象
- **local static**: 函数内声明的static对象，调用函数的时候初始化。（同一文件内，会保证按定义顺序初始化）

C++ 对于定义于不同编译单元内的全局静态对象（non-local static)的初始化相对次序并无明确定义，因此，以下代码可能会出现使用未初始化静态对象的情况：

```c++
// File 1
extern FileSystem tfs;

// File 2
class Directory {
public:
    Directory() {
        FileSystem disk = tfs;
    }
};

Directory tempDir;
```

在上面这个例子中，你无法确保位于不同编译单元内的`tfs`一定在`tempDir`之前初始化完成。

**方案一**

这个问题的一个有效解决方案是采用 **Meyers' singleton**，将全局静态对象转化为局部静态对象(local static)：将non-local static对象搬到一个自己的专属函数内，函数返回一个reference指向所包含的对象，然后通过函数来访问这些对象。这样就保证在获得reference的时候会历经一个初始化

```c++
FileSystem& tfs() {
    static FileSystem fs;
    return fs;
} // c++ 11之后是线程安全的。

Directory& tempDir() {
    static Directory td;
    return td;
}
```

**方案二**

设计上**依赖注入**

```c++
// 不依赖全局状态，通过构造函数注入依赖
class Directory {
public:
    explicit Directory(FileSystem& fs) : fs_(fs) {} // 依赖注入
    
private:
    FileSystem& fs_;
};

// 在 main() 中，初始化顺序完全由程序员控制
int main() {
    FileSystem fs;       // 1. 先构造 fs
    Directory dir(fs);   // 2. 再构造 dir，次序明确
}
```

