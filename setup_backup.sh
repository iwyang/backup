#!/bin/bash

# --- 核心黑科技：无论发生什么（报错、成功、意外中断），退出前强制暂停 ---
trap 'echo -e "\n🛑 脚本运行结束。请按回车键关闭窗口..."; read' EXIT

echo "🚀 初始化程序启动..."

# 1. 检查 Git 基础环境
if ! git --version > /dev/null 2>&1; then
    echo "❌ 严重错误: 未检测到 Git，请先安装 Git for Windows。"
    exit 1
fi

# 2. 获取用户输入
DEFAULT_MSG="更新：$(date '+%Y-%m-%d %H:%M:%S')"
echo "---------------------------------------"
echo "📅 当前时间: $(date '+%Y-%m-%d %H:%M:%S')"
read -p "请输入备份信息 (直接回车默认: $DEFAULT_MSG): " USER_INPUT
COMMIT_MSG=${USER_INPUT:-$DEFAULT_MSG}
echo "确认备份信息: $COMMIT_MSG"
echo "---------------------------------------"

# 3. 生成 Workflow 文件
echo "📂 正在生成 GitHub Actions 配置文件..."
mkdir -p .github/workflows/

cat << 'INNER_EOF' > .github/workflows/release-sync.yml
name: Release Sync
permissions:
  contents: write

on:
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
# 忽略 git init 的错误（如果已经存在）
git init > /dev/null 2>&1

# 移除旧的 remote，确保指向最新
git remote remove origin > /dev/null 2>&1
git remote add origin https://github.com/iwyang/backup

git branch -M main
git add .

# 检查是否有变更需要提交
if ! git diff-index --quiet HEAD --; then
    echo "📝 提交更改: $COMMIT_MSG"
    git commit -m "$COMMIT_MSG"
else
    echo "ℹ️ 文件无变化，跳过提交步骤。"
fi

echo "☁️ 正在推送到 GitHub (可能需要几秒钟)..."
# 使用 force 推送，避免历史冲突导致脚本卡死
if git push -u origin main --force; then
    echo "✅ 推送成功！"
else
    echo "❌ 推送失败！可能原因：网络问题 或 权限不足。"
fi

# 这里的 exit 会触发第一行的 trap，所以一定会暂停
exit 0
