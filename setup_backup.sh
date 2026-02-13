#!/bin/bash

# --- 定义错误处理函数 ---
die() {
    echo ""
    echo "❌ 错误: $1"
    echo "---------------------------------------"
    read -p "🔴 脚本运行失败。请按回车键关闭窗口..."
    exit 1
}

echo "🚀 初始化程序启动..."

# 1. 检查 Git
if ! git --version > /dev/null 2>&1; then
    die "未检测到 Git，请先安装 Git for Windows。"
fi

# 2. 获取用户输入
DEFAULT_MSG="更新配置：$(date '+%Y-%m-%d %H:%M:%S')"
echo "---------------------------------------"
echo "📅 当前时间: $(date '+%Y-%m-%d %H:%M:%S')"
read -p "请输入提交信息 (直接回车默认: $DEFAULT_MSG): " USER_INPUT
COMMIT_MSG=${USER_INPUT:-$DEFAULT_MSG}
echo "确认信息: $COMMIT_MSG"
echo "---------------------------------------"

# 3. 生成 Workflow 文件
echo "📂 正在生成 GitHub Actions 配置文件..."
mkdir -p .github/workflows/

cat << 'INNER_EOF' > .github/workflows/release-sync.yml
name: Release Sync
permissions:
  contents: write

on:
  # --- 新增：代码推送时自动触发 ---
  push:
    branches: 
      - main
  # ---------------------------
  workflow_dispatch:
  schedule:
    - cron: '0 3 * * *'

jobs:
  sync-job:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - source: "2dust/v2rayN"
            alias: "v2rayN"
          - source: "2dust/v2rayNG"
            alias: "v2rayNG"
          - source: "orion-lib/OrionTV"
            alias: "OrionTV"
          - source: "MoonTechLab/Selene"
            alias: "Selene"
          - source: "zbezj/HEU_KMS_Activator"
            alias: "HEU_KMS"

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Sync Release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          SOURCE_REPO: ${{ matrix.source }}
          ALIAS: ${{ matrix.alias }}
        run: |
          ORIGINAL_TAG=$(gh release view --repo $SOURCE_REPO --json tagName --jq .tagName)
          NEW_TAG="${ALIAS}-${ORIGINAL_TAG}"
          
          echo "Checking $SOURCE_REPO latest: $ORIGINAL_TAG"

          if gh release view $NEW_TAG > /dev/null 2>&1; then
            echo "Version $NEW_TAG already exists, skipping."
            exit 0
          fi

          OLD_TAGS=$(gh release list --limit 100 --json tagName --jq ".[].tagName" | grep "^${ALIAS}-" || true)
          for tag in $OLD_TAGS; do
            echo "Deleting old backup: $tag"
            gh release delete $tag --yes --cleanup-tag
          done

          mkdir -p ./temp_assets
          gh release download $ORIGINAL_TAG --repo $SOURCE_REPO --pattern "*" --dir ./temp_assets

          TITLE=$(gh release view $ORIGINAL_TAG --repo $SOURCE_REPO --json name --jq .name)
          [ -z "$TITLE" ] && TITLE=$ORIGINAL_TAG
          
          gh release create $NEW_TAG ./temp_assets/* \
            --title "[$ALIAS] $TITLE" \
            --notes "Sync Date: $(date '+%Y-%m-%d %H:%M:%S') | Source: https://github.com/$SOURCE_REPO"
          
          echo "Project $ALIAS sync complete!"
INNER_EOF

# 4. Git 提交与推送
echo "📦 执行 Git 仓库操作..."

git init > /dev/null 2>&1
git remote remove origin > /dev/null 2>&1
git remote add origin https://github.com/iwyang/backup || die "无法添加远程仓库"

git branch -M main
git add .

if ! git diff-index --quiet HEAD --; then
    echo "📝 提交更改: $COMMIT_MSG"
    git commit -m "$COMMIT_MSG" || die "Git 提交失败"
else
    echo "ℹ️ 文件无变化，跳过提交步骤。"
fi

echo "☁️ 正在推送到 GitHub..."

if git push -u origin main --force; then
    echo ""
    echo "======================================="
    echo "✅ 推送成功！Actions 将立即开始运行。"
    echo "✨ 窗口将在 2 秒后自动关闭..."
    echo "======================================="
    sleep 2
    exit 0
else
    die "推送失败！请检查网络连接或 GitHub 权限。"
fi
