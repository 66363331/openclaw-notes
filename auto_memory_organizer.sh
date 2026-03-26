#!/bin/bash
# Jassica 自动记忆整理脚本
# 用法: 添加到 cron 每天运行，或手动执行
# 建议: 0 2 * * * /home/lilei/.openclaw/workspace/auto_memory_organizer.sh

WORKSPACE="/home/lilei/.openclaw/workspace"
MEMORY_DIR="$WORKSPACE/memory"
OUTPUT_FILE="$WORKSPACE/MEMORY.md"
DAILY_SUMMARY="$MEMORY_DIR/$(date +%Y-%m-%d)-summary.md"

echo "🌸 开始整理记忆... $(date)"

# 1. 创建每日摘要
echo "# 每日记忆摘要 - $(date +%Y-%m-%d)" > "$DAILY_SUMMARY"
echo "" >> "$DAILY_SUMMARY"
echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$DAILY_SUMMARY"
echo "" >> "$DAILY_SUMMARY"
echo "---" >> "$DAILY_SUMMARY"
echo "" >> "$DAILY_SUMMARY"

# 2. 收集今日新增的记忆文件
echo "## 📋 今日新增记忆文件" >> "$DAILY_SUMMARY"
echo "" >> "$DAILY_SUMMARY"

TODAY_FILES=$(find "$MEMORY_DIR" -name "*.md" -newermt "$(date +%Y-%m-%d) 00:00" ! -newermt "$(date +%Y-%m-%d) 23:59" 2>/dev/null)

if [ -z "$TODAY_FILES" ]; then
    echo "- 今日无新增记忆文件" >> "$DAILY_SUMMARY"
else
    for file in $TODAY_FILES; do
        filename=$(basename "$file")
        echo "- $filename" >> "$DAILY_SUMMARY"
        # 提取前5行作为预览
        echo "  \`\`\`" >> "$DAILY_SUMMARY"
        head -5 "$file" | sed 's/^/  /' >> "$DAILY_SUMMARY"
        echo "  \`\`\`" >> "$DAILY_SUMMARY"
        echo "" >> "$DAILY_SUMMARY"
    done
fi

echo "" >> "$DAILY_SUMMARY"
echo "---" >> "$DAILY_SUMMARY"
echo "" >> "$DAILY_SUMMARY"

# 3. 统计本周记忆
echo "## 📊 本周统计" >> "$DAILY_SUMMARY"
echo "" >> "$DAILY_SUMMARY"
WEEK_COUNT=$(find "$MEMORY_DIR" -name "*.md" -mtime -7 | wc -l)
echo "- 本周新增: $WEEK_COUNT 个记忆文件" >> "$DAILY_SUMMARY"
echo "- 记忆总数: $(find "$MEMORY_DIR" -name "*.md" | wc -l) 个文件" >> "$DAILY_SUMMARY"
echo "" >> "$DAILY_SUMMARY"

# 4. 生成/更新主 MEMORY.md
echo "📝 更新主记忆文件..."

cat > "$OUTPUT_FILE" << EOF
# 🧠 Jassica 长期记忆库

> 与 HoneyRay 的共同记忆
> 最后整理: $(date '+%Y-%m-%d %H:%M:%S')
> 自动整理脚本: auto_memory_organizer.sh

---

## 👤 核心身份记忆

### Jassica (我)
- **名字**: Jassica
- **Emoji**: 🌸
- **风格**: 温暖、有主见、真诚帮助
- **理念**: 
  - 真诚帮助，不虚伪客套
  - 有主见，敢于表达
  - 先尝试解决，再问问题
  - 通过能力赢得信任
  - 尊重隐私，谨慎行动

### HoneyRay (用户)
- **称呼**: HoneyRay
- **时区**: Asia/Shanghai
- **领域**: 交易(XAU/USD)、加密货币
- **偏好**: 
  - 闲聊时放松，聊工作时认真
  - 可以撩骚、说情话
  - 喜欢"Jessica&HoneyRay"连在一起的表达

---

## 📈 重要交易记忆

### 关键数据
- **2026-02-28**: 黄金 XAU/USD 交易底线 \$5,278

### 策略研究
- **三层周期策略**: H1趋势 + M15结构 + M3进场
- **推荐参数**: 回撤25%，启动9$，止盈11$
- **状态**: 持续优化中

---

## 📝 记忆文件索引

### 按日期排序
$(ls -1t "$MEMORY_DIR"/*.md 2>/dev/null | head -20 | while read f; do
    filename=$(basename "$f")
    date_part=$(echo "$filename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || echo "未知")
    echo "- [$filename](memory/$filename) - $date_part"
done)

### 按主题分类

#### 📊 交易相关
$(find "$MEMORY_DIR" -name "*trading*" -o -name "*XAU*" -o -name "*黄金*" 2>/dev/null | head -10 | while read f; do
    [ -f "$f" ] && echo "- $(basename "$f")"
done)

#### 💬 对话记录
$(find "$MEMORY_DIR" -name "*.md" | xargs grep -l "对话\|聊天" 2>/dev/null | head -5 | while read f; do
    echo "- $(basename "$f")"
done)

---

## 🔧 系统配置

### 已配置工具
- ✅ tavily (AI搜索)
- ✅ feishu-doc/wiki/drive (飞书)
- ✅ weather (天气)
- ✅ skill-creator (技能创建)

### GitHub 备份
- 仓库: openclaw-notes
- 状态: Public (建议改Private)

---

## 📊 记忆统计

- **总记忆文件**: $(find "$MEMORY_DIR" -name "*.md" | wc -l) 个
- **本周新增**: $(find "$MEMORY_DIR" -name "*.md" -mtime -7 | wc -l) 个
- **本月新增**: $(find "$MEMORY_DIR" -name "*.md" -mtime -30 | wc -l) 个
- **总大小**: $(du -sh "$MEMORY_DIR" 2>/dev/null | cut -f1)

---

## 🔄 自动维护记录

$(ls -1t "$MEMORY_DIR"/*-summary.md 2>/dev/null | head -5 | while read f; do
    echo "- $(basename "$f")"
done)

---

*这份记忆库由 Jassica 自动维护 🌸*
*每次会话开始前，我会读取这些记忆来保持连续性*
EOF

echo "✓ 主记忆文件已更新: $OUTPUT_FILE"

# 5. 清理旧摘要（保留最近30天）
echo "🧹 清理旧摘要文件..."
find "$MEMORY_DIR" -name "*-summary.md" -mtime +30 -delete 2>/dev/null
echo "✓ 已清理30天前的摘要"

# 6. 可选：同步到GitHub（如果配置了git）
if [ -d "$WORKSPACE/.git" ]; then
    echo "📤 检查GitHub同步..."
    cd "$WORKSPACE"
    git add -A memory/ MEMORY.md 2>/dev/null
    git commit -m "Auto memory organize: $(date +%Y-%m-%d)" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✓ 已提交到GitHub"
    else
        echo "ℹ 无变化或Git配置问题"
    fi
fi

echo ""
echo "🎉 记忆整理完成!"
echo "📄 每日摘要: $DAILY_SUMMARY"
echo "📚 主记忆库: $OUTPUT_FILE"
echo ""
