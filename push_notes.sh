#!/bin/bash
# 自动同步 Typora 笔记并合并到 main 分支
# 适用于 Arch Linux + GitHub CLI (gh)
# 使用前请确保 gh 已经登录： gh auth login

# 获取当前分支名
branch=$(git rev-parse --abbrev-ref HEAD)
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
msg="update notes from $branch @ $timestamp"

# 显示信息
echo "📝 当前分支: $branch"
echo "💬 提交信息: $msg"
echo "--------------------------------"

# 执行提交与推送
git add .
git commit -m "$msg"
git push origin "$branch"

# 如果当前不是 main，就创建并合并 Pull Request
if [ "$branch" != "main" ]; then
    echo "🔀 创建并合并 Pull Request..."
    
    # 检查是否已有同名 PR（避免重复创建）
    existing_pr=$(gh pr list --head "$branch" --base main --json number --jq '.[0].number')

    if [ -z "$existing_pr" ]; then
        gh pr create --base main --head "$branch" --title "$msg" --body "Auto sync from $branch"
    else
        echo "⚠️ 已存在 PR #$existing_pr，跳过创建"
    fi

    # 合并 PR（如果存在）
    gh pr merge --auto --squash || echo "❗合并失败，请手动检查 PR"
    git pull origin main:main
    git pull origin "$branch"
    git reset --hard origin/main
    git push --force-with-lease origin "$branch"
fi

echo "✅ 笔记已同步完成！"
