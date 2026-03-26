#!/usr/bin/env python3
"""
XAU/USD 15分钟 ATR 计算工具
支持从多个数据源获取数据并交叉核对

安装依赖:
pip install yfinance pandas numpy
"""

import pandas as pd
import numpy as np
import json
from datetime import datetime, timedelta

# 尝试导入yfinance
try:
    import yfinance as yf
    YFINANCE_AVAILABLE = True
except ImportError:
    YFINANCE_AVAILABLE = False
    print("警告: yfinance未安装，请运行: pip install yfinance")

def calculate_atr(df, period=14):
    """
    计算ATR (Average True Range)
    
    TR = max(high - low, |high - prev_close|, |low - prev_close|)
    ATR = TR的N日简单移动平均
    """
    df = df.copy()
    
    # 计算True Range
    df['prev_close'] = df['Close'].shift(1)
    df['tr1'] = df['High'] - df['Low']
    df['tr2'] = abs(df['High'] - df['prev_close'])
    df['tr3'] = abs(df['Low'] - df['prev_close'])
    df['TR'] = df[['tr1', 'tr2', 'tr3']].max(axis=1)
    
    # 计算ATR
    df['ATR'] = df['TR'].rolling(window=period).mean()
    
    return df

def get_yahoo_data(symbol, period="20d", interval="15m"):
    """
    从Yahoo Finance获取数据
    symbol: GC=F (黄金期货), XAUUSD=X (黄金/美元)
    """
    if not YFINANCE_AVAILABLE:
        return None
    
    try:
        ticker = yf.Ticker(symbol)
        df = ticker.history(period=period, interval=interval)
        if len(df) == 0:
            return None
        return df
    except Exception as e:
        print(f"Yahoo Finance获取失败 ({symbol}): {e}")
        return None

def analyze_atr(df, label=""):
    """
    分析ATR数据
    """
    if df is None or len(df) == 0:
        return None
    
    # 计算ATR
    df = calculate_atr(df)
    
    # 获取最近20个工作日的数据
    # 注意: Yahoo的15分钟数据可能不包含完整的20个工作日
    recent_data = df.dropna(subset=['ATR'])
    
    if len(recent_data) == 0:
        return None
    
    # 统计信息
    stats = {
        "数据源": label,
        "数据条数": len(recent_data),
        "当前ATR": round(recent_data['ATR'].iloc[-1], 4),
        "平均ATR(20周期)": round(recent_data['ATR'].tail(20).mean(), 4),
        "最大ATR(20周期)": round(recent_data['ATR'].tail(20).max(), 4),
        "最小ATR(20周期)": round(recent_data['ATR'].tail(20).min(), 4),
        "ATR波动率": round(recent_data['ATR'].tail(20).std(), 4)
    }
    
    return stats

def main():
    print("=" * 60)
    print("XAU/USD 15分钟 ATR 分析工具")
    print("=" * 60)
    print()
    
    results = []
    
    # 数据源1: 黄金期货 (GC=F)
    print("[1/2] 从 Yahoo Finance 获取黄金期货(GC=F)数据...")
    df1 = get_yahoo_data("GC=F", period="25d", interval="15m")
    if df1 is not None:
        stats1 = analyze_atr(df1, "Yahoo Finance (GC=F 期货)")
        if stats1:
            results.append(stats1)
            print(f"✓ 成功获取 {stats1['数据条数']} 条数据")
    
    print()
    
    # 数据源2: 黄金/美元 (XAUUSD=X)
    print("[2/2] 从 Yahoo Finance 获取XAU/USD数据...")
    df2 = get_yahoo_data("XAUUSD=X", period="25d", interval="15m")
    if df2 is not None:
        stats2 = analyze_atr(df2, "Yahoo Finance (XAUUSD)")
        if stats2:
            results.append(stats2)
            print(f"✓ 成功获取 {stats2['数据条数']} 条数据")
    
    print()
    print("=" * 60)
    print("分析结果")
    print("=" * 60)
    
    if len(results) == 0:
        print("未能获取任何数据，请检查网络连接或稍后重试")
        return
    
    for r in results:
        print()
        print(f"【{r['数据源']}】")
        for key, value in r.items():
            if key != "数据源":
                print(f"  {key}: {value}")
    
    # 交叉核对
    if len(results) >= 2:
        print()
        print("=" * 60)
        print("交叉核对")
        print("=" * 60)
        
        atr_values = [r['平均ATR(20周期)'] for r in results]
        diff = abs(atr_values[0] - atr_values[1])
        avg_atr = np.mean(atr_values)
        diff_pct = (diff / avg_atr) * 100
        
        print(f"数据源1 ATR: {atr_values[0]}")
        print(f"数据源2 ATR: {atr_values[1]}")
        print(f"差异: {round(diff, 4)} ({round(diff_pct, 2)}%)")
        
        if diff_pct < 5:
            print("✓ 数据一致性良好 (差异 < 5%)")
        elif diff_pct < 10:
            print("⚠ 数据有一定差异 (差异 5-10%)")
        else:
            print("✗ 数据差异较大 (差异 > 10%)，建议人工核对")
        
        print()
        print(f"建议使用的ATR参考值: {round(avg_atr, 4)}")
    
    print()
    print("=" * 60)
    print("与OANDA对比")
    print("=" * 60)
    print("请从OANDA平台查看XAU/USD 15分钟ATR数值")
    print("如果与本结果差异较大，可能是：")
    print("  1. 数据来源不同（期货vs现货）")
    print("  2. 时间戳对齐差异")
    print("  3. ATR计算周期设置不同")

if __name__ == "__main__":
    main()
