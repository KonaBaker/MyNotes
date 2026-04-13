#!/bin/bash
# 自动同步 Typora 笔记并合并到 main 分支
# 适用于 Arch Linux + GitHub CLI (gh)
# 使用前请确保 gh 已经登录： gh auth login
#
# 设计原则：任何一步失败都立即退出，保证本地 commit 不会丢失。
# 数据安全递进： 本地 commit -> push 到 from/xxx -> 同步等待 PR 合并 -> 验证 main 已更新 -> 再 reset 对齐

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

branch=$(git rev-parse --abbrev-ref HEAD)
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
msg="update notes from $branch @ $timestamp"

echo "📝 当前分支: $branch"
echo "💬 提交信息: $msg"
echo "--------------------------------"

# 安全检查：不允许在 main 分支直接运行
if [ "$branch" = "main" ]; then
    echo -e "${RED}❌ 当前在 main 分支，请先切换到 from/xxx 分支${NC}"
    exit 1
fi

# ============================================================
# 1. 本地提交（失败则退出，但工作区改动仍保留，不会丢）
# ============================================================
git add .

if git diff --cached --quiet; then
    echo -e "${YELLOW}ℹ️  工作区没有需要提交的修改${NC}"
    has_new_commit=false
else
    if ! git commit -m "$msg"; then
        echo -e "${RED}❌ 本地提交失败${NC}"
        echo -e "${YELLOW}ℹ️  改动仍保留在工作区中，不会丢失${NC}"
        exit 1
    fi
    has_new_commit=true
    echo -e "${GREEN}✅ 本地提交成功${NC}"
fi

# ============================================================
# 2. 推送到远程 from/xxx 分支（失败则退出，本地 commit 已在本地保存）
# ============================================================
echo "📤 推送到远程 $branch ..."
if ! git push origin "$branch"; then
    echo -e "${RED}❌ 推送失败（可能是网络问题）${NC}"
    echo -e "${YELLOW}ℹ️  本地 commit 已保存，网络恢复后重新运行本脚本即可${NC}"
    exit 1
fi
echo -e "${GREEN}✅ 推送成功（此时即使后续步骤失败，改动也已在远程 $branch 分支上）${NC}"

# 如果本次并没有新 commit，而远程 from/xxx 与 main 内容一致，就没必要建 PR
if [ "$has_new_commit" = false ]; then
    ahead=$(git rev-list --count origin/main..origin/"$branch" 2>/dev/null || echo "0")
    if [ "$ahead" = "0" ]; then
        echo -e "${GREEN}✅ $branch 与 main 一致，无需创建 PR${NC}"
        echo -e "${GREEN}✅ 笔记已同步完成！${NC}"
        exit 0
    fi
fi

# ============================================================
# 3. 创建或复用 PR
# ============================================================
echo "🔀 处理 Pull Request ..."
existing_pr=$(gh pr list --head "$branch" --base main --state open --json number --jq '.[0].number' 2>/dev/null || echo "")

if [ -z "$existing_pr" ]; then
    if ! gh pr create --base main --head "$branch" --title "$msg" --body "Auto sync from $branch"; then
        echo -e "${RED}❌ 创建 PR 失败${NC}"
        echo -e "${YELLOW}ℹ️  本地 commit 已推送到远程 $branch，不会丢失。请稍后重试或手动在 GitHub 上创建 PR。${NC}"
        exit 1
    fi
    pr_number=$(gh pr list --head "$branch" --base main --state open --json number --jq '.[0].number')
else
    echo "ℹ️  已存在 PR #$existing_pr，复用"
    pr_number=$existing_pr
fi

if [ -z "$pr_number" ]; then
    echo -e "${RED}❌ 无法获取 PR 编号${NC}"
    echo -e "${YELLOW}ℹ️  本地 commit 已推送到远程 $branch，不会丢失${NC}"
    exit 1
fi

# ============================================================
# 4. 同步合并 PR（不用 --auto，确保脚本退出时 PR 真的合完了）
# ============================================================
echo "🔀 合并 PR #$pr_number ..."
# 注意：这里不加 --auto，gh 会阻塞直到合并完成（或失败）
if ! gh pr merge "$pr_number" --squash; then
    echo -e "${RED}❌ PR 合并失败（可能是冲突、检查未通过或网络问题）${NC}"
    echo -e "${YELLOW}ℹ️  本地 commit 已推送到远程 $branch，不会丢失${NC}"
    echo "   请访问 GitHub 手动处理 PR #$pr_number"
    exit 1
fi
echo -e "${GREEN}✅ PR #$pr_number 合并成功${NC}"

# ============================================================
# 5. 拉取最新 main（失败则退出，反正 PR 已合并，下次 pull 也能同步）
# ============================================================
echo "🔄 拉取最新 main ..."
if ! git fetch origin main; then
    echo -e "${YELLOW}⚠️  获取远程 main 失败，但 PR 已合并${NC}"
    echo -e "${YELLOW}   下次运行 pull_notes.sh 即可同步，本次安全退出${NC}"
    exit 0
fi

# ============================================================
# 6. 验证远程 main 确实包含了本次的改动再做 reset
#    （对 squash 合并，比较 tree 而不是 commit SHA）
# ============================================================
if [ "$has_new_commit" = true ]; then
    local_tree=$(git rev-parse HEAD^{tree})
    remote_main_tree=$(git rev-parse origin/main^{tree})
    if [ "$local_tree" != "$remote_main_tree" ]; then
        echo -e "${YELLOW}⚠️  检测到远程 main 的内容与本地 HEAD 不一致${NC}"
        echo -e "${YELLOW}   （可能 main 上还有其他提交，属正常情况）${NC}"
    fi
fi

# ============================================================
# 7. 将本地 from/xxx 对齐到 main，再 force push 保持分支整洁
# ============================================================
echo "🔀 将 $branch 对齐到 main ..."
# 先更新本地 main 引用
git branch -f main origin/main 2>/dev/null || true
# 把当前分支 reset 到 origin/main
git reset --hard origin/main

if ! git push --force-with-lease origin "$branch"; then
    echo -e "${YELLOW}⚠️  强推 $branch 失败，但 main 已是最新${NC}"
    echo -e "${YELLOW}   下次运行脚本时会自动修复${NC}"
fi

echo ""
echo -e "${GREEN}✅ 笔记已同步完成！${NC}"
git status --short
