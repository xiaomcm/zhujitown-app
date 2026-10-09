#!/usr/bin/env bash
# 一键把本目录推到 GitHub，自动创建仓库并触发云编译 workflow。
#
# 用法（任选一种授权）：
#   export GH_TOKEN=ghp_xxxxxxxxxxxxxxxx        # PAT，需要 repo 权限
#   bash push_to_github.sh zhujitown-app        # 仓库名，省略则用 zhujitown-app
#
# 或用 SSH（已生成 ~/.ssh/zhujitown_github.pub，需先手动加到 GitHub）：
#   bash push_to_github.sh zhujitown-app ssh
set -euo pipefail

REPO_NAME="${1:-zhujitown-app}"
MODE="${2:-token}"
PRIVATE="false"

cd "$(dirname "$0")"

echo "==> 仓库名：$REPO_NAME（private=$PRIVATE）"

if [ "$MODE" = "token" ]; then
  if [ -z "${GH_TOKEN:-}" ]; then
    echo "错误：请先在环境变量里提供 GH_TOKEN"
    echo "  export GH_TOKEN=你的GitHub个人访问令牌（勾选 repo 权限）"
    exit 1
  fi

  echo "==> 创建 GitHub 仓库"
  CREATE=$(curl -s -X POST https://api.github.com/user/repos \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "{\"name\":\"$REPO_NAME\",\"private\":$PRIVATE,\"description\":\"主机镇 WordPress 原生 App（Android + iOS）\"}")

  OWNER=$(echo "$CREATE" | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  FULL=$(echo "$CREATE" | sed -n 's/.*"full_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

  if [ -z "$FULL" ]; then
    echo "$CREATE" | head -20
    echo "创建失败（仓库可能已存在），尝试直接推送…"
    OWNER=$(curl -s https://api.github.com/user -H "Authorization: Bearer $GH_TOKEN" \
      | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    FULL="$OWNER/$REPO_NAME"
  fi

  REMOTE="https://$OWNER:$GH_TOKEN@github.com/$FULL.git"
  git remote remove origin 2>/dev/null || true
  git remote add origin "$REMOTE"
else
  read -rp "GitHub 用户名: " OWNER
  REMOTE="git@github.com:$OWNER/$REPO_NAME.git"
  git remote remove origin 2>/dev/null || true
  git remote add origin "$REMOTE"
  export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/zhujitown_github -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
  FULL="$OWNER/$REPO_NAME"
fi

echo "==> 推送到 $REMOTE"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git push -u origin "$BRANCH" --force-with-lease

echo
echo "推送完成 → https://github.com/$FULL"
echo
echo "接下来："
echo " 1. 打开 https://github.com/$FULL/actions"
echo " 2. Android APK：左侧选「Build Android APK」→ Run workflow（push 已自动触发一次）"
echo " 3. iOS IPA：左侧选「构建 iOS IPA」→ Run workflow → mode 选 unsigned"
echo " 4. 跑完点进任务，底部 Artifacts 下载："
echo "      ZhuJiTown-Android-APK / ZhuJiTown-iOS-IPA"
