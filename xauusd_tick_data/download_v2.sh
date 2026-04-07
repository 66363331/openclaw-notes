#!/bin/bash
# XAUUSD Tick Data Download Script v2
# Period: 2026-02-01 to 2026-04-03
# 优化：逐月下载 + 失败重试 + 限速保护

DIR="/home/lilei/.openclaw/workspace/xauusd_tick_data"
MAX_RETRIES=3

echo "========================================"
echo "XAUUSD Tick Data 下载 v2"
echo "时间范围: 2026-02-01 ~ 2026-04-03"
echo "========================================"

download_month() {
    local month_name=$1
    local date_from=$2
    local date_to=$3
    local filename=$4
    
    echo ""
    echo "[$month_name] 下载 $date_from ~ $date_to ..."
    
    for i in $(seq 1 $MAX_RETRIES); do
        echo "  第 $i 次尝试..."
        
        dukascopy-node \
            -i xauusd \
            --date-from "$date_from" \
            --date-to "$date_to" \
            -t tick \
            -f csv \
            --directory "$DIR" \
            --file-name "$filename" \
            -bs 5 \
            -bp 2000 \
            --retries 2 \
            -re \
            2>&1 | tail -10
        
        # 检查文件是否有内容
        if [ -f "$DIR/${filename}.csv" ] && [ -s "$DIR/${filename}.csv" ]; then
            local lines=$(wc -l < "$DIR/${filename}.csv")
            local size=$(du -h "$DIR/${filename}.csv" | cut -f1)
            echo "  ✅ 成功！文件: ${size}, 行数: $lines"
            return 0
        else
            echo "  ❌ 失败，10秒后重试..."
            sleep 10
        fi
    done
    
    echo "  ⚠️ $month_name 下载失败，跳过"
    return 1
}

# 2月
download_month "2月" "2026-02-01" "2026-02-28" "xauusd_2026-02_tick"

echo ""
echo "  等待15秒避免限速..."
sleep 15

# 3月
download_month "3月" "2026-03-01" "2026-03-31" "xauusd_2026-03_tick"

echo ""
echo "  等待15秒避免限速..."
sleep 15

# 4月 (1-3日)
download_month "4月(1-3)" "2026-04-01" "2026-04-03" "xauusd_2026-04_01-03_tick"

echo ""
echo "========================================"
echo "下载完成！文件列表："
ls -lh "$DIR"/*.csv 2>/dev/null
echo "========================================"
