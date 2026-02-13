#!/bin/bash

echo "🚀 开始初始化备份仓库项目..."

# 1. 创建 Workflow 目录
mkdir -p .github/workflows/

# 2. 写入同步逻辑到 YAML 文件
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

echo "✅ Workflow 文件创建成功。"

# 3. Git 初始化与推送
echo "📦 正在连接远程仓库并推送到 GitHub..."
git init
git remote add origin https://github.com/iwyang/backup
git branch -M main
git add .
git commit -m "feat: initial commit with release sync workflow"
git push -u origin main

echo "🎉 所有操作已完成！请记得去 GitHub 仓库 Settings 开启 Workflow 读写权限。"
