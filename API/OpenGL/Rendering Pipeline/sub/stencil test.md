# stencil test

> The **Stencil Test** is a per-sample operation performed after the Fragment Shader. The fragment's stencil value is tested against the value in the current stencil buffer; if the test fails, the fragment is culled.

## stencil buffer

stencil buffer是一个image(正如在framebuffer中的stencil attachment所说"the image成为stencil buffer")。

- default framebuffer有一个默认stencil buffer。
- user-defined FBO可以attach一个。

image format是stencil的。

如果一个framebuffer没有stencil buffer，stencil test就相当于关闭。

## fragment stencil value

每个fragment有一个stencil value，是uint

## stencil test

开启`glEnbale(GL_STENCIL_TEST)`

设置`void glStencilFuncSeparate(GLenum face, GLenum func, GLint ref, GLuint mask);`

$$ F_m=ref~\&~mask $$
$$ D_m=stencil\_value~\&~mask $$  stencil buffer中的值经过mask的结果

mask的意义是stencil中哪些bit参与测试。

face指定这套设置给front-face用还是back-face用。

如果没有face的图元，则默认是正面。

**Note：** 在同一个DC中，每个fragment的相同face应用的规则/ref都是相同的

- $F_m~FUNC~D_m $form

| Enum       | Test          | Enum        | Test          |
| ---------- | ------------- | ----------- | ------------- |
| GL_NEVER   | Always fails. | GL_ALWAYS   | Always passes |
| GL_LESS    | <             | GL_LEQUAL   | ≤             |
| GL_GREATER | >             | GL_GEQUAL   | ≥             |
| GL_EQUAL   | =             | GL_NOTEQUAL | ≠             |

## stencil opertaions

决定在经过test之后如何修改stencil buffer中的值。如果stencil test disable了，此步骤也不会进行。

stencil test失败，那么这个fragment就会discard，但是在early test中仍然可以去更新stencil buffer。

`void glStencilOpSeparate(GLenum face, GLenum sfail, GLenum dpfail, GLenum dppass);`

sfail\apfail\dppass对应三种情况。

| Enum    | Operation                                                    | Enum         | Operation                                                   |
| ------- | ------------------------------------------------------------ | ------------ | ----------------------------------------------------------- |
| GL_KEEP | Don't modify the current value (default)                     | GL_INVERT    | Invert the current value                                    |
| GL_ZERO | Set it to zero                                               | GL_REPLACE   | Replace with the masked fragment value                      |
| GL_INCR | Increment the current value, saturating1 if it would overflow | GL_INCR_WRAP | Increment the current value, wrapping if it would overflow  |
| GL_DECR | Decrement the current value, setting to zero if it would underflow | GL_DECR_WRAP | Decrement the current value, wrapping if it would underflow |

---

例子：shadow volume

