## assert

**runtime_assert**:

```
#   ifdef NDEBUG
#       define assert(...) ((void)0)
#   else
#       define assert(...) /* implementation-defined */
#   endif

void array_alloc(int n)
{
	assert(n > 0);
	//.......
}

int main() {
	array_alloc(10); // ok!
	array_alloc(0); // assertion failed!
}
```

在定义了NDEBUG这个宏之后。assert不会生效是一个空语句。

运行期断言。

**precompile_assert**

```
#error
```

**compile_assert**

```
static_assert();
template <typename T, typename U> void balabala(T& a, U& b) {
	static_assert(sizeof(a) == sizeof(b));
}
```

模板在编译器期就会展开所以尽量提早assert.模板实例化阶段。

