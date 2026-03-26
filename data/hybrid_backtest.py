#!/usr/bin/env python3
"""
EMA趋势过滤 + SMC结构进场 + EA管理 综合回测
- H1 EMA趋势判断（多头排列才做多，空头排列才做空）
- SMC结构突破生成OB
- 价格回到OB + K线确认进场
- EA金字塔/马丁/止盈止损管理
"""
import pandas as pd
import numpy as np
from datetime import datetime

DATA_FILE = "/home/lilei/.openclaw/workspace/data/dukascopy/ms_aligned/XAUUSD_tick_combined_ms_aligned.csv"

class EMAFilter:
    """EMA趋势过滤器"""
    def __init__(self, fast=20, mid=50, slow=200):
        self.fast = fast
        self.mid = mid
        self.slow = slow
    
    def calculate(self, df):
        """计算EMA并判断趋势"""
        df['ema_fast'] = df['close'].ewm(span=self.fast).mean()
        df['ema_mid'] = df['close'].ewm(span=self.mid).mean()
        df['ema_slow'] = df['close'].ewm(span=self.slow).mean()
        
        # 多头排列（只做多）
        df['bull_trend'] = (df['close'] > df['ema_fast']) & \
                          (df['ema_fast'] > df['ema_mid']) & \
                          (df['ema_mid'] > df['ema_slow'])
        
        # 空头排列（只做空）
        df['bear_trend'] = (df['close'] < df['ema_fast']) & \
                          (df['ema_fast'] < df['ema_mid']) & \
                          (df['ema_mid'] < df['ema_slow'])
        
        return df

class SMCStructure:
    """SMC结构检测（简化版）"""
    def __init__(self, left=5, right=5):
        self.left = left
        self.right = right
        self.obs = []
    
    def find_swings(self, df):
        """找Swing点"""
        df['swing_high'] = False
        df['swing_low'] = False
        
        for i in range(self.left, len(df) - self.right):
            window = df.iloc[i-self.left:i+self.right+1]
            if df.iloc[i]['high'] == window['high'].max():
                df.loc[df.index[i], 'swing_high'] = True
            if df.iloc[i]['low'] == window['low'].min():
                df.loc[df.index[i], 'swing_low'] = True
        
        return df
    
    def detect_structure(self, df):
        """检测CHoCH和创建OB"""
        df['choch_up'] = False
        df['choch_down'] = False
        
        last_sh = None
        last_sl = None
        
        for i in range(1, len(df)):
            # 更新最近swing点
            if df.iloc[i-1]['swing_high']:
                last_sh = df.iloc[i-1]
            if df.iloc[i-1]['swing_low']:
                last_sl = df.iloc[i-1]
            
            # CHoCH向上突破
            if last_sh is not None:
                if df.iloc[i]['close'] > last_sh['high'] and df.iloc[i-1]['close'] <= last_sh['high']:
                    df.loc[df.index[i], 'choch_up'] = True
                    # 创建Bull OB
                    ob_idx = df.index.get_loc(last_sh.name) - 1
                    if ob_idx >= 0:
                        self.obs.append({
                            'type': 'bull',
                            'created_idx': i,
                            'top': df.iloc[ob_idx]['high'],
                            'bottom': df.iloc[ob_idx]['low'],
                            'active': True,
                            'trend_required': 'bull'  # 需要牛市趋势
                        })
            
            # CHoCH向下突破
            if last_sl is not None:
                if df.iloc[i]['close'] < last_sl['low'] and df.iloc[i-1]['close'] >= last_sl['low']:
                    df.loc[df.index[i], 'choch_down'] = True
                    ob_idx = df.index.get_loc(last_sl.name) - 1
                    if ob_idx >= 0:
                        self.obs.append({
                            'type': 'bear',
                            'created_idx': i,
                            'top': df.iloc[ob_idx]['high'],
                            'bottom': df.iloc[ob_idx]['low'],
                            'active': True,
                            'trend_required': 'bear'
                        })
        
        return df

class HybridBacktest:
    """综合回测：EMA+SMC+EA"""
    
    def __init__(self, params):
        self.p = params
    
    def check_entry(self, idx, row, prev_row, obs, trend_bull, trend_bear):
        """检查进场信号（EMA过滤+SMC确认）"""
        signals = []
        
        for ob in obs:
            if not ob['active'] or idx <= ob['created_idx']:
                continue
            
            # 检查OB失效
            if ob['type'] == 'bull' and row['close'] < ob['bottom']:
                ob['active'] = False
                continue
            if ob['type'] == 'bear' and row['close'] > ob['top']:
                ob['active'] = False
                continue
            
            # 做多信号：Bull OB + 牛市趋势 + 价格触及OB
            if ob['type'] == 'bull' and ob['trend_required'] == 'bull' and trend_bull:
                if row['low'] <= ob['top'] and row['close'] >= ob['bottom']:
                    # 简化K线确认：收阳
                    if row['close'] > row['open']:
                        signals.append({'type': 'buy', 'price': row['close'], 'ob': ob})
            
            # 做空信号
            if ob['type'] == 'bear' and ob['trend_required'] == 'bear' and trend_bear:
                if row['high'] >= ob['bottom'] and row['close'] <= ob['top']:
                    if row['close'] < row['open']:
                        signals.append({'type': 'sell', 'price': row['close'], 'ob': ob})
        
        return signals
    
    def simulate_trade(self, entry_price, direction, future_df):
        """模拟EA管理过程"""
        positions = [{'type': 'seed', 'price': entry_price, 'lot': self.p['seedLot']}]
        total_lots = self.p['seedLot']
        breakeven = entry_price
        
        peak_delta = 0
        trailing = False
        l1_opened = l2_opened = False
        
        for _, tick in future_df.iterrows():
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
            
            # 止盈止损
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
        
        # 收盘
        pnl = (future_df.iloc[-1]['mid'] - breakeven) * total_lots * 100 if direction == 1 else (breakeven - future_df.iloc[-1]['mid']) * total_lots * 100
        return {'pnl': pnl, 'reason': '收盘', 'l1': l1_opened, 'l2': l2_opened}
    
    def run(self, tick_df, ohlc_df, name):
        """运行回测"""
        print(f"\n{'='*70}")
        print(f"综合回测: {name} (EMA+SMC+EA)")
        print(f"{'='*70}\n")
        
        # EMA趋势计算
        ema = EMAFilter(20, 50, 200)
        ohlc_df = ema.calculate(ohlc_df)
        
        # SMC结构检测
        smc = SMCStructure(5, 5)
        ohlc_df = smc.find_swings(ohlc_df)
        ohlc_df = smc.detect_structure(ohlc_df)
        
        print(f"EMA趋势: 牛市={ohlc_df['bull_trend'].sum()}根, 熊市={ohlc_df['bear_trend'].sum()}根")
        print(f"SMC结构: CHoCH向上={ohlc_df['choch_up'].sum()}次, 向下={ohlc_df['choch_down'].sum()}次")
        print(f"OB订单块: {len(smc.obs)}个")
        
        # 找信号并交易
        trades = []
        last_trade_4h = None
        
        for i in range(20, len(ohlc_df)):
            row = ohlc_df.iloc[i]
            prev = ohlc_df.iloc[i-1]
            
            signals = self.check_entry(i, row, prev, smc.obs, 
                                      row['bull_trend'], row['bear_trend'])
            
            for sig in signals:
                # 4小时冷却
                current_4h = row.name.floor('4h') if hasattr(row.name, 'floor') else i // 80
                if current_4h == last_trade_4h:
                    continue
                
                entry_time = ohlc_df.index[i]
                future = tick_df[tick_df['datetime'] > entry_time]
                
                if len(future) == 0:
                    continue
                
                direction = 1 if sig['type'] == 'buy' else -1
                result = self.simulate_trade(sig['price'], direction, future)
                
                trades.append({
                    'time': entry_time,
                    'dir': '多' if direction==1 else '空',
                    'entry': sig['price'],
                    **result
                })
                last_trade_4h = current_4h
        
        if len(trades) == 0:
            print("无交易")
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
    print("📊 EMA趋势 + SMC结构 + EA管理 综合回测")
    print("="*70)
    
    # 加载数据
    tick_df = pd.read_csv(DATA_FILE)
    tick_df['datetime'] = pd.to_datetime(tick_df['datetime'])
    print(f"Tick: {len(tick_df):,}条, {tick_df['datetime'].min().date()} 至 {tick_df['datetime'].max().date()}")
    
    # 生成OHLC (5分钟)
    tick_df.set_index('datetime', inplace=True)
    ohlc = tick_df.resample('5min').agg({'mid': ['first','max','min','last']})
    ohlc.columns = ['open','high','low','close']
    ohlc = ohlc.dropna()
    print(f"OHLC: {len(ohlc)} 根5分钟K线\n")
    
    # 参数组
    params_a = {'gTPDist': 13, 'gTrailStart': 10, 'trailPct': 0.30, 'pyrStep': 3, 'pyrMax': 8,
                'l1Dist': 23, 'l2Dist': 45, 'l2Mult': 2, 'hardLoss': 220, 'seedLot': 0.01}
    params_b = {'gTPDist': 9, 'gTrailStart': 8, 'trailPct': 0.20, 'pyrStep': 3, 'pyrMax': 8,
                'l1Dist': 23, 'l2Dist': 45, 'l2Mult': 2, 'hardLoss': 220, 'seedLot': 0.01}
    
    # 回测
    results = []
    bt = HybridBacktest(params_a)
    results.append(bt.run(tick_df.reset_index(), ohlc, "参数组 A (EMA+SMC)"))
    
    bt = HybridBacktest(params_b)
    results.append(bt.run(tick_df.reset_index(), ohlc, "参数组 B (EMA+SMC)"))
    
    # 对比
    print(f"\n{'='*70}")
    print("📈 对比结果")
    print(f"{'='*70}")
    print(f"{'方案':<25} {'PF':<8} {'净利$':<12} {'胜率%':<8}")
    print("-"*55)
    for r in results:
        if r:
            print(f"{r['name']:<25} {r['profit_factor']:<8.2f} {r['net_profit']:<12.2f} {r['win_rate']:<8.1f}")
    
    best = max([r for r in results if r], key=lambda x: x['profit_factor'])
    print(f"\n🏆 最优: {best['name']}")

if __name__ == "__main__":
    main()
