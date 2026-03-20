```
git rebase -i <commit-hash>^
// 编辑器将pick改为reword
// 保存退出
// 更改msg
// 保存退出
git push origin <branch-name> --force-with-lease //覆盖远程分支
```

即用新的i个提交，覆盖远程i个提交。