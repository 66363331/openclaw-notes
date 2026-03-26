#!/bin/bash
# 核心记忆文件备份脚本
# 备份 SOUL.md MEMORY.md AGENTS.md 到 GitHub

WORKSPACE="/home/lilei/.openclaw/workspace"
BACKUP_FILES=("SOUL.md" "MEMORY.md" "AGENTS.md")
BACKUP_LOG="$WORKSPACE/.backup.log"

echo "=== 备份开始 $(date) ===" >> $BACKUP_LOG

# 检查文件是否存在并添加
for file in "${BACKUP_FILES[@]}"; do
    if [ -f "$WORKSPACE/$file" ]; then
        echo "备份: $file" >> $BACKUP_LOG
    else
        echo "警告: $file 不存在" >> $BACKUP_LOG
    fi
done

# Git 操作
cd $WORKSPACE

# 配置 git（如果没有）
git config user.email "jassica@honeyray.local" 2>/dev/null
git config user.name "Jassica" 2>/dev/null

# 添加核心文件
git add SOUL.md MEMORY.md AGENTS.md 2>/dev/null

# 检查是否有变更
if git diff --cached --quiet; then
    echo "没有变更，跳过备份" >> $BACKUP_LOG
    echo "=== 备份完成 $(date) - 无变更 ===" >> $BACKUP_LOG
    exit 0
fi

# 提交并推送
COMMIT_MSG="Auto backup: $(date '+%Y-%m-%d %H:%M:%S') - Core memory files"
git commit -m "$COMMIT_MSG" >> $BACKUP_LOG 2>&1

if git push origin main >> $BACKUP_LOG 2>&1; then
    echo "✅ GitHub 备份成功" >> $BACKUP_LOG
    echo "=== 备份完成 $(date) - 成功 ===" >> $BACKUP_LOG
    exit 0
else
    echo "❌ GitHub 备份失败，尝试备用方案..." >> $BACKUP_LOG
    # 备用方案：复制到安全目录
    mkdir -p "$WORKSPACE/.local_backup"
    cp SOUL.md MEMORY.md AGENTS.md "$WORKSPACE/.local_backup/"
    echo "✅ 本地备份完成" >> $BACKUP_LOG
    echo "=== 备份完成 $(date) - GitHub失败，本地备份 ===" >> $BACKUP_LOG
    exit 1
fi
