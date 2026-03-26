#!/usr/bin/env python3
"""
均线进场 + EA 订单管理 综合回测
进场：H1 均线趋势 + M15 回调进场
管理：金字塔加仓 + 马丁补仓 + 追踪止盈 + 硬止损
"""
import pandas as pd
import numpy as np
from datetime import datetime, timedelta

DATA_FILE = "/home/lilei/.openclaw/workspace/data/dukascopy/ms_aligned/XAUUSD_tick_combined_ms_aligned.csv"

def calculate_ema(prices, period):
    """计算 EMA"""
    return prices.ewm(span=period, adjust=False).mean()

def calculate_ema_alignment(df, ema_fast=20, ema_mid=50, ema_slow=200):
    """计算多周期EMA排列"""
    df[f'EMA{ema_fast}'] = calculate_ema(df['mid'], ema_fast)
    df[f'EMA{ema_mid}'] = calculate_ema(df['mid'], ema_mid)
    df[f'EMA{ema_slow}'] = calculate_ema(df['mid'], ema_slow)
    
    # 多头排列：价格 > 快 > 中 > 慢
    df['bull_align'] = (df['mid'] > df[f'EMA{ema_fast}']) & \
                       (df[f'EMA{ema_fast}'] > df[f'EMA{ema_mid}']) & \
                       (df[f'EMA{ema_mid}'] > df[f'EMA{ema_slow}'])
    
    # 空头排列：价格 < 快 < 中 < 慢
    df['bear_align'] = (df['mid'] < df[f'EMA{ema_fast}']) & \
                       (df[f'EMA{ema_fast}'] < df[f'EMA{ema_mid}']) & \
                       (df[f'EMA{ema_mid}'] < df[f'EMA{ema_slow}'])
    
    return df

class EMA_EA_Backtest:
    """均线进场 + EA 管理"""
    
    def __init__(self, params):
        self.p = params
        
    def prepare_data(self, df):
        """准备数据 - 计算EMA"""
        df['datetime'] = pd.to_datetime(df['datetime'])
        df.set_index('datetime', inplace=True)
        
        # 重采样到1分钟计算EMA（再从1分钟聚合到H1/M15判断）
        df_1min = df.resample('1min').last().dropna()
        
        # 计算 EMA
        df_1min = calculate_ema_alignment(df_1min, 20, 50, 200)
        
        return df_1min.reset_index()
    
    def find_entry_signals(self, df_1min):
        """找进场信号"""
        signals = []
        
        # 按小时聚合判断趋势
        df_1min['hour'] = df_1min['datetime'].dt.floor('h')
        
        for hour, hour_df in df_1min.groupby('hour'):
            if len(hour_df) < 30:
                continue
            
            # H1 趋势判断（用小时最后一根确认趋势）
            last_row = hour_df.iloc[-1]
            
            if last_row['bull_align']:
                trend = 'bull'
            elif last_row['bear_align']:
                trend = 'bear'
            else:
                continue  # 无明确趋势
            
            # 在小时内找回调进场点
            ema20_col = 'EMA20'
            
            for i in range(10, len(hour_df)):
                row = hour_df.iloc[i]
                prev = hour_df.iloc[i-1]
                
                if trend == 'bull':
                    # 多头回调进场：价格触及或跌破EMA20后反弹
                    if prev['mid'] <= prev[ema20_col] and row['mid'] > row[ema20_col]:
                        if row['mid'] > prev['mid']:  # 确认反弹
                            signals.append({
                                'time': row['datetime'],
                                'direction': 1,  # 做多
                                'entry_price': row['mid'],
                                'trend': 'bull',
                                'reason': '多头回调EMA20反弹'
                            })
                            break  # 每小时只取第一个信号
                            
                elif trend == 'bear':
                    # 空头回调进场：价格触及或涨破EMA20后回落
                    if prev['mid'] >= prev[ema20_col] and row['mid'] < row[ema20_col]:
                        if row['mid'] < prev['mid']:  # 确认回落
                            signals.append({
                                'time': row['datetime'],
                                'direction': -1,  # 做空
                                'entry_price': row['mid'],
                                'trend': 'bear',
                                'reason': '空头回调EMA20回落'
                            })
                            break
        
        return pd.DataFrame(signals)
    
    def simulate_trade(self, signal_row, tick_df):
        """模拟完整交易（从进场到出场）"""
        entry_time = signal_row['time']
        direction = signal_row['direction']
        entry_price = signal_row['entry_price']
        
        # 获取进场后的tick数据
        future_ticks = tick_df[tick_df['datetime'] > entry_time]
        if len(future_ticks) == 0:
            return None
        
        # 持仓状态
        positions = [{'type': 'seed', 'price': entry_price, 'lot': self.p['seedLot']}]
        total_lots = self.p['seedLot']
        breakeven = entry_price
        
        peak_delta = 0
        trailing = False
        l1_opened = False
        l2_opened = False
        
        exit_price = future_ticks.iloc[-1]['mid']  # 默认收盘
        exit_reason = "收盘"
        pnl = 0
        max_positions = 1
        
        # 遍历后续tick
        for _, tick in future_ticks.iterrows():
            price = tick['mid']
            
            # 计算当前浮盈和持仓均价
            if direction == 1:  # 做多
                delta = price - breakeven
                
                # 金字塔加仓
                if delta > 0 and len([p for p in positions if p['type']=='pyramid']) < self.p['pyrMax']:
                    ref = max(p['price'] for p in positions if p['type'] in ['seed','pyramid'])
                    if price - ref >= self.p['pyrStep']:
                        positions.append({'type': 'pyramid', 'price': price, 'lot': self.p['seedLot']})
                        total_lots += self.p['seedLot']
                        breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                        max_positions = max(max_positions, len(positions))
                
                # 马丁补仓
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
            if direction == 1:
                pnl = (exit_price - breakeven) * total_lots * 100
            else:
                pnl = (breakeven - exit_price) * total_lots * 100
        
        return {
            'exit_time': tick.name if hasattr(tick, 'name') else tick['datetime'],
            'exit_price': exit_price,
            'pnl': pnl,
            'exit_reason': exit_reason,
            'positions': max_positions,
            'total_lots': total_lots,
            'l1': l1_opened,
            'l2': l2_opened,
            'peak_delta': peak_delta,
        }
    
    def run(self, tick_df):
        """运行完整回测"""
        print("准备数据...")
        df_1min = self.prepare_data(tick_df.copy())
        
        print("寻找进场信号...")
        signals = self.find_entry_signals(df_1min)
        print(f"找到 {len(signals)} 个进场信号")
        
        if len(signals) == 0:
            return None
        
        print("模拟交易...")
        trades = []
        for _, signal in signals.iterrows():
            result = self.simulate_trade(signal, tick_df)
            if result:
                trades.append({
                    'entry_time': signal['time'],
                    'direction': '多' if signal['direction'] == 1 else '空',
                    'entry_price': signal['entry_price'],
                    **result
                })
        
        return pd.DataFrame(trades)

def analyze_results(trades_df, params_name):
    """分析交易结果"""
    if trades_df is None or len(trades_df) == 0:
        print(f"{params_name}: 无交易")
        return None
    
    total = len(trades_df)
    wins = len(trades_df[trades_df['pnl'] > 0])
    losses = len(trades_df[trades_df['pnl'] <= 0])
    
    total_profit = trades_df[trades_df['pnl'] > 0]['pnl'].sum()
    total_loss = abs(trades_df[trades_df['pnl'] <= 0]['pnl'].sum())
    
    print(f"\n{'='*70}")
    print(f"📊 {params_name} 回测结果")
    print(f"{'='*70}")
    print(f"总交易: {total} 笔")
    print(f"盈利: {wins} ({wins/total*100:.1f}%) | 亏损: {losses} ({losses/total*100:.1f}%)")
    print(f"总盈利: ${total_profit:.2f} | 总亏损: ${total_loss:.2f}")
    print(f"净利润: ${total_profit - total_loss:.2f}")
    print(f"盈利因子: {total_profit/total_loss:.2f}" if total_loss > 0 else "盈利因子: ∞")
    
    print(f"\n出场原因:")
    for reason, count in trades_df['exit_reason'].value_counts().items():
        avg = trades_df[trades_df['exit_reason']==reason]['pnl'].mean()
        print(f"  {reason}: {count}次 (均${avg:.2f})")
    
    print(f"\n马丁统计: L1={trades_df['l1'].sum()}次 | L2={trades_df['l2'].sum()}次")
    
    # 连亏
    trades_df['win'] = trades_df['pnl'] > 0
    streak = (trades_df['win'] != trades_df['win'].shift()).cumsum()
    streaks = trades_df.groupby(streak)['win'].agg(['first', 'count'])
    loss_streaks = streaks[streaks['first'] == False]['count']
    max_loss_streak = loss_streaks.max() if len(loss_streaks) > 0 else 0
    print(f"最大连亏: {max_loss_streak} 次")
    
    # 最近5笔
    print(f"\n最近5笔交易:")
    for _, t in trades_df.tail(5).iterrows():
        print(f"  {t['entry_time']} {t['direction']}: 入{t['entry_price']:.2f} 出{t['exit_price']:.2f} 盈亏${t['pnl']:.2f} [{t['exit_reason']}]")
    
    return {
        'name': params_name,
        'total': total,
        'win_rate': wins/total*100,
        'profit_factor': total_profit/total_loss if total_loss > 0 else 0,
        'net_profit': total_profit - total_loss,
        'max_loss_streak': max_loss_streak,
    }

def main():
    print("📊 EMA进场 + EA管理 综合回测")
    print("="*70)
    
    # 加载数据
    df = pd.read_csv(DATA_FILE)
    df['datetime'] = pd.to_datetime(df['datetime'])
    print(f"数据: {df['datetime'].min()} 至 {df['datetime'].max()}")
    print(f"共 {len(df):,} 条 tick 数据\n")
    
    # 参数组 A
    params_a = {
        'gTPDist': 13.0, 'gTrailStart': 10.0, 'trailPct': 0.30,
        'gLockDist': 3.0, 'gLockSL': 1.0,
        'pyrStep': 3.0, 'pyrMax': 8,
        'l1Dist': 23.0, 'l2Dist': 45.0, 'l2Mult': 2.0,
        'hardLoss': 220.0, 'seedLot': 0.01,
    }
    
    # 参数组 B
    params_b = {
        'gTPDist': 9.0, 'gTrailStart': 8.0, 'trailPct': 0.20,
        'gLockDist': 4.0, 'gLockSL': 1.2,
        'pyrStep': 3.0, 'pyrMax': 8,
        'l1Dist': 23.0, 'l2Dist': 45.0, 'l2Mult': 2.0,
        'hardLoss': 220.0, 'seedLot': 0.01,
    }
    
    results = []
    
    # 测试参数组 A
    bt_a = EMA_EA_Backtest(params_a)
    trades_a = bt_a.run(df)
    result_a = analyze_results(trades_a, "参数组 A (EMA进场)")
    if result_a:
        results.append(result_a)
    
    # 测试参数组 B
    bt_b = EMA_EA_Backtest(params_b)
    trades_b = bt_b.run(df)
    result_b = analyze_results(trades_b, "参数组 B (EMA进场)")
    if result_b:
        results.append(result_b)
    
    # 对比
    if len(results) >= 2:
        print(f"\n{'='*70}")
        print("📈 对比分析")
        print(f"{'='*70}")
        print(f"{'参数组':<20} {'PF':<8} {'净利$':<12} {'胜率%':<10} {'连亏':<6}")
        print("-" * 60)
        for r in results:
            print(f"{r['name']:<20} {r['profit_factor']:<8.2f} {r['net_profit']:<12.2f} {r['win_rate']:<10.1f} {r['max_loss_streak']:<6}")
        
        best = max(results, key=lambda x: x['profit_factor'])
        print(f"\n🏆 最优: {best['name']}")

if __name__ == "__main__":
    main()
