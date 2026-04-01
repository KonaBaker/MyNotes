`std::ifstream`只读（input file stream）

`std::ofstream`只写（output file stream）

`std::fstream`读写皆可

采取了RAII，不需要手动析构，不需要对file进行close。自动调用open和close。

```c++
std::ifstream file(filename, openmode | openmode | ...);
```

**状态判断** operator bool()

```c++
if(!file) {
    throw std::runtime_error("...");
}
```

**格式化读取** operator >>

```c++
while (file >> x) {
	std::cout << x << ' ';
}
```

会自动跳过空格和换行。

**读取整个文件**

- `std::istreambuf_iterator`

```c++
std::string content(
    std::istreambuf_iterator<char>(file),
);
```

- `std::ostringstream`

```c++
std::ostringstream oss;
oss << file.rdbuf();          // rdbuf() 返回底层缓冲区指针
std::string content = oss.str();
```

**openmode**

- ios::in 读（ifstream 默认

- ios::out 写（ofstream 默认

- ios::binary 二进制模式，不做换行转

- ios::app 追加到文件末

- ios::trunc 打开时清空（ofstream 默认）

- ios::ate 打开后定位到末尾

**定位**

单位是字节

- seek{g/p}

跳到指定位置

- tell{g/p}

返回当前位置

**二进制数据**

read/write

`read(char* buf, streamsize count)`

`write(const char* buf, streamsize count)`

读的是原始字节，需要搭配`reinterpret_cast`使用

**为什么是char?**

因为char刚好是一个字节的大小，这里的含义char就是字节。

static_cast负责有意义的转换。

reinterpret_cast更多是如何看内存？



C++17有了std::byte,但是其只允许位操作，用于表达“操作原始内存”这一意图。

但是read仍然只接收char*