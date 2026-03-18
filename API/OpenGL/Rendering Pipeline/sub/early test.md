early test

被很多gpu支持的一种feature（会有专门的硬件单元优化）



`layout(early_fragment_tests) in;`

强制开启（显式启用），如果fragment即使在FS中被discard,depth/stencil buffer仍然是可以被写入的。



- “depth test fails 或者 stencil test fails 都会导致 fragment discard，但是 stencil buffer 仍然可能因为 glStencilOpSeparate 的设置被写入。”
- “depth test fails，那么 depth buffer 就不会被写入。”
- “如果 depth test 和 stencil test 在 FS 后执行，如果 FS 中 discard 了，后面的 test 也不会执行，depth/stencil buffer 也不会被写入。”

