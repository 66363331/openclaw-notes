#!/bin/bash
# 飞书备份脚本（GitHub失败时使用）
# 将核心文件备份到飞书云文档

WORKSPACE="/home/lilei/.openclaw/workspace"
FEISHU_BACKUP_DIR="$WORKSPACE/feishu_backup"
LOG="$WORKSPACE/.backup.log"

echo "=== 飞书备份开始 $(date) ===" >> $LOG

# 创建备份目录
mkdir -p "$FEISHU_BACKUP_DIR"

# 复制核心文件
cp "$WORKSPACE/SOUL.md" "$FEISHU_BACKUP_DIR/SOUL_$(date +%Y%m%d_%H%M).md" 2>/dev/null
cp "$WORKSPACE/MEMORY.md" "$FEISHU_BACKUP_DIR/MEMORY_$(date +%Y%m%d_%H%M).md" 2>/dev/null
cp "$WORKSPACE/AGENTS.md" "$FEISHU_BACKUP_DIR/AGENTS_$(date +%Y%m%d_%H%M).md" 2>/dev/null

# 保留最近30个备份，删除旧的
ls -t "$FEISHU_BACKUP_DIR"/SOUL_*.md 2>/dev/null | tail -n +31 | xargs -r rm
echo "✅ 飞书本地备份完成（保留最近30个版本）" >> $LOG

# 这里可以添加飞书API上传逻辑（如果有API权限）
# 目前先保存在本地，等需要时手动同步到飞书云文档

echo "=== 飞书备份完成 $(date) ===" >> $LOG
