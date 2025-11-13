#!/bin/bash
# 自动拉取并同步笔记
# 适用于多设备笔记同步场景

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取当前分支名
branch=$(git rev-parse --abbrev-ref HEAD)

echo -e "${GREEN}📥 开始同步笔记...${NC}"
echo "当前分支: $branch"
echo "--------------------------------"

# 1. 检查是否有未提交的修改
if ! git diff-index --quiet HEAD --; then
    echo -e "${YELLOW}⚠️  检测到本地有未提交的修改${NC}"
    git status --short
    echo ""
    echo "请选择处理方式："
    echo "  1) 暂存修改 (stash) - 拉取后恢复"
    echo "  2) 提交修改 (commit) - 先提交再拉取"
    echo "  3) 放弃修改 (discard) - 丢弃所有本地修改"
    echo "  4) 取消操作 (abort)"
    read -p "请输入选择 [1-4]: " choice
    
    case $choice in
        1)
            echo "💾 暂存本地修改..."
            git stash push -m "Auto stash before sync @ $(date '+%Y-%m-%d %H:%M:%S')"
            stashed=true
            ;;
        2)
            echo "📝 提交本地修改..."
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            git add .
            git commit -m "local changes from $branch @ $timestamp"
            git push origin "$branch"
            ;;
        3)
            echo -e "${RED}⚠️  确认要丢弃所有本地修改吗？(y/N)${NC}"
            read -p "> " confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                git reset --hard HEAD
                git clean -fd
                echo "✅ 本地修改已丢弃"
            else
                echo "❌ 操作已取消"
                exit 0
            fi
            ;;
        4|*)
            echo "❌ 操作已取消"
            exit 0
            ;;
    esac
fi

# 2. 获取远程最新信息
echo "🔍 获取远程更新..."
git fetch origin

# 3. 更新 main 分支
echo "📥 更新 main 分支..."
if [ "$branch" = "main" ]; then
    # 如果当前就在 main 分支
    git pull origin main --rebase
else
    # 如果在其他分支，切换到 main 更新后再切回
    git checkout main
    git pull origin main --rebase
    git checkout "$branch"
fi

# 4. 更新当前工作分支
if [ "$branch" != "main" ]; then
    echo "📥 更新 $branch 分支..."
    
    # 检查远程是否有这个分支的更新
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse origin/"$branch" 2>/dev/null || echo "")
    
    if [ -n "$REMOTE" ]; then
        if [ "$LOCAL" != "$REMOTE" ]; then
            echo "🔄 远程有更新，拉取中..."
            git pull origin "$branch" --rebase
        else
            echo "✅ $branch 已是最新"
        fi
    else
        echo "ℹ️  远程没有 $branch 分支"
    fi
    
    # 5. 将 main 的更新合并到当前分支
    echo "🔀 合并 main 的更新到 $branch..."
    if git merge main --no-edit; then
        echo "✅ 合并成功"
    else
        echo -e "${RED}❗ 合并冲突！请手动解决冲突后运行：${NC}"
        echo "   git add ."
        echo "   git commit -m 'resolve merge conflicts'"
        exit 1
    fi
fi

# 6. 如果之前暂存了修改，现在恢复
if [ "$stashed" = true ]; then
    echo "📂 恢复暂存的修改..."
    if git stash pop; then
        echo "✅ 修改已恢复"
    else
        echo -e "${YELLOW}⚠️  恢复修改时发生冲突，请手动处理${NC}"
        echo "   暂存的内容仍保留在 stash 中"
        echo "   可以运行: git stash list 查看"
    fi
fi

echo ""
echo -e "${GREEN}✅ 笔记同步完成！${NC}"
echo "当前状态："
git status --short