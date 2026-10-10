#!/usr/bin/env bash
# 一键把本目录推到 GitHub，自动创建仓库并触发云编译 workflow。
#
# 用法（任选一种授权）：
#   export GH_TOKEN=ghp_xxxxxxxxxxxxxxxx        # PAT，需要 repo + workflow 权限
#   bash push_to_github.sh zhujitown-app        # 仓库名，省略则用 zhujitown-app
#
# 或用 SSH（已生成 ~/.ssh/zhujitown_github.pub，需先手动加到 GitHub）：
#   bash push_to_github.sh zhujitown-app ssh
#
# 说明：token 只活在本次进程里，不会写进 .git/config，也不会留在任何文件中。
set -euo pipefail

REPO_NAME="${1:-zhujitown-app}"
MODE="${2:-token}"
PRIVATE="false"

cd "$(dirname "$0")"

# 找一个可用的 python（Windows 上 python 可能不在 PATH）
PY=""
for cand in python python3 py \
  "$HOME/.workbuddy/binaries/python/versions/3.13.12/python.exe"; do
  if command -v "$cand" >/dev/null 2>&1; then PY="$cand"; break; fi
done
if [ -z "$PY" ]; then
  echo "错误：找不到 python，无法解析 GitHub API 响应"
  exit 1
fi

jget() { "$PY" -c 'import sys,json;d=json.load(sys.stdin);print(d.get(sys.argv[1],""))' "$1"; }

if [ "$MODE" = "token" ]; then
  if [ -z "${GH_TOKEN:-}" ]; then
    echo "错误：请先在环境变量里提供 GH_TOKEN"
    echo "  export GH_TOKEN=你的GitHub个人访问令牌（勾选 repo 权限）"
    exit 1
  fi

  echo "==> 校验 token"
  ME=$(curl -s -H "Authorization: Bearer $GH_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            https://api.github.com/user)
  OWNER=$(echo "$ME" | jget login)
  if [ -z "$OWNER" ]; then
    echo "token 无效或权限不足："
    echo "$ME" | head -5
    exit 1
  fi
  echo "    已登录为：$OWNER"

  echo "==> 创建仓库 $REPO_NAME"
  CREATE=$(curl -s -X POST https://api.github.com/user/repos \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "{\"name\":\"$REPO_NAME\",\"private\":$PRIVATE,\"description\":\"主机镇 WordPress 原生 App（Android + iOS）\"}")
  FULL=$(echo "$CREATE" | jget full_name)
  if [ -z "$FULL" ]; then
    MSG=$(echo "$CREATE" | jget message)
    echo "    （$MSG）尝试复用已有仓库"
    FULL="$OWNER/$REPO_NAME"
  fi

  # token 只在本次 push 中使用，不写进 .git/config
  ASKPASS=$(mktemp)
  cat > "$ASKPASS" <<EOF
#!/bin/sh
case "\$1" in
  *Username*) echo "$OWNER" ;;
  *Password*) echo "$GH_TOKEN" ;;
esac
EOF
  chmod +x "$ASKPASS"
  trap 'rm -f "$ASKPASS"' EXIT

  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/$FULL.git"
else
  read -rp "GitHub 用户名: " OWNER
  FULL="$OWNER/$REPO_NAME"
  git remote remove origin 2>/dev/null || true
  git remote add origin "git@github.com:$FULL.git"
  export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/zhujitown_github -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
  ASKPASS=""
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "==> 推送 $BRANCH → https://github.com/$FULL"
if [ -n "${ASKPASS:-}" ]; then
  GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0 git push -u origin "$BRANCH"
else
  git push -u origin "$BRANCH"
fi

echo
echo "推送完成 → https://github.com/$FULL"
echo "remote 中不含 token：$(git remote get-url origin)"
echo
echo "接下来："
echo " 1. 打开 https://github.com/$FULL/actions"
echo " 2. Android APK：左侧选「Build Android APK」→ Run workflow（push 已自动触发一次）"
echo " 3. iOS IPA：左侧选「构建 iOS IPA」→ Run workflow → mode 选 unsigned"
echo " 4. 跑完点进任务，底部 Artifacts 下载："
echo "      ZhuJiTown-Android-APK / ZhuJiTown-iOS-IPA"
