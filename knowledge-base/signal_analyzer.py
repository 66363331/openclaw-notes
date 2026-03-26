#!/usr/bin/env python3
"""
SMC + Wyckoff 历史信号分析器
目标：检测CHoCH/BOS/假突/假跌信号，统计信号后价格走向的概率分布
"""

import csv
import math
from dataclasses import dataclass
from typing import List, Dict, Tuple, Optional

# ============ 数据加载 ============

def load_csv(filename: str) -> List[dict]:
    """加载CSV数据"""
    rows = []
    with open(filename, 'r', encoding='utf-8', errors='replace') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) < 6:
                continue
            try:
                rows.append({
                    'time': row[0],
                    'open': float(row[1]),
                    'high': float(row[2]),
                    'low': float(row[3]),
                    'close': float(row[4]),
                    'volume': float(row[5]) if row[5] else 0
                })
            except:
                continue
    return rows

# ============ 核心信号检测 ============

@dataclass
class SwingPoint:
    index: int
    type: str  # 'HH', 'HL', 'LH', 'LL'
    price: float

def find_swing_points(rows: List[dict], window: int = 5) -> List[SwingPoint]:
    """识别波段高低点"""
    points = []
    for i in range(window, len(rows) - window):
        highs = [rows[i]['high'] for i in range(i-window, i+window+1)]
        lows = [rows[i]['low'] for i in range(i-window, i+window+1)]
        
        if rows[i]['high'] == max(highs) and rows[i]['high'] > rows[i-window]['high'] and rows[i]['high'] > rows[i+window]['high']:
            if len(points) == 0 or points[-1].type != 'HH':
                points.append(SwingPoint(i, 'HH', rows[i]['high']))
        elif rows[i]['low'] == min(lows) and rows[i]['low'] < rows[i-window]['low'] and rows[i]['low'] < rows[i+window]['low']:
            if len(points) == 0 or points[-1].type != 'LL':
                points.append(SwingPoint(i, 'LL', rows[i]['low']))
    
    return points

def detect_choch(points: List[SwingPoint]) -> List[dict]:
    """
    检测CHoCH (Change of Character) - 趋势结构改变
    看连续 HH/LL 序列是否被打破
    """
    signals = []
    for i in range(4, len(points)):
        # 检查最近4个点
        p1, p2, p3, p4 = points[i-3], points[i-2], points[i-1], points[i]
        
        # 上涨趋势中的CHoCH（跌破LH）
        if p1.type == 'HH' and p2.type == 'LH' and p3.type == 'HH' and p4.type == 'LL':
            if p2.price < p1.price:  # LH < HH
                signals.append({
                    'type': 'CHoCH_Bull',
                    'index': p4.index,
                    'time': None,  # 简化版不保留time
                    'trigger_price': p4.price,
                    'broken_level': p2.price,  # 跌破LH
                    'description': f'Bull CHoCH: HH->LH->HH->LL, broke below LH at {p2.price:.2f}'
                })
        
        # 下跌趋势中的CHoCH（突破LH）
        if p1.type == 'LL' and p2.type == 'LH' and p3.type == 'LL' and p4.type == 'HH':
            if p2.price > p1.price:  # LH > LL
                signals.append({
                    'type': 'CHoCH_Bear',
                    'index': p4.index,
                    'time': None,
                    'trigger_price': p4.price,
                    'broken_level': p2.price,  # 突破LH
                    'description': f'Bear CHoCH: LL->LH->LL->HH, broke above LH at {p2.price:.2f}'
                })
    
    return signals

def detect_bos(rows: List[dict], window: int = 5) -> List[dict]:
    """
    检测BOS (Break of Structure) - 结构突破
    HH/HL序列被突破 = 上涨延续
    LH/LL序列被突破 = 下跌延续
    """
    signals = []
    
    for i in range(window * 2, len(rows) - 1):
        # 计算前window根K线的高低点
        start_idx = i - window * 2
        recent_highs = [rows[j]['high'] for j in range(start_idx, i)]
        recent_lows = [rows[j]['low'] for j in range(start_idx, i)]
        
        local_high = max(recent_highs)
        local_low = min(recent_lows)
        
        # 检查是否突破前高（上涨BOS）
        if rows[i+1]['close'] > local_high:
            signals.append({
                'type': 'BOS_Bull',
                'index': i + 1,
                'break_price': local_high,
                'close_after': rows[i+1]['close'],
                'description': f'Bull BOS: closed above recent high {local_high:.2f}'
            })
        
        # 检查是否跌破前低（下跌BOS）
        if rows[i+1]['close'] < local_low:
            signals.append({
                'type': 'BOS_Bear',
                'index': i + 1,
                'break_price': local_low,
                'close_after': rows[i+1]['close'],
                'description': f'Bear BOS: closed below recent low {local_low:.2f}'
            })
    
    return signals

def detect_fvg(rows: List[dict]) -> List[dict]:
    """
    检测FVG (Fair Value Gap) - 流动性缺口
    3根K线不重叠的空白区域
    """
    signals = []
    
    for i in range(2, len(rows) - 1):
        # 上涨中的FVG（中间K线低点 > 前后K线高点）
        mid_low = rows[i]['low']
        prev_high = rows[i-1]['high']
        next_high = rows[i+1]['high']
        
        if mid_low > prev_high and mid_low > next_high:
            gap_size = mid_low - max(prev_high, next_high)
            if gap_size > 0:
                signals.append({
                    'type': 'FVG_Bull',
                    'index': i,
                    'top': mid_low,
                    'bottom': max(prev_high, next_high),
                    'gap_size': gap_size,
                    'description': f'Bull FVG: gap up from {max(prev_high, next_high):.2f} to {mid_low:.2f}'
                })
        
        # 下跌中的FVG（中间K线高点 < 前后K线低点）
        mid_high = rows[i]['high']
        prev_low = rows[i-1]['low']
        next_low = rows[i+1]['low']
        
        if mid_high < prev_low and mid_high < next_low:
            gap_size = min(prev_low, next_low) - mid_high
            if gap_size > 0:
                signals.append({
                    'type': 'FVG_Bear',
                    'index': i,
                    'top': min(prev_low, next_low),
                    'bottom': mid_high,
                    'gap_size': gap_size,
                    'description': f'Bear FVG: gap down from {mid_high:.2f} to {min(prev_low, next_low):.2f}'
                })
    
    return signals

def detect_spring_upthrust(rows: List[dict], window: int = 3) -> List[dict]:
    """
    检测Spring（弹簧）和Upthrust（喷出）- 威科夫术语
    Spring: 跌破支撑后快速拉回（假跌破 = 买入信号）
    Upthrust: 突破阻力后快速回落（假突破 = 卖出信号）
    """
    signals = []
    
    for i in range(window, len(rows) - window):
        # 计算局部支撑/阻力
        local_lows = [rows[j]['low'] for j in range(i-window, i)]
        local_highs = [rows[j]['high'] for j in range(i-window, i)]
        support = min(local_lows)
        resistance = max(local_highs)
        
        # Spring: 跌破支撑但收盘收复
        if rows[i]['low'] < support:
            drop_depth = (support - rows[i]['low']) / support * 100  # 跌破深度%
            recovery = (rows[i]['close'] - rows[i]['low']) / (support - rows[i]['low']) * 100 if rows[i]['low'] < rows[i]['close'] else 0
            
            if rows[i]['close'] > support and recovery > 50:  # 收盘收复支撑，且回收 > 50%
                signals.append({
                    'type': 'Spring',
                    'index': i,
                    'level': support,
                    'drop_depth': drop_depth,
                    'recovery': recovery,
                    'description': f'Spring at {support:.2f}: dropped {drop_depth:.2f}%, recovered {recovery:.1f}%'
                })
        
        # Upthrust: 突破阻力但收盘回落
        if rows[i]['high'] > resistance:
            break_depth = (rows[i]['high'] - resistance) / resistance * 100  # 突破深度%
            reversal = (rows[i]['high'] - rows[i]['close']) / (rows[i]['high'] - resistance) * 100 if rows[i]['high'] > rows[i]['close'] else 0
            
            if rows[i]['close'] < resistance and reversal > 50:  # 收盘回落阻力下方，且回落 > 50%
                signals.append({
                    'type': 'Upthrust',
                    'index': i,
                    'level': resistance,
                    'break_depth': break_depth,
                    'reversal': reversal,
                    'description': f'Upthrust at {resistance:.2f}: broke {break_depth:.2f}%, reversed {reversal:.1f}%'
                })
    
    return signals

def detect_liquidity_sweep(rows: List[dict], window: int = 20) -> List[dict]:
    """
    检测流动性扫损（Sweep）
    快速刺穿波段高/低点，伴随大成交量，然后反转
    """
    signals = []
    
    for i in range(window, len(rows) - 1):
        # 检测是否突破前window高低点
        lookback_highs = [rows[j]['high'] for j in range(i-window, i)]
        lookback_lows = [rows[j]['low'] for j in range(i-window, i)]
        
        hh_price = max(lookback_highs)
        ll_price = min(lookback_lows)
        
        # 高点被刺穿 + 大成交量 + 反转
        if rows[i]['high'] > hh_price and rows[i]['close'] < hh_price:
            penetration = (rows[i]['high'] - hh_price) / hh_price * 100
            volume = rows[i]['volume']
            avg_vol = sum(rows[j]['volume'] for j in range(i-window, i)) / window
            
            if volume > avg_vol * 1.5 and penetration < 0.5:  # 轻微刺穿 + 大成交量
                signals.append({
                    'type': 'Sweep_HH',
                    'index': i,
                    'swept_level': hh_price,
                    'penetration': penetration,
                    'volume_ratio': volume / avg_vol if avg_vol > 0 else 0,
                    'description': f'Swept HH at {hh_price:.2f}, penetration {penetration:.3f}%, vol ratio {volume/avg_vol:.1f}x'
                })
        
        # 低点被刺穿 + 大成交量 + 反转
        if rows[i]['low'] < ll_price and rows[i]['close'] > ll_price:
            penetration = (ll_price - rows[i]['low']) / ll_price * 100
            volume = rows[i]['volume']
            avg_vol = sum(rows[j]['volume'] for j in range(i-window, i)) / window
            
            if volume > avg_vol * 1.5 and penetration < 0.5:
                signals.append({
                    'type': 'Sweep_LL',
                    'index': i,
                    'swept_level': ll_price,
                    'penetration': penetration,
                    'volume_ratio': volume / avg_vol if avg_vol > 0 else 0,
                    'description': f'Swept LL at {ll_price:.2f}, penetration {penetration:.3f}%, vol ratio {volume/avg_vol:.1f}x'
                })
    
    return signals

# ============ 统计分析 ============

def analyze_signal_outcome(rows: List[dict], signal: dict, forward_candles: int) -> Dict:
    """分析信号后forward_candles根K线的价格走向"""
    idx = signal['index']
    signal_price = rows[idx]['close']
    
    if idx + forward_candles >= len(rows):
        return None
    
    future_prices = [rows[idx + j]['close'] for j in range(1, forward_candles + 1)]
    future_highs = [rows[idx + j]['high'] for j in range(1, forward_candles + 1)]
    future_lows = [rows[idx + j]['low'] for j in range(1, forward_candles + 1)]
    
    # 计算信号类型方向
    is_bullish = 'Bull' in signal['type'] or 'Spring' in signal['type'] or 'Sweep_LL' in signal['type']
    is_bearish = 'Bear' in signal['type'] or 'Upthrust' in signal['type'] or 'Sweep_HH' in signal['type']
    
    results = {
        'signal_type': signal['type'],
        'signal_index': idx,
    }
    
    if is_bullish:
        # 统计最高点到信号点的涨幅
        max_rise = max(h - signal_price for h in future_highs)
        max_fall = signal_price - min(l for l in future_lows)
        results['max_rise'] = max_rise
        results['max_fall'] = max_fall
        results['went_up'] = max_rise > max_fall
        results['signal_return'] = max_rise / signal_price * 100  # 百分比涨幅
        
    elif is_bearish:
        max_fall = signal_price - min(l for l in future_lows)
        max_rise = max(h - signal_price for h in future_highs)
        results['max_fall'] = max_fall
        results['max_rise'] = max_rise
        results['went_down'] = max_fall > max_rise
        results['signal_return'] = max_fall / signal_price * 100
    
    return results

def calculate_win_rate(rows: List[dict], signals: List[dict], forward: int, min_return_pct: float = 0.1) -> Dict:
    """计算信号胜率"""
    outcomes = []
    
    for sig in signals:
        result = analyze_signal_outcome(rows, sig, forward)
        if result:
            outcomes.append(result)
    
    if not outcomes:
        return {'count': 0, 'win_rate': 0, 'avg_return': 0}
    
    wins = sum(1 for o in outcomes if ('went_up' in o and o['went_up']) or ('went_down' in o and o['went_down']))
    
    # 过滤有效信号（收益 > min_return_pct）
    valid = [o for o in outcomes if o.get('signal_return', 0) > min_return_pct]
    wins_filtered = sum(1 for o in valid if ('went_up' in o and o['went_up']) or ('went_down' in o and o['went_down']))
    
    avg_return = sum(o.get('signal_return', 0) for o in outcomes) / len(outcomes)
    
    return {
        'count': len(outcomes),
        'count_valid': len(valid),
        'wins': wins,
        'wins_filtered': wins_filtered,
        'win_rate': wins / len(outcomes) * 100,
        'win_rate_filtered': wins_filtered / len(valid) * 100 if valid else 0,
        'avg_return': avg_return
    }

# ============ 主程序 ============

def main():
    print("=" * 60)
    print("SMC + 威科夫 历史信号分析器")
    print("=" * 60)
    
    # 加载数据
    print("\n[1] 加载数据...")
    rows = load_csv('/home/lilei/.openclaw/workspace/knowledge-base/XAUUSDM15_utf8.csv')
    print(f"    共加载 {len(rows)} 根M15 K线")
    
    # 检测各种信号
    print("\n[2] 检测信号...")
    
    print("    - 识别波段点...")
    swing_points = find_swing_points(rows, window=5)
    print(f"    找到 {len(swing_points)} 个波段高低点")
    
    print("    - 检测CHoCH...")
    choch_signals = detect_choch(swing_points)
    print(f"    找到 {len(choch_signals)} 个CHoCH信号")
    
    print("    - 检测BOS...")
    bos_signals = detect_bos(rows, window=5)
    print(f"    找到 {len(bos_signals)} 个BOS信号")
    
    print("    - 检测FVG...")
    fvg_signals = detect_fvg(rows)
    print(f"    找到 {len(fvg_signals)} 个FVG信号")
    
    print("    - 检测Spring/Upthrust...")
    spring_signals = detect_spring_upthrust(rows, window=3)
    print(f"    找到 {len(spring_signals)} 个Spring/Upthrust信号")
    
    print("    - 检测流动性Sweep...")
    sweep_signals = detect_liquidity_sweep(rows, window=20)
    print(f"    找到 {len(sweep_signals)} 个Sweep信号")
    
    # 统计分析
    print("\n[3] 信号统计分析")
    print("-" * 60)
    
    forward_periods = [1, 3, 5, 10]  # 信号后1/3/5/10根K线
    
    for fp in forward_periods:
        print(f"\n📊 信号后{fp}根K线 ({fp*15}分钟) 的表现：")
        print("-" * 50)
        
        # CHoCH
        choch_stats = calculate_win_rate(rows, choch_signals, fp)
        print(f"  CHoCH:  {choch_stats['count']}个样本 | 胜率{choch_stats['win_rate']:.1f}% | 均幅{choch_stats['avg_return']:.3f}%")
        
        # BOS
        bos_stats = calculate_win_rate(rows, bos_signals, fp)
        print(f"  BOS:    {bos_stats['count']}个样本 | 胜率{bos_stats['win_rate']:.1f}% | 均幅{bos_stats['avg_return']:.3f}%")
        
        # FVG
        fvg_stats = calculate_win_rate(rows, fvg_signals, fp)
        print(f"  FVG:    {fvg_stats['count']}个样本 | 胜率{fvg_stats['win_rate']:.1f}% | 均幅{fvg_stats['avg_return']:.3f}%")
        
        # Spring/Upthrust
        spring_stats = calculate_win_rate(rows, spring_signals, fp)
        print(f"  Spring/Upthrust: {spring_stats['count']}个样本 | 胜率{spring_stats['win_rate']:.1f}% | 均幅{spring_stats['avg_return']:.3f}%")
        
        # Sweep
        sweep_stats = calculate_win_rate(rows, sweep_signals, fp)
        print(f"  Sweep:  {sweep_stats['count']}个样本 | 胜率{sweep_stats['win_rate']:.1f}% | 均幅{sweep_stats['avg_return']:.3f}%")
    
    # 组合信号分析（四重共振）
    print("\n[4] 组合信号分析")
    print("-" * 60)
    print("  检测【Zone① + Sweep + 假跌/假突】共振信号...")
    
    # 简单重叠检测：同区域Sweep + 反向FVG
    combined_count = 0
    combined_wins = 0
    
    for sweep in sweep_signals:
        idx = sweep['index']
        # 在Sweep后3根K线内找反向FVG
        for fvg in fvg_signals:
            if idx < fvg['index'] <= idx + 3:
                # 类型匹配：Sweep_LL + FVG_Bull 或 Sweep_HH + FVG_Bear
                if ('LL' in sweep['type'] and 'Bull' in fvg['type']) or \
                   ('HH' in sweep['type'] and 'Bear' in fvg['type']):
                    combined_count += 1
                    result = analyze_signal_outcome(rows, sweep, 5)
                    if result and (result.get('went_up') or result.get('went_down')):
                        combined_wins += 1
    
    if combined_count > 0:
        combined_wr = combined_wins / combined_count * 100
        print(f"  四重共振样本: {combined_count}个 | 胜率: {combined_wr:.1f}%")
    else:
        print("  未检测到足够的组合信号样本")
    
    # 输出详细样本
    print("\n[5] 详细信号样本（前20个）")
    print("-" * 60)
    
    print("\n【CHoCH样本】")
    for i, sig in enumerate(choch_signals[:10]):
        print(f"  {i+1}. {sig['description']}")
    
    print("\n【Sweep样本】")
    for i, sig in enumerate(sweep_signals[:10]):
        print(f"  {i+1}. {sig['description']}")
    
    print("\n" + "=" * 60)
    print("分析完成！")
    print("=" * 60)

if __name__ == '__main__':
    main()
