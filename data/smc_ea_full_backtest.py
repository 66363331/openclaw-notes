#!/usr/bin/env python3
"""
SMC进场信号 + EA订单管理 完整回测
- CHoCH结构突破检测
- OB订单块生成与管理
- 价格行为确认进场
- EA金字塔/马丁/止盈止损管理
"""
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import json

DATA_FILE = "/home/lilei/.openclaw/workspace/data/dukascopy/ms_aligned/XAUUSD_tick_combined_ms_aligned.csv"

class SMCStructure:
    """SMC结构检测"""
    def __init__(self, left_bars=5, right_bars=5):
        self.left = left_bars
        self.right = right_bars
        self.swing_highs = []  # [(index, price, time), ...]
        self.swing_lows = []
        self.choch_events = []  # 结构突破事件
        self.ob_zones = []  # 订单块区域
        
    def find_swings(self, highs, lows, times):
        """找Swing High/Low"""
        for i in range(self.left, len(highs) - self.right):
            # Swing High: 当前是窗口内最高点
            window_high = max(highs[i-self.left:i+self.right+1])
            if highs[i] == window_high:
                self.swing_highs.append({'idx': i, 'price': highs[i], 'time': times[i]})
            
            # Swing Low: 当前是窗口内最低点
            window_low = min(lows[i-self.left:i+self.right+1])
            if lows[i] == window_low:
                self.swing_lows.append({'idx': i, 'price': lows[i], 'time': times[i]})
    
    def detect_choch(self, closes, times):
        """检测CHoCH结构突破"""
        last_sh = None
        last_sl = None
        
        for i in range(1, len(closes)):
            # 更新最近swing点
            for sh in self.swing_highs:
                if sh['idx'] < i:
                    last_sh = sh
            for sl in self.swing_lows:
                if sl['idx'] < i:
                    last_sl = sl
            
            # CHoCH向上突破（做多结构）
            if last_sh and closes[i] > last_sh['price'] and closes[i-1] <= last_sh['price']:
                # 创建Bullish OB（突破前的一根K线）
                ob_idx = last_sh['idx'] - 1
                if ob_idx >= 0:
                    self.choch_events.append({
                        'type': 'bullish',
                        'idx': i,
                        'time': times[i],
                        'swing_ref': last_sh,
                        'ob_idx': ob_idx
                    })
            
            # CHoCH向下突破（做空结构）
            if last_sl and closes[i] < last_sl['price'] and closes[i-1] >= last_sl['price']:
                ob_idx = last_sl['idx'] - 1
                if ob_idx >= 0:
                    self.choch_events.append({
                        'type': 'bearish',
                        'idx': i,
                        'time': times[i],
                        'swing_ref': last_sl,
                        'ob_idx': ob_idx
                    })
    
    def create_ob_zones(self, highs, lows, opens, closes, times):
        """创建OB订单块区域"""
        for event in self.choch_events:
            ob_idx = event['ob_idx']
            if event['type'] == 'bullish':
                self.ob_zones.append({
                    'type': 'bull',
                    'created_idx': event['idx'],
                    'created_time': event['time'],
                    'top': highs[ob_idx],
                    'bottom': lows[ob_idx],
                    'mitigated': False,
                    'mitigated_idx': None
                })
            else:
                self.ob_zones.append({
                    'type': 'bear',
                    'created_idx': event['idx'],
                    'created_time': event['time'],
                    'top': highs[ob_idx],
                    'bottom': lows[ob_idx],
                    'mitigated': False,
                    'mitigated_idx': None
                })
    
    def check_entry(self, idx, highs, lows, opens, closes, strict=True):
        """检查进场信号"""
        signals = []
        
        for ob in self.ob_zones:
            if ob['mitigated'] or idx <= ob['created_idx']:
                continue
            
            # 检查OB是否失效（价格收盘突破OB）
            if ob['type'] == 'bull' and closes[idx] < ob['bottom']:
                ob['mitigated'] = True
                ob['mitigated_idx'] = idx
                continue
            if ob['type'] == 'bear' and closes[idx] > ob['top']:
                ob['mitigated'] = True
                ob['mitigated_idx'] = idx
                continue
            
            # 做多信号：价格触及OB上沿 + K线形态确认
            if ob['type'] == 'bull':
                if lows[idx] <= ob['top'] and closes[idx] >= ob['bottom']:
                    if strict:
                        # 严格模式：需要吞没或Pinbar
                        is_engulfing = (closes[idx-1] < opens[idx-1]) and (closes[idx] > opens[idx]) and \
                                      (closes[idx] >= opens[idx-1]) and (opens[idx] <= closes[idx-1])
                        total_size = highs[idx] - lows[idx]
                        is_pinbar = total_size > 0 and ((min(closes[idx], opens[idx]) - lows[idx]) / total_size > 0.6)
                        
                        if is_engulfing or is_pinbar:
                            signals.append({'type': 'buy', 'ob': ob, 'price': closes[idx]})
                    else:
                        signals.append({'type': 'buy', 'ob': ob, 'price': closes[idx]})
            
            # 做空信号
            elif ob['type'] == 'bear':
                if highs[idx] >= ob['bottom'] and closes[idx] <= ob['top']:
                    if strict:
                        is_engulfing = (closes[idx-1] > opens[idx-1]) and (closes[idx] < opens[idx]) and \
                                      (closes[idx] <= opens[idx-1]) and (opens[idx] >= closes[idx-1])
                        total_size = highs[idx] - lows[idx]
                        is_pinbar = total_size > 0 and ((highs[idx] - max(closes[idx], opens[idx])) / total_size > 0.6)
                        
                        if is_engulfing or is_pinbar:
                            signals.append({'type': 'sell', 'ob': ob, 'price': closes[idx]})
                    else:
                        signals.append({'type': 'sell', 'ob': ob, 'price': closes[idx]})
        
        return signals


class EAOrderManager:
    """EA订单管理"""
    def __init__(self, params):
        self.p = params
        
    def simulate_trade(self, entry_time, entry_price, direction, tick_df):
        """模拟完整交易过程"""
        # 获取进场后的tick数据
        future_ticks = tick_df[tick_df['timestamp_ms'] > entry_time].copy()
        if len(future_ticks) == 0:
            return None
        
        # 持仓结构
        positions = [{'type': 'seed', 'price': entry_price, 'lot': self.p['seedLot']}]
        total_lots = self.p['seedLot']
        breakeven = entry_price
        
        # 状态
        peak_delta = 0
        trailing = False
        l1_opened = False
        l2_opened = False
        max_positions = 1
        
        exit_price = future_ticks.iloc[-1]['mid']
        exit_reason = "收盘"
        pnl = 0
        
        for _, tick in future_ticks.iterrows():
            price = tick['mid']
            
            # 计算浮盈
            if direction == 1:  # 做多
                delta = price - breakeven
                
                # 金字塔加仓
                if delta > 0:
                    pyramid_count = len([p for p in positions if p['type']=='pyramid'])
                    if pyramid_count < self.p['pyrMax']:
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
                
                # 金字塔
                if delta > 0:
                    pyramid_count = len([p for p in positions if p['type']=='pyramid'])
                    if pyramid_count < self.p['pyrMax']:
                        ref = min(p['price'] for p in positions if p['type'] in ['seed','pyramid'])
                        if ref - price >= self.p['pyrStep']:
                            positions.append({'type': 'pyramid', 'price': price, 'lot': self.p['seedLot']})
                            total_lots += self.p['seedLot']
                            breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                            max_positions = max(max_positions, len(positions))
                
                # 马丁
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
            # 收盘
            if direction == 1:
                pnl = (exit_price - breakeven) * total_lots * 100
            else:
                pnl = (breakeven - exit_price) * total_lots * 100
        
        return {
            'exit_price': exit_price,
            'pnl': pnl,
            'exit_reason': exit_reason,
            'positions': max_positions,
            'total_lots': total_lots,
            'l1': l1_opened,
            'l2': l2_opened,
            'peak_delta': peak_delta,
        }


def run_smc_backtest(params, tick_df, ohlc_df, name):
    """运行SMC回测"""
    print(f"\n{'='*70}")
    print(f"SMC回测: {name}")
    print(f"参数: 回撤{params['trailPct']*100:.0f}% | 启动{params['gTrailStart']:.0f}$ | 止盈{params['gTPDist']:.0f}$")
    print(f"{'='*70}\n")
    
    # 准备OHLC数据
    highs = ohlc_df['high'].values
    lows = ohlc_df['low'].values
    opens = ohlc_df['open'].values
    closes = ohlc_df['close'].values
    times = ohlc_df['timestamp_ms'].values
    
    # SMC结构检测
    smc = SMCStructure(left_bars=5, right_bars=5)
    smc.find_swings(highs, lows, times)
    smc.detect_choch(closes, times)
    smc.create_ob_zones(highs, lows, opens, closes, times)
    
    print(f"检测到 {len(smc.swing_highs)} 个Swing High, {len(smc.swing_lows)} 个Swing Low")
    print(f"CHoCH突破: {len(smc.choch_events)} 次")
    print(f"OB订单块: {len(smc.ob_zones)} 个")
    
    # 找进场信号（非严格模式，获得更多样本）
    ea = EAOrderManager(params)
    trades = []
    last_trade_day = None
    
    for i in range(20, len(closes)):
        signals = smc.check_entry(i, highs, lows, opens, closes, strict=False)
        
        for signal in signals:
            entry_time = times[i]
            entry_price = signal['price']
            direction = 1 if signal['type'] == 'buy' else -1
            
            # 每4小时最多1笔（避免过度交易）
            current_time = datetime.fromtimestamp(entry_time/1000)
            current_4h = current_time.replace(minute=0, second=0, microsecond=0)
            current_4h = current_4h.replace(hour=(current_time.hour // 4) * 4)
            
            if last_trade_day == current_4h:
                continue
            
            result = ea.simulate_trade(entry_time, entry_price, direction, tick_df)
            if result:
                trades.append({
                    'entry_time': current_time,
                    'direction': '多' if direction==1 else '空',
                    'entry': entry_price,
                    **result
                })
                last_trade_day = current_4h
    
    if len(trades) == 0:
        print("无交易")
        return None
    
    trades_df = pd.DataFrame(trades)
    
    # 统计
    total = len(trades_df)
    wins = len(trades_df[trades_df['pnl'] > 0])
    total_profit = trades_df[trades_df['pnl'] > 0]['pnl'].sum()
    total_loss = abs(trades_df[trades_df['pnl'] <= 0]['pnl'].sum())
    
    print(f"\n总交易: {total} 笔")
    print(f"盈利: {wins} ({wins/total*100:.1f}%) | 亏损: {total-wins}")
    print(f"净利润: ${total_profit-total_loss:.2f}")
    print(f"盈利因子: {total_profit/total_loss:.2f}" if total_loss > 0 else "盈利因子: ∞")
    
    print(f"\n出场原因:")
    for reason, count in trades_df['exit_reason'].value_counts().items():
        avg = trades_df[trades_df['exit_reason']==reason]['pnl'].mean()
        print(f"  {reason}: {count}次 (均${avg:.2f})")
    
    print(f"\n马丁统计: L1={trades_df['l1'].sum()} | L2={trades_df['l2'].sum()}")
    
    return {
        'name': name,
        'total': total,
        'win_rate': wins/total*100,
        'profit_factor': total_profit/total_loss if total_loss > 0 else 0,
        'net_profit': total_profit - total_loss,
    }


def main():
    print("📊 SMC进场 + EA管理 完整回测")
    print("="*70)
    
    # 加载tick数据
    tick_df = pd.read_csv(DATA_FILE)
    tick_df['datetime'] = pd.to_datetime(tick_df['datetime'])
    print(f"Tick数据: {len(tick_df):,} 条")
    print(f"时间: {tick_df['datetime'].min()} 至 {tick_df['datetime'].max()}\n")
    
    # 生成OHLC (3分钟) 用于SMC结构检测
    tick_df.set_index('datetime', inplace=True)
    ohlc = tick_df.resample('3min').agg({'mid': ['first', 'max', 'min', 'last']})
    ohlc.columns = ['open', 'high', 'low', 'close']
    ohlc = ohlc.dropna().reset_index()
    ohlc['timestamp_ms'] = ohlc['datetime'].astype(np.int64) // 10**6
    print(f"OHLC数据: {len(ohlc)} 根3分钟K线\n")
    
    # 参数组
    params_a = {
        'trailPct': 0.30, 'gTrailStart': 10.0, 'gTPDist': 13.0,
        'pyrStep': 3.0, 'pyrMax': 8,
        'l1Dist': 23.0, 'l2Dist': 45.0, 'l2Mult': 2.0,
        'hardLoss': 220.0, 'seedLot': 0.01
    }
    
    params_b = {
        'trailPct': 0.20, 'gTrailStart': 8.0, 'gTPDist': 9.0,
        'pyrStep': 3.0, 'pyrMax': 8,
        'l1Dist': 23.0, 'l2Dist': 45.0, 'l2Mult': 2.0,
        'hardLoss': 220.0, 'seedLot': 0.01
    }
    
    # 运行回测
    results = []
    results.append(run_smc_backtest(params_a, tick_df.reset_index(), ohlc, "参数组 A (SMC)"))
    results.append(run_smc_backtest(params_b, tick_df.reset_index(), ohlc, "参数组 B (SMC)"))
    
    # 对比
    print(f"\n{'='*70}")
    print("📈 SMC回测对比")
    print(f"{'='*70}")
    print(f"{'参数组':<20} {'PF':<8} {'净利$':<12} {'胜率%':<8}")
    print("-"*50)
    for r in results:
        if r:
            print(f"{r['name']:<20} {r['profit_factor']:<8.2f} {r['net_profit']:<12.2f} {r['win_rate']:<8.1f}")
    
    best = max(results, key=lambda x: x['profit_factor'] if x else 0)
    print(f"\n🏆 最优: {best['name']}")

if __name__ == "__main__":
    main()
