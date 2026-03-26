#!/usr/bin/env python3
"""
EA 参数优化脚本 - 精简版网格搜索
"""
import pandas as pd
import numpy as np
from itertools import product
import json

DATA_FILE = "/home/lilei/.openclaw/workspace/data/dukascopy/ms_aligned/XAUUSD_tick_combined_ms_aligned.csv"

# 精简参数边界 (3^5 = 243 种组合)
PARAM_RANGES = {
    'trailPct': [0.20, 0.25, 0.30],      # 回撤百分比
    'gTrailStart': [7.0, 9.0, 11.0],      # 追踪启动
    'gTPDist': [9.0, 11.0, 13.0],         # 主止盈
    'gLockDist': [3.0, 3.5, 4.0],         # 锁定触发
    'gLockSL': [1.0, 1.2, 1.5],           # 锁定利润
}

BASE_PARAMS = {
    'pyrStep': 3.0, 'pyrMax': 8, 'l1Dist': 23.0,
    'l2Dist': 45.0, 'l2Mult': 2.0, 'hardLoss': 220.0, 'seedLot': 0.01,
}

def load_data():
    print("📊 加载数据...")
    df = pd.read_csv(DATA_FILE)
    df['datetime'] = pd.to_datetime(df['datetime'])
    print(f"数据: {df['datetime'].min().date()} 至 {df['datetime'].max().date()}")
    print(f"共 {len(df):,} 条 tick 数据")
    total_combo = np.prod([len(v) for v in PARAM_RANGES.values()])
    print(f"搜索组合数: {total_combo} 种\n")
    return df

class EABacktest:
    def __init__(self, params, df):
        self.params = {**BASE_PARAMS, **params}
        self.df = df
        
    def run(self):
        self.df['date'] = self.df['datetime'].dt.date
        total_profit = total_loss = 0
        win_count = loss_count = 0
        max_dd = peak = equity = 0
        
        for _, group in self.df.groupby('date'):
            if len(group) < 100: continue
            entry = group.iloc[0]['mid']
            deltas = group['mid'].values - entry  # 假设做多
            
            peak_delta = trailing = 0
            pnl = deltas[-1] * self.params['seedLot'] * 100  # 默认收盘
            
            for d in deltas:
                if d > peak_delta: peak_delta = d
                if not trailing and d >= self.params['gTrailStart']: trailing = True
                if trailing and d <= peak_delta * (1 - self.params['trailPct']):
                    pnl = d * self.params['seedLot'] * 100
                    break
                if not trailing and d >= self.params['gTPDist']:
                    pnl = self.params['gTPDist'] * self.params['seedLot'] * 100
                    break
                if d <= -self.params['hardLoss'] / (self.params['seedLot'] * 100):
                    pnl = -self.params['hardLoss']
                    break
            
            equity += pnl
            if equity > peak: peak = equity
            max_dd = max(max_dd, peak - equity)
            if pnl > 0: total_profit += pnl; win_count += 1
            else: total_loss += abs(pnl); loss_count += 1
        
        total = win_count + loss_count
        if total == 0: return None
        return {
            'trades': total, 'wins': win_count, 'losses': loss_count,
            'win_rate': win_count/total*100,
            'profit_factor': total_profit/total_loss if total_loss else 0,
            'net_profit': total_profit - total_loss,
            'max_drawdown': max_dd,
        }

def score(r):
    if not r or r['profit_factor'] <= 0: return -999
    return (min(r['profit_factor']/3, 1)*40 + min(r['net_profit']/300, 1)*30 + 
            min(r['win_rate']/90, 1)*20 + max(0, 1-r['max_drawdown']/100)*10)

def main():
    df = load_data()
    
    print("🔍 开始优化搜索...\n")
    best_score, best_params, best_result = -999, None, None
    all_results = []
    param_names = list(PARAM_RANGES.keys())
    param_values = list(PARAM_RANGES.values())
    
    for i, combo in enumerate(product(*param_values)):
        params = dict(zip(param_names, combo))
        result = EABacktest(params, df).run()
        if not result: continue
        
        s = score(result)
        all_results.append({'params': params, 'result': result, 'score': s})
        
        if s > best_score:
            best_score, best_params, best_result = s, params, result
            print(f"✨ 新最优 #{i+1}: 评分={s:.1f} | PF={result['profit_factor']:.2f} | 净利=${result['net_profit']:.1f} | 胜率={result['win_rate']:.1f}%")
    
    # 输出结果
    print(f"\n{'='*70}")
    print("🏆 最优参数组合")
    print(f"{'='*70}\n")
    
    print(f"📋 核心参数:")
    print(f"  峰值回撤百分比: {best_params['trailPct']*100:.0f}%")
    print(f"  追踪启动阈值:   {best_params['gTrailStart']:.0f}$")
    print(f"  主止盈:         {best_params['gTPDist']:.0f}$")
    print(f"  锁定触发:       {best_params['gLockDist']:.1f}$")
    print(f"  锁定利润:       {best_params['gLockSL']:.1f}$")
    
    print(f"\n📈 回测结果:")
    print(f"  盈利因子: {best_result['profit_factor']:.2f}")
    print(f"  净利润:   ${best_result['net_profit']:.2f}")
    print(f"  胜率:     {best_result['win_rate']:.2f}%")
    print(f"  交易次数: {best_result['trades']} 次")
    print(f"  最大回撤: ${best_result['max_drawdown']:.2f}")
    
    print(f"\n{'='*70}")
    print("📝 MT5 G06 止盈设置")
    print(f"{'='*70}")
    print(f"出场预设 = EXIT_ASIA")
    print(f"峰值回撤百分比 = {best_params['trailPct']:.2f}")
    print(f"微调-主止盈 = +{best_params['gTPDist'] - 9.0:.1f}")
    print(f"微调-锁定触发 = {best_params['gLockDist'] - 4.0:.1f}")
    print(f"微调-锁定利润 = {best_params['gLockSL'] - 1.7:.1f}")
    print(f"微调-追踪启动 = +{best_params['gTrailStart'] - 5.0:.1f}")
    
    # TOP 5
    print(f"\n{'='*70}")
    print("🔥 TOP 5 备选参数")
    print(f"{'='*70}")
    sorted_r = sorted(all_results, key=lambda x: x['score'], reverse=True)
    print(f"{'排名':<4} {'评分':<8} {'PF':<6} {'净利$':<10} {'胜率%':<8} {'参数(回撤|启动|止盈|锁触|锁利)'}")
    print("-" * 85)
    for i, rec in enumerate(sorted_r[:5], 1):
        r, p = rec['result'], rec['params']
        param_s = f"{p['trailPct']*100:.0f}%|{p['gTrailStart']:.0f}|{p['gTPDist']:.0f}|{p['gLockDist']:.1f}|{p['gLockSL']:.1f}"
        print(f"{i:<4} {rec['score']:<8.1f} {r['profit_factor']:<6.2f} {r['net_profit']:<10.2f} {r['win_rate']:<8.1f} {param_s}")
    
    # 保存
    with open("/home/lilei/.openclaw/workspace/data/best_params.json", 'w') as f:
        json.dump({'best': {'params': best_params, 'result': best_result, 'score': best_score}, 
                   'top5': [{'params': r['params'], 'score': r['score']} for r in sorted_r[:5]]}, f)
    print(f"\n✓ 结果已保存")

if __name__ == "__main__":
    main()
