#!/usr/bin/env python3
"""
EMA进场 + EA管理 简化回测
"""
import pandas as pd
import numpy as np

DATA_FILE = "/home/lilei/.openclaw/workspace/data/dukascopy/ms_aligned/XAUUSD_tick_combined_ms_aligned.csv"

# EMA参数
EMA_FAST, EMA_MID, EMA_SLOW = 20, 50, 200

# 两组EA参数
PARAMS_A = {'trailPct': 0.30, 'gTrailStart': 10.0, 'gTPDist': 13.0, 'l1Dist': 23.0, 'l2Dist': 45.0, 'l2Mult': 2.0, 'hardLoss': 220.0, 'seedLot': 0.01}
PARAMS_B = {'trailPct': 0.20, 'gTrailStart': 8.0, 'gTPDist': 9.0, 'l1Dist': 23.0, 'l2Dist': 45.0, 'l2Mult': 2.0, 'hardLoss': 220.0, 'seedLot': 0.01}

def backtest(df, params, name):
    """简化回测"""
    print(f"\n{'='*60}")
    print(f"回测: {name}")
    print(f"{'='*60}")
    
    # 计算EMA
    df['ema20'] = df['mid'].ewm(span=EMA_FAST).mean()
    df['ema50'] = df['mid'].ewm(span=EMA_MID).mean()
    df['ema200'] = df['mid'].ewm(span=EMA_SLOW).mean()
    
    # 趋势判断
    df['trend_up'] = (df['mid'] > df['ema20']) & (df['ema20'] > df['ema50']) & (df['ema50'] > df['ema200'])
    df['trend_down'] = (df['mid'] < df['ema20']) & (df['ema20'] < df['ema50']) & (df['ema50'] < df['ema200'])
    
    # 找进场点（EMA20回调）
    df['prev_mid'] = df['mid'].shift(1)
    df['long_signal'] = df['trend_up'] & (df['prev_mid'] <= df['ema20']) & (df['mid'] > df['ema20'])
    df['short_signal'] = df['trend_down'] & (df['prev_mid'] >= df['ema20']) & (df['mid'] < df['ema20'])
    
    # 每天最多1笔交易
    df['date'] = df['datetime'].dt.date
    df['signal_num'] = df.groupby('date').cumcount()
    signals = df[(df['long_signal'] | df['short_signal']) & (df['signal_num'] < 480)]  # 约1小时内第1个信号
    
    print(f"找到 {len(signals)} 个进场信号")
    
    if len(signals) == 0:
        return None
    
    # 简化的交易模拟
    trades = []
    for idx, row in signals.iterrows():
        direction = 1 if row['long_signal'] else -1
        entry = row['mid']
        
        # 简化：模拟到当日收盘
        day_data = df[df['date'] == row['date']]
        future = day_data[day_data.index > idx]
        
        if len(future) == 0:
            continue
        
        # 简化逻辑：检查是否触发止盈止损
        if direction == 1:
            tp = entry + params['gTPDist']
            sl = entry - params['hardLoss'] / (params['seedLot'] * 100)
            max_price = future['mid'].max()
            
            if max_price >= tp:
                exit_p = tp
                reason = 'TP'
                pnl = params['gTPDist'] * params['seedLot'] * 100
            elif future['mid'].min() <= sl:
                exit_p = sl
                reason = 'SL'
                pnl = -params['hardLoss']
            else:
                exit_p = future.iloc[-1]['mid']
                reason = 'Close'
                pnl = (exit_p - entry) * params['seedLot'] * 100
        else:
            tp = entry - params['gTPDist']
            sl = entry + params['hardLoss'] / (params['seedLot'] * 100)
            min_price = future['mid'].min()
            
            if min_price <= tp:
                exit_p = tp
                reason = 'TP'
                pnl = params['gTPDist'] * params['seedLot'] * 100
            elif future['mid'].max() >= sl:
                exit_p = sl
                reason = 'SL'
                pnl = -params['hardLoss']
            else:
                exit_p = future.iloc[-1]['mid']
                reason = 'Close'
                pnl = (entry - exit_p) * params['seedLot'] * 100
        
        trades.append({'pnl': pnl, 'reason': reason, 'dir': '多' if direction==1 else '空'})
    
    trades_df = pd.DataFrame(trades)
    total = len(trades_df)
    wins = len(trades_df[trades_df['pnl'] > 0])
    profit = trades_df[trades_df['pnl'] > 0]['pnl'].sum()
    loss = abs(trades_df[trades_df['pnl'] <= 0]['pnl'].sum())
    
    print(f"总交易: {total} | 盈利: {wins} ({wins/total*100:.1f}%) | 亏损: {total-wins}")
    print(f"净利润: ${profit-loss:.2f} | 盈利因子: {profit/loss:.2f}" if loss > 0 else "盈利因子: ∞")
    print(f"\n出场原因: {trades_df['reason'].value_counts().to_dict()}")
    
    return {'name': name, 'profit_factor': profit/loss if loss>0 else 0, 'net_profit': profit-loss, 'win_rate': wins/total*100 if total>0 else 0}

def main():
    print("📊 EMA进场 + EA管理 简化回测")
    print("="*60)
    
    df = pd.read_csv(DATA_FILE)
    df['datetime'] = pd.to_datetime(df['datetime'])
    print(f"数据: {df['datetime'].min()} 至 {df['datetime'].max()}")
    print(f"共 {len(df):,} 条 tick\n")
    
    results = []
    results.append(backtest(df, PARAMS_A, "参数组 A (回撤30% 止盈13$)"))
    results.append(backtest(df, PARAMS_B, "参数组 B (回撤20% 止盈9$)"))
    
    print(f"\n{'='*60}")
    print("📈 对比")
    print(f"{'='*60}")
    print(f"{'参数组':<30} {'PF':<8} {'净利$':<12} {'胜率%':<8}")
    print("-"*60)
    for r in results:
        if r:
            print(f"{r['name']:<30} {r['profit_factor']:<8.2f} {r['net_profit']:<12.2f} {r['win_rate']:<8.1f}")
    
    best = max(results, key=lambda x: x['profit_factor'] if x else 0)
    print(f"\n🏆 最优: {best['name']}")

if __name__ == "__main__":
    main()
