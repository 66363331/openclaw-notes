#!/usr/bin/env python3
"""
基于数据统计的最优参数推荐
分析 tick 数据特征，推荐最优参数
"""
import pandas as pd
import numpy as np

DATA_FILE = "/home/lilei/.openclaw/workspace/data/dukascopy/ms_aligned/XAUUSD_tick_combined_ms_aligned.csv"

def analyze_data():
    """分析数据特征"""
    print("📊 加载并分析数据...")
    df = pd.read_csv(DATA_FILE)
    df['datetime'] = pd.to_datetime(df['datetime'])
    df['date'] = df['datetime'].dt.date
    
    print(f"\n数据范围: {df['datetime'].min()} 至 {df['datetime'].max()}")
    print(f"总数据量: {len(df):,} 条")
    
    # 计算每日波动特征
    daily_stats = []
    for date, group in df.groupby('date'):
        if len(group) < 100:
            continue
        
        high = group['mid'].max()
        low = group['mid'].min()
        open_p = group.iloc[0]['mid']
        close_p = group.iloc[-1]['mid']
        
        range_val = high - low
        volatility = group['mid'].std()
        
        daily_stats.append({
            'date': date,
            'range': range_val,
            'volatility': volatility,
            'open': open_p,
            'close': close_p,
            'change': abs(close_p - open_p),
        })
    
    stats_df = pd.DataFrame(daily_stats)
    
    print(f"\n📈 日线统计:")
    print(f"  分析天数: {len(stats_df)}")
    print(f"  日均波幅: ${stats_df['range'].mean():.2f} (最小${stats_df['range'].min():.2f}, 最大${stats_df['range'].max():.2f})")
    print(f"  日均波动率: ${stats_df['volatility'].mean():.2f}")
    print(f"  日涨跌中位数: ${stats_df['change'].median():.2f}")
    
    # 分位数分析
    print(f"\n📊 波幅分位数:")
    for q in [0.25, 0.5, 0.75, 0.9]:
        print(f"  {int(q*100)}%: ${stats_df['range'].quantile(q):.2f}")
    
    return stats_df

def recommend_params(stats_df):
    """基于数据特征推荐参数"""
    avg_range = stats_df['range'].mean()
    median_range = stats_df['range'].median()
    p75_range = stats_df['range'].quantile(0.75)
    
    print(f"\n{'='*70}")
    print("🎯 基于数据特征的最优参数推荐")
    print(f"{'='*70}\n")
    
    # 追踪启动阈值
    # 应该大于日均波幅的某个比例，避免过早启动
    trail_start_recommend = max(6.0, round(median_range * 0.35, 0))
    
    # 主止盈
    # 基于75%分位数，确保大多数日子能触达
    tp_recommend = round(p75_range * 0.4, 0)
    
    # 回撤百分比
    # 波幅越大，回撤容忍度应越高
    if avg_range > 50:
        trail_pct = 0.30  # 大波动用30%
    elif avg_range > 35:
        trail_pct = 0.25  # 中等波动用25%
    else:
        trail_pct = 0.20  # 小波动用20%
    
    # 锁定触发 - 保本线
    lock_trigger = round(trail_start_recommend * 0.35, 1)
    
    # 锁定利润
    lock_profit = round(lock_trigger * 0.3, 1)
    
    print("📋 推荐参数:")
    print(f"  峰值回撤百分比: {trail_pct*100:.0f}%")
    print(f"  追踪启动阈值:   {trail_start_recommend:.0f}$")
    print(f"  主止盈:         {tp_recommend:.0f}$")
    print(f"  锁定触发:       {lock_trigger:.1f}$")
    print(f"  锁定利润:       {lock_profit:.1f}$")
    
    print(f"\n📋 MT5 G06 止盈设置:")
    print(f"出场预设 = EXIT_ASIA")
    print(f"峰值回撤百分比 = {trail_pct:.2f}")
    print(f"微调-主止盈 = +{tp_recommend - 9.0:.1f}")
    print(f"微调-锁定触发 = {lock_trigger - 4.0:.1f}")
    print(f"微调-锁定利润 = {lock_profit - 1.7:.1f}")
    print(f"微调-追踪启动 = +{trail_start_recommend - 5.0:.1f}")
    
    print(f"\n💡 参数设计逻辑:")
    print(f"  1. 追踪启动 {trail_start_recommend:.0f}$ = 日均波幅 {median_range:.1f}$ × 35%")
    print(f"     目的: 避免日内小波动过早触发追踪")
    print(f"  2. 主止盈 {tp_recommend:.0f}$ = 75%分位波幅 {p75_range:.1f}$ × 40%")
    print(f"     目的: 确保75%的交易日能触达主止盈")
    print(f"  3. 回撤 {trail_pct*100:.0f}% 基于日均波幅 ${avg_range:.1f}")
    print(f"     目的: 给趋势足够空间，同时保护利润")
    print(f"  4. 锁定触发 {lock_trigger:.1f}$ ≈ 追踪启动的35%")
    print(f"     目的: 早期保本，降低风险")
    
    # 备选参数
    print(f"\n{'='*70}")
    print("🔥 备选参数组合（根据风险偏好选择）")
    print(f"{'='*70}\n")
    
    scenarios = [
        ("激进型", 0.35, trail_start_recommend + 2, tp_recommend + 2, lock_trigger + 0.5),
        ("平衡型", trail_pct, trail_start_recommend, tp_recommend, lock_trigger),
        ("保守型", 0.20, trail_start_recommend - 2, tp_recommend - 2, lock_trigger - 0.5),
    ]
    
    print(f"{'风格':<10} {'回撤%':<8} {'启动$':<8} {'止盈$':<8} {'锁触$':<8} {'特点'}")
    print("-" * 70)
    for name, pct, start, tp, lock in scenarios:
        desc = "高盈利潜力，波动大" if name=="激进型" else ("稳健盈利，风险低" if name=="保守型" else "平衡收益与风险")
        print(f"{name:<10} {pct*100:.0f}%       {start:.0f}$      {tp:.0f}$      {lock:.1f}$      {desc}")
    
    return {
        'trailPct': trail_pct,
        'gTrailStart': trail_start_recommend,
        'gTPDist': tp_recommend,
        'gLockDist': lock_trigger,
        'gLockSL': lock_profit,
    }

def main():
    stats_df = analyze_data()
    best_params = recommend_params(stats_df)
    
    # 保存推荐
    import json
    with open("/home/lilei/.openclaw/workspace/data/recommended_params.json", 'w') as f:
        json.dump(best_params, f, indent=2)
    print(f"\n✓ 推荐参数已保存至: recommended_params.json")

if __name__ == "__main__":
    main()
