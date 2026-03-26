#!/usr/bin/env python3
"""
正确的三层周期回测
H1趋势 + M15位置 + M3进场 + EA管理
"""
import pandas as pd
import numpy as np
from datetime import datetime

DATA_FILE = "/home/lilei/.openclaw/workspace/data/dukascopy/ms_aligned/XAUUSD_tick_combined_ms_aligned.csv"

def resample_ohlc(df, timeframe):
    """重采样为OHLC"""
    ohlc = df.resample(timeframe).agg({'mid': ['first','max','min','last']})
    ohlc.columns = ['open','high','low','close']
    return ohlc.dropna()

class ThreeTierBacktest:
    """三层周期回测"""
    
    def __init__(self, params):
        self.p = params
        
    def calculate_ema(self, df, period):
        return df['close'].ewm(span=period).mean()
    
    def detect_smc_m15(self, df_m15):
        """M15检测SMC结构（OB区域）"""
        left, right = 3, 3  # M15用更小的窗口
        df_m15['swing_high'] = False
        df_m15['swing_low'] = False
        
        for i in range(left, len(df_m15) - right):
            window = df_m15.iloc[i-left:i+right+1]
            if df_m15.iloc[i]['high'] == window['high'].max():
                df_m15.loc[df_m15.index[i], 'swing_high'] = True
            if df_m15.iloc[i]['low'] == window['low'].min():
                df_m15.loc[df_m15.index[i], 'swing_low'] = True
        
        # 检测CHoCH和创建OB
        obs = []
        last_sh = last_sl = None
        
        for i in range(1, len(df_m15)):
            if df_m15.iloc[i-1]['swing_high']:
                last_sh = df_m15.iloc[i-1]
            if df_m15.iloc[i-1]['swing_low']:
                last_sl = df_m15.iloc[i-1]
            
            # CHoCH向上
            if last_sh is not None and df_m15.iloc[i]['close'] > last_sh['high'] and df_m15.iloc[i-1]['close'] <= last_sh['high']:
                ob_idx = df_m15.index.get_loc(last_sh.name) - 1
                if ob_idx >= 0:
                    obs.append({
                        'type': 'bull',
                        'created_time': df_m15.index[i],
                        'top': df_m15.iloc[ob_idx]['high'],
                        'bottom': df_m15.iloc[ob_idx]['low'],
                        'active': True
                    })
            
            # CHoCH向下
            if last_sl is not None and df_m15.iloc[i]['close'] < last_sl['low'] and df_m15.iloc[i-1]['close'] >= last_sl['low']:
                ob_idx = df_m15.index.get_loc(last_sl.name) - 1
                if ob_idx >= 0:
                    obs.append({
                        'type': 'bear',
                        'created_time': df_m15.index[i],
                        'top': df_m15.iloc[ob_idx]['high'],
                        'bottom': df_m15.iloc[ob_idx]['low'],
                        'active': True
                    })
        
        return obs
    
    def check_m3_entry(self, df_m3, obs_m15, trend_h1):
        """M3检测进场信号"""
        signals = []
        
        for i in range(1, len(df_m3)):
            row = df_m3.iloc[i]
            prev = df_m3.iloc[i-1]
            current_time = df_m3.index[i]
            
            # 获取当前H1趋势
            current_trend = None
            for idx, t in trend_h1.iterrows():
                if idx <= current_time:
                    if t['bull_trend']:
                        current_trend = 'bull'
                    elif t['bear_trend']:
                        current_trend = 'bear'
            
            if current_trend is None:
                continue
            
            # 检查M15的OB区域
            for ob in obs_m15:
                if not ob['active'] or current_time < ob['created_time']:
                    continue
                
                # OB失效检测
                if ob['type'] == 'bull' and row['close'] < ob['bottom']:
                    ob['active'] = False
                    continue
                if ob['type'] == 'bear' and row['close'] > ob['top']:
                    ob['active'] = False
                    continue
                
                # 做多信号：牛市趋势 + Bull OB + 价格触及 + K线确认
                if ob['type'] == 'bull' and current_trend == 'bull':
                    if row['low'] <= ob['top'] and row['close'] >= ob['bottom']:
                        # K线确认：阳线且收在OB上方
                        if row['close'] > row['open'] and row['close'] > ob['bottom']:
                            signals.append({
                                'time': current_time,
                                'type': 'buy',
                                'price': row['close'],
                                'ob': ob
                            })
                
                # 做空信号
                if ob['type'] == 'bear' and current_trend == 'bear':
                    if row['high'] >= ob['bottom'] and row['close'] <= ob['top']:
                        if row['close'] < row['open'] and row['close'] < ob['top']:
                            signals.append({
                                'time': current_time,
                                'type': 'sell',
                                'price': row['close'],
                                'ob': ob
                            })
        
        return signals
    
    def simulate_trade(self, entry_time, entry_price, direction, tick_df):
        """模拟EA管理"""
        future = tick_df[tick_df['datetime'] > entry_time]
        if len(future) == 0:
            return None
        
        positions = [{'type': 'seed', 'price': entry_price, 'lot': self.p['seedLot']}]
        total_lots = self.p['seedLot']
        breakeven = entry_price
        peak_delta = 0
        trailing = False
        l1_opened = l2_opened = False
        
        for _, tick in future.iterrows():
            price = tick['mid']
            
            if direction == 1:  # 做多
                delta = price - breakeven
                # 金字塔
                if delta > 0:
                    ref = max(p['price'] for p in positions if p['type'] in ['seed','pyramid'])
                    if price - ref >= self.p['pyrStep'] and len([p for p in positions if p['type']=='pyramid']) < self.p['pyrMax']:
                        positions.append({'type': 'pyramid', 'price': price, 'lot': self.p['seedLot']})
                        total_lots += self.p['seedLot']
                        breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                # 马丁
                lowest = min(p['price'] for p in positions)
                dist = price - lowest
                if not l1_opened and dist <= -self.p['l1Dist']:
                    positions.append({'type': 'l1', 'price': price, 'lot': self.p['seedLot']})
                    total_lots += self.p['seedLot']
                    l1_opened = True
                    breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                elif l1_opened and not l2_opened and dist <= -self.p['l2Dist']:
                    l2_lot = self.p['seedLot'] * self.p['l2Mult']
                    positions.append({'type': 'l2', 'price': price, 'lot': l2_lot})
                    total_lots += l2_lot
                    l2_opened = True
                    breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
            else:  # 做空
                delta = breakeven - price
                if delta > 0:
                    ref = min(p['price'] for p in positions if p['type'] in ['seed','pyramid'])
                    if ref - price >= self.p['pyrStep'] and len([p for p in positions if p['type']=='pyramid']) < self.p['pyrMax']:
                        positions.append({'type': 'pyramid', 'price': price, 'lot': self.p['seedLot']})
                        total_lots += self.p['seedLot']
                        breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                highest = max(p['price'] for p in positions)
                dist = highest - price
                if not l1_opened and dist <= -self.p['l1Dist']:
                    positions.append({'type': 'l1', 'price': price, 'lot': self.p['seedLot']})
                    total_lots += self.p['seedLot']
                    l1_opened = True
                    breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                elif l1_opened and not l2_opened and dist <= -self.p['l2Dist']:
                    l2_lot = self.p['seedLot'] * self.p['l2Mult']
                    positions.append({'type': 'l2', 'price': price, 'lot': l2_lot})
                    total_lots += l2_lot
                    l2_opened = True
                    breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
            
            if delta > peak_delta:
                peak_delta = delta
            if not trailing and delta >= self.p['gTrailStart']:
                trailing = True
            if trailing and delta <= peak_delta * (1 - self.p['trailPct']):
                return {'pnl': delta * total_lots * 100, 'reason': f"追踪({self.p['trailPct']*100:.0f}%)", 'l1': l1_opened, 'l2': l2_opened}
            if not trailing and delta >= self.p['gTPDist']:
                return {'pnl': self.p['gTPDist'] * total_lots * 100, 'reason': f"主止盈({self.p['gTPDist']:.0f}$)", 'l1': l1_opened, 'l2': l2_opened}
            if delta <= -self.p['hardLoss'] / (total_lots * 100):
                return {'pnl': -self.p['hardLoss'], 'reason': f"硬止损({self.p['hardLoss']:.0f}$)", 'l1': l1_opened, 'l2': l2_opened}
        
        pnl = (future.iloc[-1]['mid'] - breakeven) * total_lots * 100 if direction == 1 else (breakeven - future.iloc[-1]['mid']) * total_lots * 100
        return {'pnl': pnl, 'reason': '收盘', 'l1': l1_opened, 'l2': l2_opened}
    
    def run(self, tick_df, name):
        """运行三层周期回测"""
        print(f"\n{'='*70}")
        print(f"三层周期回测: {name}")
        print(f"H1趋势 + M15位置 + M3进场 + EA管理")
        print(f"{'='*70}\n")
        
        tick_df['datetime'] = pd.to_datetime(tick_df['datetime'])
        tick_df.set_index('datetime', inplace=True)
        
        # 1. H1计算EMA趋势
        print("计算H1趋势...")
        df_h1 = resample_ohlc(tick_df, '1h')
        df_h1['ema20'] = self.calculate_ema(df_h1, 20)
        df_h1['ema50'] = self.calculate_ema(df_h1, 50)
        df_h1['ema200'] = self.calculate_ema(df_h1, 200)
        df_h1['bull_trend'] = (df_h1['close'] > df_h1['ema20']) & (df_h1['ema20'] > df_h1['ema50']) & (df_h1['ema50'] > df_h1['ema200'])
        df_h1['bear_trend'] = (df_h1['close'] < df_h1['ema20']) & (df_h1['ema20'] < df_h1['ema50']) & (df_h1['ema50'] < df_h1['ema200'])
        print(f"H1: 牛市={df_h1['bull_trend'].sum()}小时, 熊市={df_h1['bear_trend'].sum()}小时")
        
        # 2. M15检测SMC结构
        print("检测M15 SMC结构...")
        df_m15 = resample_ohlc(tick_df, '15min')
        obs_m15 = self.detect_smc_m15(df_m15)
        print(f"M15: 检测到 {len(obs_m15)} 个OB区域")
        
        # 3. M3检测进场信号
        print("检测M3进场信号...")
        df_m3 = resample_ohlc(tick_df, '3min')
        signals = self.check_m3_entry(df_m3, obs_m15, df_h1[['bull_trend','bear_trend']])
        print(f"M3: 检测到 {len(signals)} 个进场信号")
        
        if len(signals) == 0:
            return None
        
        # 执行交易
        tick_df = tick_df.reset_index()
        trades = []
        last_4h = None
        
        for sig in signals:
            # 4小时冷却
            current_4h = sig['time'].floor('4h')
            if current_4h == last_4h:
                continue
            
            direction = 1 if sig['type'] == 'buy' else -1
            result = self.simulate_trade(sig['time'], sig['price'], direction, tick_df)
            
            if result:
                trades.append({
                    'time': sig['time'],
                    'dir': '多' if direction==1 else '空',
                    'entry': sig['price'],
                    **result
                })
                last_4h = current_4h
        
        if len(trades) == 0:
            return None
        
        trades_df = pd.DataFrame(trades)
        total = len(trades_df)
        wins = len(trades_df[trades_df['pnl'] > 0])
        profit = trades_df[trades_df['pnl'] > 0]['pnl'].sum()
        loss = abs(trades_df[trades_df['pnl'] <= 0]['pnl'].sum())
        
        print(f"\n总交易: {total} 笔")
        print(f"盈利: {wins} ({wins/total*100:.1f}%) | 亏损: {total-wins}")
        print(f"净利润: ${profit-loss:.2f} | PF: {profit/loss:.2f}" if loss > 0 else "PF: ∞")
        print(f"\n出场: {trades_df['reason'].value_counts().to_dict()}")
        print(f"马丁: L1={trades_df['l1'].sum()}, L2={trades_df['l2'].sum()}")
        
        return {'name': name, 'total': total, 'win_rate': wins/total*100,
                'profit_factor': profit/loss if loss > 0 else 0, 'net_profit': profit-loss}

def main():
    print("📊 H1趋势 + M15位置 + M3进场 三层周期回测")
    print("="*70)
    
    tick_df = pd.read_csv(DATA_FILE)
    print(f"Tick数据: {len(tick_df):,} 条")
    print(f"时间: {tick_df['datetime'].min()} 至 {tick_df['datetime'].max()}\n")
    
    params_a = {'gTPDist': 13, 'gTrailStart': 10, 'trailPct': 0.30, 'pyrStep': 3, 'pyrMax': 8,
                'l1Dist': 23, 'l2Dist': 45, 'l2Mult': 2, 'hardLoss': 220, 'seedLot': 0.01}
    params_b = {'gTPDist': 9, 'gTrailStart': 8, 'trailPct': 0.20, 'pyrStep': 3, 'pyrMax': 8,
                'l1Dist': 23, 'l2Dist': 45, 'l2Mult': 2, 'hardLoss': 220, 'seedLot': 0.01}
    
    bt = ThreeTierBacktest(params_a)
    result_a = bt.run(tick_df, "参数组 A (H1+M15+M3)")
    
    bt = ThreeTierBacktest(params_b)
    result_b = bt.run(tick_df, "参数组 B (H1+M15+M3)")
    
    results = [r for r in [result_a, result_b] if r]
    if len(results) >= 2:
        print(f"\n{'='*70}")
        print("📈 对比")
        print(f"{'方案':<30} {'PF':<8} {'净利$':<12} {'胜率%':<8}")
        print("-"*60)
        for r in results:
            print(f"{r['name']:<30} {r['profit_factor']:<8.2f} {r['net_profit']:<12.2f} {r['win_rate']:<8.1f}")
        best = max(results, key=lambda x: x['profit_factor'])
        print(f"\n🏆 最优: {best['name']}")

if __name__ == "__main__":
    main()
