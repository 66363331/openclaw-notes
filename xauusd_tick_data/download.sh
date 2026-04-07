#!/bin/bash
# XAUUSD Tick Data Download Script
# Period: 2026-02-01 to 2026-04-03

DIR="/home/lilei/.openclaw/workspace/xauusd_tick_data"

echo "========================================"
echo "XAUUSD Tick Data 下载"
echo "时间范围: 2026-02-01 ~ 2026-04-03"
echo "========================================"

# February 2026
echo ""
echo "[1/3] 下载 2026年2月 数据..."
dukascopy-node \
  -i xauusd \
  --date-from 2026-02-01 \
  --date-to 2026-02-28 \
  -t tick \
  -f csv \
  --directory "$DIR" \
  --file-name "xauusd_2026-02_tick" \
  -v \
  2>&1 | tail -5

# March 2026
echo ""
echo "[2/3] 下载 2026年3月 数据..."
dukascopy-node \
  -i xauusd \
  --date-from 2026-03-01 \
  --date-to 2026-03-31 \
  -t tick \
  -f csv \
  --directory "$DIR" \
  --file-name "xauusd_2026-03_tick" \
  -v \
  2>&1 | tail -5

# April 2026 (1-3)
echo ""
echo "[3/3] 下载 2026年4月(1-3日) 数据..."
dukascopy-node \
  -i xauusd \
  --date-from 2026-04-01 \
  --date-to 2026-04-03 \
  -t tick \
  -f csv \
  --directory "$DIR" \
  --file-name "xauusd_2026-04_01-03_tick" \
  -v \
  2>&1 | tail -5

echo ""
echo "========================================"
echo "下载完成！文件列表："
ls -lh "$DIR"/*.csv 2>/dev/null || echo "未找到CSV文件"
echo "========================================"
