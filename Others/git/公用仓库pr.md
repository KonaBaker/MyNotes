首先要fork公用仓库到一个自己的仓库。

然后设置公用仓库为upstream进行跟踪。

```
git remote add upstream <repo-addr>
```

然后在自己的仓库进行相关操作（add,commit, push)就可以了，当提交的时候会自动在公有仓库和自己仓库出现创建合并请求。

