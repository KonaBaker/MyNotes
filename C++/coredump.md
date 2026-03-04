core dump

core dump是程序异常崩溃的时候，由操作系统自动生成的内存快照文件。将文件传递给helper(systemd-coredump)进行进一步处理。

通常包含，堆栈信息，寄存器状态，cpu信息。

名称通常为core.pid

`sysctl `是用来更改arch linux系统核心参数的命令。

`systemd-coredump` 是和core sump相关的服务或者守护进程

获得core dump文件。存储在systemd-coredump。记录元数据以及文件。

使用coredumpctrl来对coredump文件进行操作。



### gdb手动生成

gdb支持最完整的是c++语言。信息质量取决于：

- 要加-g调试符号
- 编译器本身生成调试信息质量
- 优化程度

生成coredump需要安装gdb包，然后附加进程。

GDB是debugger，在程序崩溃点停住。

```
gdb ./program
(gdb) run
(gdb) generate-core-file
Saved corefile core.2071
(gdb) quit
gdb ./program core.2071
```

之后使用bt(backtrace)定位崩溃点。

