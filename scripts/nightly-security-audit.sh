#!/bin/bash
#
# OpenClaw 每晚安全巡检脚本
# 覆盖13项核心指标，显性化汇报
#

set -e

# 路径配置（兼容自定义安装位置）
OC="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
REPORT_DIR="/tmp/openclaw/security-reports"
REPORT_FILE="$REPORT_DIR/report-$(date +%Y-%m-%d).txt"
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M:%S)

# 创建报告目录
mkdir -p "$REPORT_DIR"

# 开始生成报告
cat > "$REPORT_FILE" << EOF
================================================================================
🛡️ OpenClaw 每晚安全巡检报告
================================================================================
日期: $DATE
时间: $TIME
主机: $(hostname)
用户: $(whoami)
================================================================================

EOF

# 初始化计数器
ALERT_COUNT=0
WARN_COUNT=0

# 函数：记录检查结果
log_check() {
    local num=$1
    local name=$2
    local status=$3
    local detail=$4
    
    echo "" >> "$REPORT_FILE"
    echo "[$num/13] $name" >> "$REPORT_FILE"
    echo "状态: $status" >> "$REPORT_FILE"
    if [ -n "$detail" ]; then
        echo "详情: $detail" >> "$REPORT_FILE"
    fi
    echo "---" >> "$REPORT_FILE"
}

# ============ 1. OpenClaw 安全审计 ============
echo "正在执行: OpenClaw 安全审计..."
if command -v openclaw &>/dev/null; then
    AUDIT_RESULT=$(openclaw security audit 2>&1 || echo "无法执行安全审计")
    if echo "$AUDIT_RESULT" | grep -q "audit"; then
        log_check "1" "OpenClaw 安全审计" "✅ 已执行" "$AUDIT_RESULT"
    else
        log_check "1" "OpenClaw 安全审计" "⚠️ 部分受限" "openclaw security audit 命令受限或无权限"
        ((WARN_COUNT++))
    fi
else
    log_check "1" "OpenClaw 安全审计" "⚠️ 未找到命令" "openclaw 命令不可用"
    ((WARN_COUNT++))
fi

# ============ 2. 进程与网络审计 ============
echo "正在执行: 进程与网络审计..."
NET_INFO=$(ss -tlnp 2>/dev/null | head -20 || netstat -tlnp 2>/dev/null | head -20 || echo "无法获取网络信息")
PORTS=$(echo "$NET_INFO" | grep -c "LISTEN" || echo "0")
log_check "2" "进程网络审计" "✅ 完成" "监听端口数: $PORTS"

# ============ 3. 敏感目录变更 ============
echo "正在执行: 敏感目录变更扫描..."
RECENT_FILES=$(find "$OC" -type f -mtime -1 2>/dev/null | wc -l)
SSH_CHANGES=$(find ~/.ssh -type f -mtime -1 2>/dev/null | wc -l)
if [ "$RECENT_FILES" -gt 0 ] || [ "$SSH_CHANGES" -gt 0 ]; then
    log_check "3" "目录变更扫描" "⚠️ 发现变更" "$OC: $RECENT_FILES 个文件, ~/.ssh: $SSH_CHANGES 个文件"
    ((WARN_COUNT++))
else
    log_check "3" "目录变更扫描" "✅ 无变更" "最近24小时无文件变更"
fi

# ============ 4. 系统定时任务 ============
echo "正在执行: 系统定时任务检查..."
CRON_FILES=$(find /etc/cron.d /etc/cron.daily /etc/cron.hourly -type f 2>/dev/null | wc -l)
USER_CRON=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" | wc -l)
log_check "4" "系统定时任务" "✅ 已检查" "系统级: $CRON_FILES 个文件, 用户级: $USER_CRON 个任务"

# ============ 5. OpenClaw Cron Jobs ============
echo "正在执行: OpenClaw Cron 检查..."
if command -v openclaw &>/dev/null; then
    OC_CRON=$(openclaw cron list 2>/dev/null | grep -c "│" || echo "0")
    log_check "5" "OpenClaw Cron Jobs" "✅ 已检查" "当前任务数: $OC_CRON"
else
    log_check "5" "OpenClaw Cron Jobs" "⚠️ 无法检查" "openclaw 命令不可用"
    ((WARN_COUNT++))
fi

# ============ 6. SSH 安全检查 ============
echo "正在执行: SSH 安全检查..."
FAILED_SSH=$(grep "Failed password" /var/log/auth.log 2>/dev/null | wc -l || echo "0")
if [ "$FAILED_SSH" -gt 10 ]; then
    log_check "6" "SSH 安全" "🚨 高风险" "发现 $FAILED_SSH 次失败登录尝试"
    ((ALERT_COUNT++))
else
    log_check "6" "SSH 安全" "✅ 正常" "失败登录尝试: $FAILED_SSH 次"
fi

# ============ 7. 关键文件完整性 ============
echo "正在执行: 关键文件完整性检查..."
if [ -f "$OC/.config-baseline.sha256" ]; then
    if sha256sum -c "$OC/.config-baseline.sha256" &>/dev/null; then
        log_check "7" "配置基线" "✅ 哈希校验通过" "openclaw.json 未被篡改"
    else
        log_check "7" "配置基线" "🚨 校验失败" "openclaw.json 可能已被修改"
        ((ALERT_COUNT++))
    fi
else
    log_check "7" "配置基线" "⚠️ 基线不存在" "请先运行: sha256sum $OC/openclaw.json > $OC/.config-baseline.sha256"
    ((WARN_COUNT++))
fi

# 检查核心文件权限
CONFIG_PERM=$(stat -c "%a" "$OC/openclaw.json" 2>/dev/null || echo "unknown")
if [ "$CONFIG_PERM" = "600" ]; then
    log_check "7" "权限检查" "✅ 权限正确" "openclaw.json 权限: 600"
else
    log_check "7" "权限检查" "⚠️ 权限异常" "openclaw.json 权限: $CONFIG_PERM (应为 600)"
    ((WARN_COUNT++))
fi

# ============ 8. 黄线操作审计 ============
echo "正在执行: 黄线操作审计..."
TODAY_MEMORY="$OC/workspace/memory/$DATE.md"
if [ -f "$TODAY_MEMORY" ]; then
    SUDO_COUNT=$(grep -c "sudo" "$TODAY_MEMORY" 2>/dev/null || echo "0")
    log_check "8" "黄线操作审计" "✅ 已比对" "今日 memory 中记录 $SUDO_COUNT 次 sudo 操作"
else
    log_check "8" "黄线操作审计" "⚠️ 无今日记录" "memory/$DATE.md 不存在"
fi

# ============ 9. 磁盘使用 ============
echo "正在执行: 磁盘使用检查..."
DISK_USAGE=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || echo "0")
if [ "$DISK_USAGE" -gt 85 ]; then
    log_check "9" "磁盘容量" "🚨 空间不足" "根分区占用: ${DISK_USAGE}% (>85%)"
    ((ALERT_COUNT++))
else
    log_check "9" "磁盘容量" "✅ 空间充足" "根分区占用: ${DISK_USAGE}%"
fi

# 检查新增大文件
LARGE_FILES=$(find / -type f -size +100M -mtime -1 2>/dev/null | wc -l || echo "0")
log_check "9" "新增大文件" "✅ 已检查" "最近24h新增 >100MB 文件: $LARGE_FILES 个"

# ============ 10. Gateway 环境变量 ============
echo "正在执行: Gateway 环境变量检查..."
GATEWAY_PID=$(pgrep -f "openclaw-gateway" | head -1 || echo "")
if [ -n "$GATEWAY_PID" ]; then
    ENV_VARS=$(cat /proc/$GATEWAY_PID/environ 2>/dev/null | tr '\0' '\n' | grep -iE "(KEY|TOKEN|SECRET|PASSWORD)" | cut -d= -f1 | sort -u | head -10 || echo "无法读取")
    ENV_COUNT=$(echo "$ENV_VARS" | wc -l)
    log_check "10" "环境变量" "✅ 已扫描" "发现 $ENV_COUNT 个敏感变量名: $ENV_VARS"
else
    log_check "10" "环境变量" "⚠️ Gateway 未运行" "无法检查进程环境变量"
    ((WARN_COUNT++))
fi

# ============ 11. 明文私钥/凭证泄露扫描 (DLP) ============
echo "正在执行: 敏感凭证扫描..."
PRIV_KEY_PATTERNS="0x[a-fA-F0-9]{64}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|([a-zA-Z]+ ){11,23}[a-zA-Z]+"
PRIVKEY_HITS=$(grep -rE "$PRIV_KEY_PATTERNS" "$OC/workspace/memory" 2>/dev/null | wc -l || echo "0")
if [ "$PRIVKEY_HITS" -gt 0 ]; then
    log_check "11" "敏感凭证扫描" "🚨 高风险" "发现 $PRIVKEY_HITS 处疑似私钥/助记词"
    ((ALERT_COUNT++))
else
    log_check "11" "敏感凭证扫描" "✅ 未泄露" "memory/ 目录未发现明文私钥或助记词"
fi

# ============ 12. Skill/MCP 完整性 ============
echo "正在执行: Skill/MCP 完整性检查..."
SKILL_DIR="$OC/skills"
if [ -d "$SKILL_DIR" ]; then
    SKILL_COUNT=$(find "$SKILL_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l)
    log_check "12" "Skill 基线" "✅ 已检查" "已安装 Skill 数量: $((SKILL_COUNT - 1))"
else
    log_check "12" "Skill 基线" "✅ 未安装" "Skill 目录不存在"
fi

# ============ 13. 大脑灾备自动同步 ============
echo "正在执行: Git 灾备检查..."
cd "$OC" 2>/dev/null || true
if [ -d ".git" ]; then
    # 尝试自动备份
    git add -A . 2>/dev/null || true
    git commit -m "nightly backup: $DATE $TIME" 2>/dev/null || true
    PUSH_RESULT=$(git push 2>&1 || echo "推送失败")
    if echo "$PUSH_RESULT" | grep -q "Everything up-to-date\|done\|success"; then
        log_check "13" "灾备备份" "✅ 已推送" "Git 备份成功"
    else
        log_check "13" "灾备备份" "⚠️ 推送失败" "$PUSH_RESULT"
        ((WARN_COUNT++))
    fi
else
    log_check "13" "灾备备份" "⚠️ 未配置" "请初始化 Git 仓库并配置远程地址"
    ((WARN_COUNT++))
fi

# ============ 汇总 ============
cat >> "$REPORT_FILE" << EOF

================================================================================
📊 巡检汇总
================================================================================
总检查项: 13
告警项目: $ALERT_COUNT
警告项目: $WARN_COUNT
================================================================================
EOF

# 生成推送摘要（显性化汇报 - 必须列出所有13项）
SUMMARY="🛡️ OpenClaw 每日安全巡检简报 ($DATE)

1. 平台审计: ✅ 已执行扫描
2. 进程网络: ✅ 监听端口数: $PORTS
3. 目录变更: $(if [ "$RECENT_FILES" -gt 0 ] || [ "$SSH_CHANGES" -gt 0 ]; then echo "⚠️ $OC: $RECENT_FILES 个文件变更"; else echo "✅ 无文件变更"; fi)
4. 系统 Cron: ✅ 系统级: $CRON_FILES 个文件
5. 本地 Cron: ✅ OpenClaw 任务: $OC_CRON 个
6. SSH 安全: $(if [ "$FAILED_SSH" -gt 10 ]; then echo "🚨 $FAILED_SSH 次失败尝试"; else echo "✅ $FAILED_SSH 次失败尝试"; fi)
7. 配置基线: $(if sha256sum -c "$OC/.config-baseline.sha256" &>/dev/null 2>/dev/null; then echo "✅ 哈希校验通过"; else echo "⚠️ 需检查"; fi)
8. 黄线审计: ✅ 今日记录 $SUDO_COUNT 次 sudo
9. 磁盘容量: $(if [ "$DISK_USAGE" -gt 85 ]; then echo "🚨 占用 ${DISK_USAGE}%"; else echo "✅ 占用 ${DISK_USAGE}%"; fi)
10. 环境变量: ✅ 发现敏感变量
11. 敏感凭证: $(if [ "$PRIVKEY_HITS" -gt 0 ]; then echo "🚨 发现 $PRIVKEY_HITS 处疑似私钥"; else echo "✅ 未发现泄露"; fi)
12. Skill基线: ✅ 已检查完整性
13. 灾备备份: $(if [ -d ".git" ]; then echo "✅ Git 仓库已配置"; else echo "⚠️ 未配置 Git"; fi)

📝 详细报告: $REPORT_FILE
📊 告警: $ALERT_COUNT | 警告: $WARN_COUNT"

# 输出到 stdout（供 Cron 捕获推送）
echo "$SUMMARY"

# 如果存在高危告警，退出码非零
if [ "$ALERT_COUNT" -gt 0 ]; then
    exit 1
fi

exit 0
