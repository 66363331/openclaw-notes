#!/usr/bin/env python3
"""
EA 参数优化脚本 - 网格搜索寻找最优解
优化目标：最大化盈利因子，同时保持合理胜率
"""
import pandas as pd
import numpy as np
from datetime import datetime
from itertools import product
import json

# 加载 tick 数据
DATA_FILE = "/home/lilei/.openclaw/workspace/data/dukascopy/ms_aligned/XAUUSD_tick_combined_ms_aligned.csv"

# 参数边界设计
PARAM_RANGES = {
    'trailPct': [0.15, 0.20, 0.25, 0.30, 0.35],      # 回撤百分比 15%-35%
    'gTrailStart': [6.0, 7.0, 8.0, 9.0, 10.0, 11.0], # 追踪启动 6-11
    'gTPDist': [8.0, 9.0, 10.0, 11.0, 12.0, 13.0],   # 主止盈 8-13
    'gLockDist': [2.5, 3.0, 3.5, 4.0, 4.5],          # 锁定触发 2.5-4.5
    'gLockSL': [0.8, 1.0, 1.2, 1.5],                  # 锁定利润 0.8-1.5
}

# 固定参数
BASE_PARAMS = {
    'pyrStep': 3.0,
    'pyrMax': 8,
    'l1Dist': 23.0,
    'l2Dist': 45.0,
    'l2Mult': 2.0,
    'hardLoss': 220.0,
    'seedLot': 0.01,
}

def load_data():
    """加载 tick 数据"""
    print("加载数据...")
    df = pd.read_csv(DATA_FILE)
    df['datetime'] = pd.to_datetime(df['datetime'])
    print(f"数据范围: {df['datetime'].min()} 至 {df['datetime'].max()}")
    print(f"总数据量: {len(df):,} 条")
    print(f"\n参数搜索空间: {np.prod([len(v) for v in PARAM_RANGES.values()])} 种组合")
    return df

class EABacktest:
    """EA 回测引擎"""
    def __init__(self, params, df):
        self.params = {**BASE_PARAMS, **params}
        self.df = df
        
    def run(self):
        """运行回测"""
        self.df['date'] = self.df['datetime'].dt.date
        
        total_profit = 0
        total_loss = 0
        win_count = 0
        loss_count = 0
        max_drawdown = 0
        peak_equity = 0
        equity = 0
        
        for date, group in self.df.groupby('date'):
            if len(group) < 100:
                continue
                
            entry_price = group.iloc[0]['mid']
            direction = 1
            
            pnl = self.simulate_trade(entry_price, direction, group)
            
            equity += pnl
            if equity > peak_equity:
                peak_equity = equity
            drawdown = peak_equity - equity
            if drawdown > max_drawdown:
                max_drawdown = drawdown
            
            if pnl > 0:
                total_profit += pnl
                win_count += 1
            else:
                total_loss += abs(pnl)
                loss_count += 1
                
        total_trades = win_count + loss_count
        if total_trades == 0:
            return None
            
        win_rate = win_count / total_trades * 100
        profit_factor = total_profit / total_loss if total_loss > 0 else 0
        net_profit = total_profit - total_loss
        
        return {
            'total_trades': total_trades,
            'win_count': win_count,
            'loss_count': loss_count,
            'win_rate': win_rate,
            'profit_factor': profit_factor,
            'net_profit': net_profit,
            'total_profit': total_profit,
            'total_loss': total_loss,
            'max_drawdown': max_drawdown,
        }
    
    def simulate_trade(self, entry_price, direction, price_series):
        """模拟单笔交易"""
        p = self.params
        
        if direction == 1:
            deltas = price_series['mid'].values - entry_price
        else:
            deltas = entry_price - price_series['mid'].values
            
        peak_delta = 0
        trailing = False
        
        for delta in deltas:
            if delta > peak_delta:
                peak_delta = delta
                
            if not trailing and delta >= p['gTrailStart']:
                trailing = True
                
            if trailing:
                exit_threshold = peak_delta * (1 - p['trailPct'])
                if delta <= exit_threshold:
                    return delta * p['seedLot'] * 100
                    
            if not trailing and delta >= p['gTPDist']:
                return p['gTPDist'] * p['seedLot'] * 100
                
            if delta <= -p['hardLoss'] / (p['seedLot'] * 100):
                return -p['hardLoss']
                
        return deltas[-1] * p['seedLot'] * 100

def calculate_score(result):
    """计算综合评分
    权重：盈利因子 40%，净利润 30%，胜率 20%，回撤控制 10%
    """
    if result is None or result['profit_factor'] <= 0:
        return -999
    
    pf_score = min(result['profit_factor'] / 3.0, 1.0) * 40  # 盈利因子满分3.0
    np_score = min(result['net_profit'] / 300, 1.0) * 30     # 净利润满分300
    wr_score = min(result['win_rate'] / 90, 1.0) * 20        # 胜率满分90%
    dd_score = max(0, 1 - result['max_drawdown'] / 100) * 10 # 回撤越小越好
    
    return pf_score + np_score + wr_score + dd_score

def grid_search(df):
    """网格搜索最优参数"""
    print(f"\n{'='*70}")
    print("🔍 开始网格搜索最优参数")
    print(f"{'='*70}\n")
    
    best_score = -999
    best_params = None
    best_result = None
    all_results = []
    
    # 生成所有参数组合
    param_names = list(PARAM_RANGES.keys())
    param_values = list(PARAM_RANGES.values())
    total_combinations = np.prod([len(v) for v in param_values])
    
    tested = 0
    
    for combination in product(*param_values):
        params = dict(zip(param_names, combination))
        
        backtest = EABacktest(params, df)
        result = backtest.run()
        
        if result is None:
            continue
            
        score = calculate_score(result)
        
        record = {
            'params': params,
            'result': result,
            'score': score
        }
        all_results.append(record)
        
        if score > best_score:
            best_score = score
            best_params = params
            best_result = result
            print(f"✨ 找到更优解 #{tested+1}: 评分={score:.2f}, PF={result['profit_factor']:.2f}, NP=${result['net_profit']:.2f}")
        
        tested += 1
        if tested % 100 == 0:
            print(f"  进度: {tested}/{total_combinations} ({tested/total_combinations*100:.1f}%)")
    
    return best_params, best_result, best_score, all_results

def print_top_results(all_results, top_n=10):
    """打印前N个最优结果"""
    sorted_results = sorted(all_results, key=lambda x: x['score'], reverse=True)
    
    print(f"\n{'='*70}")
    print(f"🏆 TOP {top_n} 最优参数组合")
    print(f"{'='*70}\n")
    
    print(f"{'排名':<4} {'评分':<8} {'PF':<6} {'净利润':<10} {'胜率%':<8} {'回撤$':<8} {'参数组合'}")
    print("-" * 110)
    
    for i, record in enumerate(sorted_results[:top_n], 1):
        r = record['result']
        p = record['params']
        param_str = f"回撤{p['trailPct']*100:.0f}%|启动{p['gTrailStart']:.0f}|止盈{p['gTPDist']:.0f}|锁触{p['gLockDist']:.1f}|锁利{p['gLockSL']:.1f}"
        print(f"{i:<4} {record['score']:<8.2f} {r['profit_factor']:<6.2f} ${r['net_profit']:<9.2f} {r['win_rate']:<8.2f} ${r['max_drawdown']:<8.2f} {param_str}")

def main():
    df = load_data()
    
    # 执行网格搜索
    best_params, best_result, best_score, all_results = grid_search(df)
    
    # 打印最优结果
    print(f"\n{'='*70}")
    print("🎯 最优参数组合")
    print(f"{'='*70}\n")
    
    print("最优参数:")
    print(f"  峰值回撤百分比 (trailPct): {best_params['trailPct']*100:.0f}%")
    print(f"  追踪启动阈值 (gTrailStart): {best_params['gTrailStart']:.1f}$")
    print(f"  主止盈 (gTPDist): {best_params['gTPDist']:.1f}$")
    print(f"  锁定触发 (gLockDist): {best_params['gLockDist']:.1f}$")
    print(f"  锁定利润 (gLockSL): {best_params['gLockSL']:.1f}$")
    
    print(f"\n回测结果:")
    print(f"  盈利因子: {best_result['profit_factor']:.2f}")
    print(f"  净利润: ${best_result['net_profit']:.2f}")
    print(f"  胜率: {best_result['win_rate']:.2f}%")
    print(f"  总交易: {best_result['total_trades']} 次")
    print(f"  最大回撤: ${best_result['max_drawdown']:.2f}")
    print(f"  综合评分: {best_score:.2f}")
    
    # 打印 MT5 设置格式
    print(f"\n{'='*70}")
    print("📋 MT5 G06 止盈参数设置")
    print(f"{'='*70}")
    print(f"出场预设 = EXIT_ASIA")
    print(f"峰值回撤百分比 = {best_params['trailPct']:.2f}")
    print(f"微调-主止盈 = +{best_params['gTPDist'] - 9.0:.1f} (实际 {best_params['gTPDist']:.1f}$)")
    print(f"微调-锁定触发 = {best_params['gLockDist'] - 4.0:.1f} (实际 {best_params['gLockDist']:.1f}$)")
    print(f"微调-锁定利润 = {best_params['gLockSL'] - 1.7:.1f} (实际 {best_params['gLockSL']:.1f}$)")
    print(f"微调-追踪启动 = +{best_params['gTrailStart'] - 5.0:.1f} (实际 {best_params['gTrailStart']:.1f}$)")
    
    # 打印TOP10
    print_top_results(all_results, 10)
    
    # 保存结果
    output_file = "/home/lilei/.openclaw/workspace/data/optimization_results.json"
    with open(output_file, 'w') as f:
        json.dump({
            'best_params': best_params,
            'best_result': best_result,
            'best_score': best_score,
            'top_10': [
                {
                    'params': r['params'],
                    'result': r['result'],
                    'score': r['score']
                } for r in sorted(all_results, key=lambda x: x['score'], reverse=True)[:10]
            ]
        }, f, indent=2)
    print(f"\n✓ 详细结果已保存至: {output_file}")

if __name__ == "__main__":
    main()
