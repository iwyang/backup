name: Release Sync
permissions:
  contents: write

on:
  push:
    branches: 
      - main
  workflow_dispatch:
    inputs:
      force_resync:
        description: '是否强制重新同步所有项目'
        required: false
        default: 'false'
  schedule:
    - cron: '0 3 * * *'

jobs:
  sync-by-real-time:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Time-Travel Sync
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          FORCE_SYNC: ${{ github.event.inputs.force_resync }}
        run: |
          # 定义项目列表：格式为 "上游仓库|本地别名"
          repos=(
            "2dust/v2rayN|v2rayN"
            "2dust/v2rayNG|v2rayNG"
            "orion-lib/OrionTV|OrionTV"
            "zbezj/HEU_KMS_Activator|HEU_KMS"
            "eritpchy/FingerprintPay|FingerprintPay"
            "connectbot/connectbot|connectbot"
            "koreader/koreader|koreader"
            "Dr-TSNG/ZygiskNext|ZygiskNext"
            "JingMatrix/LSPosed|LSPosed"
            "Xposed-Modules-Repo/com.y7.fingerpay|com.y7.fingerpay"
            "twoone-3/AdGuardHomeForRoot|AdGuardHomeForRoot"
          )

          echo "正在获取各项目原作者发布时间..."
          rm -f repo_list.txt
          for item in "${repos[@]}"; do
            src=$(echo $item | cut -d'|' -f1)
            alias=$(echo $item | cut -d'|' -f2)
            # 获取上游最新发布的发布时间
            pub_date=$(gh release view --repo $src --json publishedAt --jq .publishedAt 2>/dev/null || echo "1970-01-01T00:00:00Z")
            echo "$pub_date|$src|$alias" >> repo_list.txt
          done

          # 【升序排列】：按照时间从旧到新处理
          sort -t'|' -k1,1 repo_list.txt -o repo_list_sorted.txt
          
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

          total_items=$(wc -l < repo_list_sorted.txt)
          current_index=0

          while IFS='|' read -r date src alias; do
            current_index=$((current_index + 1))
            echo "=========================================="
            echo "正在处理 [$current_index/$total_items]: $alias (原作者更新于: $date)"
            
            # 获取上游最新的 Tag 名
            ORIGINAL_TAG=$(gh release view --repo $src --json tagName --jq .tagName)
            NEW_TAG="${alias}-${ORIGINAL_TAG}"

            # 检查本地是否已经存在该版本（如果不是强制同步）
            if [ "$FORCE_SYNC" != "true" ]; then
              if gh release view "$NEW_TAG" > /dev/null 2>&1; then
                echo "跳过已存在的最新版: $alias ($ORIGINAL_TAG)"
                continue
              fi
            fi

            # ==== 清理该项目的所有历史 Release 和 Tag ====
            echo "正在清理 [$alias] 的所有历史旧版本..."
            OLD_TAGS=$(gh release list --limit 100 --json tagName --jq ".[].tagName" | grep "^${alias}-" || true)
            for OLD_TAG in $OLD_TAGS; do
              echo "删除旧版本: $OLD_TAG"
              gh release delete "$OLD_TAG" --yes --cleanup-tag 2>/dev/null || true
            done
            gh release delete "$NEW_TAG" --yes --cleanup-tag 2>/dev/null || true

            # 【时间穿越】：注入原始发布时间到 Git 提交
            export GIT_AUTHOR_DATE="$date"
            export GIT_COMMITTER_DATE="$date"

            git commit --allow-empty -m "Release $alias $ORIGINAL_TAG"
            git pull --rebase origin main || true
            git push origin main
            
            # 下载上游资源
            mkdir -p ./temp_assets && rm -rf ./temp_assets/*
            gh release download "$ORIGINAL_TAG" --repo "$src" --pattern "*" --dir ./temp_assets
            
            # ==== 核心修改：获取 Release 标题和正文（更新日志） ====
            # 一次性获取标题(name)和内容(body)
            RELEASE_INFO=$(gh release view "$ORIGINAL_TAG" --repo "$src" --json name,body)
            TITLE=$(echo "$RELEASE_INFO" | jq -r .name)
            UPSTREAM_BODY=$(echo "$RELEASE_INFO" | jq -r .body)

            if [ -z "$TITLE" ] || [ "$TITLE" == "null" ]; then
              TITLE="$ORIGINAL_TAG"
            fi
            
            CLEAN_DATE=$(echo "$date" | tr 'T' ' ' | tr -d 'Z')
            SYNC_TIME=$(date '+%Y-%m-%d %H:%M:%S')
            
            # 生成新的发布说明：包含元数据和原始更新日志
            cat << EOF > release_notes.md
**Upstream Release:** [🔗 $src@$ORIGINAL_TAG](https://github.com/$src/releases/tag/$ORIGINAL_TAG) | **Upstream Update:** $CLEAN_DATE | **Sync Date:** $SYNC_TIME

---

### Upstream Release Notes / 原作者更新日志：

$UPSTREAM_BODY
EOF
            # ========================================================

            # 创建新的 Release
            if [ "$current_index" -eq "$total_items" ]; then
              echo "创建并标记为最新的 Release..."
              gh release create "$NEW_TAG" ./temp_assets/* \
                --title "[$alias] $TITLE" \
                --notes-file release_notes.md \
                --latest
            else
              echo "创建 Release..."
              gh release create "$NEW_TAG" ./temp_assets/* \
                --title "[$alias] $TITLE" \
                --notes-file release_notes.md \
                --latest=false
            fi
            
            echo "$alias 同步完成！"
            sleep 2
          done < repo_list_sorted.txt
