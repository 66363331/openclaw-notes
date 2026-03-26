#!/usr/bin/env python3
"""
EA 真实交易模拟 - 手动开仓 + EA接管模式
"""
import pandas as pd
import numpy as np

DATA_FILE = "/home/lilei/.openclaw/workspace/data/dukascopy/ms_aligned/XAUUSD_tick_combined_ms_aligned.csv"

PARAMS_A = {
    'name': '参数组 A',
    'trailPct': 0.30, 'gTrailStart': 10.0, 'gTPDist': 13.0,
    'gLockDist': 3.0, 'gLockSL': 1.0,
    'pyrStep': 3.0, 'pyrMax': 8,
    'l1Dist': 23.0, 'l2Dist': 45.0, 'l2Mult': 2.0,
    'hardLoss': 220.0, 'seedLot': 0.01,
}

PARAMS_B = {
    'name': '参数组 B',
    'trailPct': 0.20, 'gTrailStart': 8.0, 'gTPDist': 9.0,
    'gLockDist': 4.0, 'gLockSL': 1.2,
    'pyrStep': 3.0, 'pyrMax': 8,
    'l1Dist': 23.0, 'l2Dist': 45.0, 'l2Mult': 2.0,
    'hardLoss': 220.0, 'seedLot': 0.01,
}

class EASimulator:
    """EA 模拟器"""
    def __init__(self, params):
        self.p = params
        
    def simulate_day(self, day_df, direction):
        """模拟一天的交易
        direction: 1=做多(手动开仓), -1=做空(手动开仓)
        """
        prices = day_df['mid'].values
        if len(prices) < 100:
            return None
            
        # 手动开仓（开盘后第一根价格）
        entry_price = prices[0]
        
        # 持仓结构
        positions = [{'type': 'seed', 'price': entry_price, 'lot': self.p['seedLot']}]
        
        # 状态
        peak_delta = 0
        trailing = False
        l1_opened = False
        l2_opened = False
        
        breakeven = entry_price
        total_lots = self.p['seedLot']
        
        exit_price = prices[-1]  # 默认收盘
        exit_reason = "收盘"
        pnl = 0
        max_positions = 1
        
        for i, price in enumerate(prices[1:], 1):
            # 计算当前浮盈
            if direction == 1:  # 做多
                delta = price - breakeven
                
                # 金字塔加仓（浮盈>0且步距满足）
                if delta > 0 and len([p for p in positions if p['type']=='pyramid']) < self.p['pyrMax']:
                    ref = max(p['price'] for p in positions if p['type'] in ['seed','pyramid'])
                    if price - ref >= self.p['pyrStep']:
                        positions.append({'type': 'pyramid', 'price': price, 'lot': self.p['seedLot']})
                        total_lots += self.p['seedLot']
                        breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                        max_positions = max(max_positions, len(positions))
                
                # 马丁补仓 L1/L2
                lowest = min(p['price'] for p in positions)
                dist = price - lowest
                if not l1_opened and dist <= -self.p['l1Dist']:
                    positions.append({'type': 'l1', 'price': price, 'lot': self.p['seedLot']})
                    total_lots += self.p['seedLot']
                    l1_opened = True
                    breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                    max_positions = max(max_positions, len(positions))
                elif l1_opened and not l2_opened and dist <= -self.p['l2Dist']:
                    l2_lot = self.p['seedLot'] * self.p['l2Mult']
                    positions.append({'type': 'l2', 'price': price, 'lot': l2_lot})
                    total_lots += l2_lot
                    l2_opened = True
                    breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                    max_positions = max(max_positions, len(positions))
                    
            else:  # 做空
                delta = breakeven - price
                
                # 金字塔加仓
                if delta > 0 and len([p for p in positions if p['type']=='pyramid']) < self.p['pyrMax']:
                    ref = min(p['price'] for p in positions if p['type'] in ['seed','pyramid'])
                    if ref - price >= self.p['pyrStep']:
                        positions.append({'type': 'pyramid', 'price': price, 'lot': self.p['seedLot']})
                        total_lots += self.p['seedLot']
                        breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                        max_positions = max(max_positions, len(positions))
                
                # 马丁补仓
                highest = max(p['price'] for p in positions)
                dist = highest - price
                if not l1_opened and dist <= -self.p['l1Dist']:
                    positions.append({'type': 'l1', 'price': price, 'lot': self.p['seedLot']})
                    total_lots += self.p['seedLot']
                    l1_opened = True
                    breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                    max_positions = max(max_positions, len(positions))
                elif l1_opened and not l2_opened and dist <= -self.p['l2Dist']:
                    l2_lot = self.p['seedLot'] * self.p['l2Mult']
                    positions.append({'type': 'l2', 'price': price, 'lot': l2_lot})
                    total_lots += l2_lot
                    l2_opened = True
                    breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                    max_positions = max(max_positions, len(positions))
            
            # 更新峰值
            if delta > peak_delta:
                peak_delta = delta
            
            # 追踪启动
            if not trailing and delta >= self.p['gTrailStart']:
                trailing = True
            
            # 追踪止盈
            if trailing:
                exit_line = peak_delta * (1 - self.p['trailPct'])
                if delta <= exit_line:
                    exit_price = price
                    exit_reason = f"追踪({self.p['trailPct']*100:.0f}%)"
                    pnl = delta * total_lots * 100
                    break
            
            # 主止盈
            if not trailing and delta >= self.p['gTPDist']:
                exit_price = price
                exit_reason = f"主止盈({self.p['gTPDist']:.0f}$)"
                pnl = self.p['gTPDist'] * total_lots * 100
                break
            
            # 硬止损
            if delta <= -self.p['hardLoss'] / (total_lots * 100):
                exit_price = price
                exit_reason = f"硬止损({self.p['hardLoss']:.0f}$)"
                pnl = -self.p['hardLoss']
                break
        else:
            # 收盘结算
            pnl = (exit_price - breakeven) * total_lots * 100 if direction == 1 else (breakeven - exit_price) * total_lots * 100
        
        return {
            'entry': entry_price,
            'exit': exit_price,
            'pnl': pnl,
            'reason': exit_reason,
            'direction': '多' if direction == 1 else '空',
            'positions': max_positions,
            'lots': total_lots,
            'l1': l1_opened,
            'l2': l2_opened,
            'peak_delta': peak_delta,
        }

def run_backtest(params, df, mode='alternate'):
    """运行回测
    mode: 'long'=每天做多, 'short'=每天做空, 'alternate'=多空交替
    """
    print(f"\n{'='*70}")
    print(f"回测: {params['name']} | 模式: {mode}")
    print(f"参数: 回撤{params['trailPct']*100:.0f}% | 启动{params['gTrailStart']:.0f}$ | 止盈{params['gTPDist']:.0f}$")
    print(f"{'='*70}\n")
    
    df['date'] = df['datetime'].dt.date
    simulator = EASimulator(params)
    
    trades = []
    day_count = 0
    
    for date, day_df in df.groupby('date'):
        if len(day_df) < 500:
            continue
        
        # 确定方向
        if mode == 'long':
            direction = 1
        elif mode == 'short':
            direction = -1
        else:  # alternate
            direction = 1 if day_count % 2 == 0 else -1
        
        result = simulator.simulate_day(day_df, direction)
        if result:
            result['date'] = date
            trades.append(result)
            day_count += 1
    
    trades_df = pd.DataFrame(trades)
    
    # 统计
    total = len(trades_df)
    wins = len(trades_df[trades_df['pnl'] > 0])
    losses = len(trades_df[trades_df['pnl'] <= 0])
    total_profit = trades_df[trades_df['pnl'] > 0]['pnl'].sum()
    total_loss = abs(trades_df[trades_df['pnl'] <= 0]['pnl'].sum())
    
    print(f"总交易: {total} 天")
    print(f"盈利: {wins} ({wins/total*100:.1f}%) | 亏损: {losses} ({losses/total*100:.1f}%)")
    print(f"总盈利: ${total_profit:.2f} | 总亏损: ${total_loss:.2f}")
    print(f"净利润: ${total_profit - total_loss:.2f}")
    print(f"盈利因子: {total_profit/total_loss:.2f}" if total_loss > 0 else "盈利因子: ∞")
    
    print(f"\n出场原因:")
    for reason, count in trades_df['reason'].value_counts().items():
        avg = trades_df[trades_df['reason']==reason]['pnl'].mean()
        print(f"  {reason}: {count}次 (均${avg:.2f})")
    
    print(f"\n马丁统计: L1={trades_df['l1'].sum()}次 | L2={trades_df['l2'].sum()}次")
    
    # 连亏分析
    trades_df['win'] = trades_df['pnl'] > 0
    streak = (trades_df['win'] != trades_df['win'].shift()).cumsum()
    streaks = trades_df.groupby(streak)['win'].agg(['first', 'count'])
    loss_streaks = streaks[streaks['first'] == False]['count']
    max_loss_streak = loss_streaks.max() if len(loss_streaks) > 0 else 0
    print(f"最大连亏: {max_loss_streak} 次")
    
    # 显示最后5笔交易
    print(f"\n最近5笔交易:")
    for _, t in trades_df.tail(5).iterrows():
        print(f"  {t['date']} {t['direction']}: 入{t['entry']:.2f} 出{t['exit']:.2f} 盈亏${t['pnl']:.2f} [{t['reason']}] 仓位{t['positions']}层")
    
    return {
        'name': params['name'],
        'total': total,
        'wins': wins,
        'losses': losses,
        'win_rate': wins/total*100,
        'profit_factor': total_profit/total_loss if total_loss > 0 else 0,
        'net_profit': total_profit - total_loss,
        'max_loss_streak': max_loss_streak,
    }

def main():
    df = pd.read_csv(DATA_FILE)
    df['datetime'] = pd.to_datetime(df['datetime'])
    
    print(f"📊 数据: {df['datetime'].min().date()} 至 {df['datetime'].max().date()}")
    print(f"   {len(df):,} 条 tick 数据")
    
    results = []
    
    # 测试两种模式：每天做多 / 多空交替
    for params in [PARAMS_A, PARAMS_B]:
        for mode in ['long', 'alternate']:
            result = run_backtest(params, df, mode)
            result['mode'] = mode
            results.append(result)
    
    # 对比
    print(f"\n{'='*70}")
    print("📈 综合对比")
    print(f"{'='*70}")
    print(f"{'参数组':<12} {'模式':<10} {'PF':<6} {'净利$':<10} {'胜率%':<8} {'连亏':<6}")
    print("-" * 60)
    for r in results:
        print(f"{r['name']:<12} {r['mode']:<10} {r['profit_factor']:<6.2f} {r['net_profit']:<10.2f} {r['win_rate']:<8.1f} {r['max_loss_streak']:<6}")
    
    # 找出最优
    best = max(results, key=lambda x: x['profit_factor'] if x['profit_factor'] > 0 else -999)
    print(f"\n🏆 最优: {best['name']} + {best['mode']}模式")
    print(f"   盈利因子: {best['profit_factor']:.2f} | 净利润: ${best['net_profit']:.2f}")

if __name__ == "__main__":
    main()
