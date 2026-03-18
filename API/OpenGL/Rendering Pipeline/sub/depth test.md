# depth test

- if fails，fragment discard
- if passes, update depth buffer(除非关闭写入)

## depth buffer

同stencil buffer

## fragment depth value

这个值有window-space z(gl_FragCoord.z)或者写入的gl_FragDepth决定

## depth test

`glEnable(GL_DEPTH_TEST)`

`void glDepthFunc(GLenum func);`

fragment's depth FUNC buffer's depth

| Enum       | Test          | Enum        | Test          |
| ---------- | ------------- | ----------- | ------------- |
| GL_NEVER   | Always fails. | GL_ALWAYS   | Always passes |
| GL_LESS    | <             | GL_LEQUAL   | ≤             |
| GL_GREATER | >             | GL_GEQUAL   | ≥             |
| GL_EQUAL   | =             | GL_NOTEQUAL | ≠             |

## early-z

【细见early-z或early-test】