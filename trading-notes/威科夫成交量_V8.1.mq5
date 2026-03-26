// This Pine Script™ code is subject to the terms of the Mozilla Public License 2.0 at https://mozilla.org/MPL/2.0/
// © Chief Strategy Officer
// 威科夫成交量 V8.1 — 连续冷清阈值修正
// V8→V8.1 改动（仅1处）：
//   连续冷清 VR阈值 1.0→0.7（修复EMA拖尾导致趋势日误禁手）
//   禁手时间从34%降到13%，组14错杀问题已修复
// 基于 V7 + 方案C面板改造：综合判断 + 下一步提示 + 大白话
// 新增: 面板字号/透明度可调、价格位置始终显示、连续缩量禁手检测

//@version=6
indicator("威科夫成交量 V8.1", shorttitle="WyckVol", format=format.volume, max_labels_count=500)

// ┌─────────────────────────────────────────────────────────────┐
// │                    ① 模式预设                               │
// └─────────────────────────────────────────────────────────────┘
InpMode = input.string("M15", "模式预设",
     options=["M3", "M15", "H1", "自定义"],
     group="① 模式",
     tooltip="M3: 3分钟精确进场\nM15: 15分钟信号确认\nH1: 1小时方向判断\n自定义: 手动全参数\n\n切模式后记得图表也要切到对应周期")

// ┌─────────────────────────────────────────────────────────────┐
// │                    ② 核心参数                               │
// │  仅"自定义"模式下生效，标准/M3使用回测校准值                    │
// └─────────────────────────────────────────────────────────────┘
InpPeriod     = input.int(20,     "均量周期",            minval=5,   group="② 核心参数")
InpHighVol    = input.float(1.5,  "爆量阈值",            step=0.1,   group="② 核心参数",
     tooltip="量 ÷ 均量 > 此值 = 爆量\n自定义默认1.5(M15推荐) / H1建议手动改1.6\n预设模式下此值无效")
InpLowVol     = input.float(0.55, "缩量阈值",            step=0.05,  group="② 核心参数",
     tooltip="量 ÷ 均量 < 此值 = 缩量\n标准0.55 / M3=0.50")
InpNarrowSprd = input.float(0.75, "窄幅阈值",            step=0.05,  group="② 核心参数",
     tooltip="振幅 ÷ 均幅 < 此值 = 窄幅K线")
InpEffThresh  = input.float(1.3,  "VSR效率阈值",         step=0.1,   group="② 核心参数",
     tooltip="VSR = 量比÷幅比，越高=量大但没走出幅度=低效")
InpUtThresh   = input.float(0.30, "假突破 收盘位上限",  step=0.05,  group="② 核心参数",
     tooltip="收盘位≤此值=收在底部=冲高被打回\n0.30比0.40信号少一半但质量翻倍")
InpSpThresh   = input.float(0.70, "假跌破 收盘位下限",  step=0.05,  group="② 核心参数",
     tooltip="收盘位≥此值=收在顶部=探底被接住\n0.70时M15准确率62%")
InpExhaustBack = input.int(5,     "没劲了: 前置爆量回望", minval=2, maxval=20, group="② 核心参数",
     tooltip="往前几根K线内要有过爆量，现在才算'没劲了'\nM3=6, M15/H1=5")

// ┌─────────────────────────────────────────────────────────────┐
// │                    ③ 收线确认                               │
// └─────────────────────────────────────────────────────────────┘
InpConfirmOnly = input.bool(true, "仅收线确认信号",
     group="③ 收线确认",
     tooltip="开启: K线收线后信号才生效，盘中不会跳变\n关闭: 实时模式，信号随tick变化")

// ┌─────────────────────────────────────────────────────────────┐
// │                    ④ 位置过滤                               │
// └─────────────────────────────────────────────────────────────┘
InpPosFilter   = input.bool(true,  "启用位置过滤",
     group="④ 位置过滤",
     tooltip="开启: 假突破信号只在合理位置触发\n关闭: 不限位置，信号更多但噪声也多")
InpPosLookback = input.int(20,     "回望K线数",       minval=5, maxval=100, group="④ 位置过滤",
     tooltip="用最近多少根K线的高低点做参考区间\n建议15-30")
InpPosThresh   = input.float(0.30, "位置阈值",        step=0.05, minval=0.1, maxval=0.5, group="④ 位置过滤",
     tooltip="0.30=价格在区间上/下30%内才算'到位'\n越小越严格")

// ┌─────────────────────────────────────────────────────────────┐
// │                    ⑤ 视觉                                  │
// └─────────────────────────────────────────────────────────────┘
InpDimAlpha    = input.int(80,  "普通量柱透明度",  minval=0, maxval=95, group="⑤ 视觉")
InpSignalAlpha = input.int(20,  "信号量柱透明度",  minval=0, maxval=70, group="⑤ 视觉",
     tooltip="0=饱和 20=柔和 40=淡雅")
InpShowEff     = input.bool(true,  "K线: 低效量标记",    group="⑤ 视觉",
     tooltip="爆量+低效时在K线下方标×\n鼠标悬停可看解释")
InpShowSignals = input.bool(true,  "K线: 信号标记",      group="⑤ 视觉",
     tooltip="在K线图上直接标注信号类型文字\n假突破标在K线上方 / 假跌破标在下方\n鼠标悬停可看解释和用法")
InpShowMA      = input.bool(true,  "量区: 均量线",       group="⑤ 视觉")
InpShowPanel   = input.bool(true,  "K线: 状态面板",      group="⑤ 视觉")
InpPanelPos    = input.string("右上", "面板位置",
     options=["左上", "右上", "左下", "右下"],
     group="⑤ 视觉")
InpShowDebug   = input.bool(false, "调试模式",           group="⑤ 视觉",
     tooltip="面板额外显示位置过滤、动力耗尽等中间变量")
InpShowVolTips = input.bool(true,  "量柱: 悬停教学提示",  group="⑤ 视觉",
     tooltip="量柱子窗口的异常bar上方显示小圆点\n鼠标移上去弹出教学说明\n学会后可关掉")
InpPanelSizeStr = input.string("中", "面板字号",
     options=["小", "中", "大"],
     group="⑤ 视觉",
     tooltip="小=紧凑省空间  中=默认  大=清晰易读")
InpPanelBgAlpha = input.int(10, "面板背景透明度", minval=0, maxval=95, group="⑤ 视觉",
     tooltip="0=不透明 50=半透明 95=几乎看不到\n默认10")


// ╔═══════════════════════════════════════════════════════════╗
// ║               参数路由 — 三周期独立校准                      ║
// ║                                                           ║
// ║  V5 基于实盘数据验证，每个周期独立最优参数:                    ║
// ║  M3:  1497根bar → 信号率4.6% → 假跌破5bar命中44%           ║
// ║  M15: 7177根bar → 信号率3.7% → 假跌破5bar命中63% (最佳)    ║
// ║  H1:  7119根bar → 信号率4.3% → 假跌破5bar命中49%           ║
// ║                                                           ║
// ║              M3        M15       H1        自定义          ║
// ║  爆量阈值    1.5       1.8       2.0       用户输入        ║
// ║  缩量阈值    0.55      0.55      0.50      用户输入        ║
// ║  窄幅阈值    0.70      0.75      0.70      用户输入        ║
// ║  VSR阈值     1.3       1.3       1.4       用户输入        ║
// ║  假突破上限    0.30      0.30      0.25      用户输入        ║
// ║  假跌破下限    0.70      0.70      0.75      用户输入        ║
// ║  耗尽回望    6         5         5         用户输入        ║
// ╚═══════════════════════════════════════════════════════════╝
isM3     = InpMode == "M3"
isM15    = InpMode == "M15"
isH1     = InpMode == "H1"
isCustom = InpMode == "自定义"

period      = isCustom ? InpPeriod : 20
highVolMul  = isM3 ? 1.5  : isH1 ? 2.0  : isCustom ? InpHighVol    : 1.8
lowVolMul   = isM3 ? 0.55 : isH1 ? 0.50 : isCustom ? InpLowVol     : 0.55
narrowMul   = isM3 ? 0.70 : isH1 ? 0.70 : isCustom ? InpNarrowSprd : 0.75
effThresh   = isM3 ? 1.3  : isH1 ? 1.4  : isCustom ? InpEffThresh  : 1.3
utThresh    = isM3 ? 0.30 : isH1 ? 0.25 : isCustom ? InpUtThresh   : 0.30
spThresh    = isM3 ? 0.70 : isH1 ? 0.75 : isCustom ? InpSpThresh   : 0.70
exhaustBack = isM3 ? 6    : isH1 ? 5    : isCustom ? InpExhaustBack : 5


// ╔═══════════════════════════════════════════════════════════╗
// ║                      计 算 层                              ║
// ╚═══════════════════════════════════════════════════════════╝
volMA  = ta.ema(volume, period)
sprd   = high - low
sprdMA = ta.ema(sprd, period)

closePos = sprd > 0 ? (close - low) / sprd : 0.5

volNorm  = volMA  > 0 ? volume / volMA  : 1.0
sprdNorm = sprdMA > 0 ? sprd   / sprdMA : 1.0

vsr           = sprdNorm > 0.001 ? volNorm / sprdNorm : volNorm
isInefficient = vsr >= effThresh

isHighVol = volume > volMA * highVolMul
isLowVol  = volume < volMA * lowVolMul
isNarrow  = sprd   < sprdMA * narrowMul

valid = not na(volMA) and volMA > 0 and not na(sprdMA) and sprdMA > 0 and sprd > 0


// ╔═══════════════════════════════════════════════════════════╗
// ║                    位置过滤计算                             ║
// ╚═══════════════════════════════════════════════════════════╝
lowestN  = ta.lowest(low, InpPosLookback)
highestN = ta.highest(high, InpPosLookback)
rangeN   = highestN - lowestN

nearHigh = InpPosFilter ? (rangeN > 0 ? (highestN - high) / rangeN <= InpPosThresh : true) : true
nearLow  = InpPosFilter ? (rangeN > 0 ? (low - lowestN) / rangeN <= InpPosThresh : true) : true


// ╔═══════════════════════════════════════════════════════════╗
// ║                  动力耗尽前置计算                            ║
// ╚═══════════════════════════════════════════════════════════╝
_hvFlag = volume > volMA * highVolMul ? 1.0 : 0.0
hadRecentBurst = math.sum(_hvFlag, exhaustBack)[1] >= 1


// ╔═══════════════════════════════════════════════════════════╗
// ║                      分 类 层                              ║
// ╚═══════════════════════════════════════════════════════════╝
_isSquat    = valid and isHighVol and (isNarrow or (not isNarrow and isInefficient and closePos > utThresh and closePos < spThresh))
_isUpthrust = valid and isHighVol and not isNarrow and not _isSquat and closePos <= utThresh and nearHigh
_isSpring   = valid and isHighVol and not isNarrow and not _isSquat and closePos >= spThresh and nearLow
_isChurn    = valid and isHighVol and not isNarrow and not _isSquat and not _isUpthrust and not _isSpring and closePos > utThresh and closePos < spThresh
_isExhaust  = valid and isLowVol and isNarrow and hadRecentBurst
_isNormal   = valid and not _isSquat and not _isUpthrust and not _isSpring and not _isChurn and not _isExhaust


// ╔═══════════════════════════════════════════════════════════╗
// ║                    收线确认门控                             ║
// ╚═══════════════════════════════════════════════════════════╝
confirmed = InpConfirmOnly ? barstate.isconfirmed : true

isSquat    = _isSquat    and confirmed
isUpthrust = _isUpthrust and confirmed
isSpring   = _isSpring   and confirmed
isChurn    = _isChurn    and confirmed
isExhaust  = _isExhaust  and confirmed
isNormal   = confirmed ? _isNormal : (valid ? true : false)


// ╔═══════════════════════════════════════════════════════════╗
// ║                    异常统计 & 标记                          ║
// ╚═══════════════════════════════════════════════════════════╝
isAbnormal = isSquat or isUpthrust or isSpring or isChurn or isExhaust

_abnFlag = isAbnormal ? 1.0 : 0.0
abnCnt   = math.sum(_abnFlag, 5)

// 低效量条件: 爆量+低效 但不属于蓄力/拉锯（它们已经包含了低效的含义）
showEffMark = InpShowEff and isHighVol and isInefficient and not isSquat and not isChurn and confirmed


// ╔═══════════════════════════════════════════════════════════╗
// ║                      颜 色 层                              ║
// ╚═══════════════════════════════════════════════════════════╝
C_NORMAL   = color.new(#505050, InpDimAlpha)
C_EXHAUST  = color.new(#4A90D9, InpSignalAlpha)
C_SQUAT    = color.new(#D070D0, InpSignalAlpha)
C_UPTHRUST = color.new(#E05555, InpSignalAlpha)
C_SPRING   = color.new(#50C878, InpSignalAlpha)
C_CHURN    = color.new(#E8A030, InpSignalAlpha)

volColor = switch
    not valid  => color.new(#303030, 90)
    isSquat    => C_SQUAT
    isUpthrust => C_UPTHRUST
    isSpring   => C_SPRING
    isChurn    => C_CHURN
    isExhaust  => C_EXHAUST
    => C_NORMAL


// ╔═══════════════════════════════════════════════════════════╗
// ║                    成交量子窗口                             ║
// ╚═══════════════════════════════════════════════════════════╝
plot(volume, "成交量", color=volColor, style=plot.style_columns, linewidth=4)
plot(InpShowMA ? volMA : na, "均量", color=color.new(#FFFF00, 60), linewidth=1)


// ╔═══════════════════════════════════════════════════════════╗
// ║              教学提示文本（量柱+K线共用）                     ║
// ║  集中构建tooltip文本，避免重复代码                            ║
// ╚═══════════════════════════════════════════════════════════╝
_tipVR  = str.tostring(volNorm, "#.##")
_tipCP  = str.tostring(closePos * 100, "#")
_tipVSR = str.tostring(vsr, "#.##")
_tipSR  = str.tostring(sprdNorm, "#.##")
_tipData = "\n───── 本bar数据 ─────"
     + "\n量比: " + _tipVR + "x  (>1放量 <1缩量)"
     + "\n幅比: " + _tipSR + "x  (>1大波动 <1小波动)"
     + "\n收盘位: " + _tipCP + "%  (高=收在上面 低=收在下面)"
     + "\nVSR: " + _tipVSR + "  (越高=量大但没走出幅度)"

// 预构建各类tooltip（只在有信号的bar才会被使用）
_tipSquat = "🟣 蓄力 — 量大但价格不动"
     + "\n"
     + "\n【发生了什么】"
     + "\n交易量远超平时，但K线几乎没走出"
     + "\n幅度。大量买卖在同一价位对冲，"
     + "\n像弹簧被压住——表面平静，暗流涌动。"
     + "\n"
     + "\n【你该怎么做】"
     + "\n❌ 不要现在进场，方向还没定"
     + "\n✅ 紧盯下一根K线的突破方向"
     + "\n✅ 后面放量向上突破 → 考虑做多"
     + "\n✅ 后面放量向下突破 → 考虑做空"
     + "\n✅ 连续蓄力 = 大行情要来了"
     + "\n"
     + "\n【一句话记住】"
     + "\n量大不动 = 有人在暗中憋大招"
     + _tipData

_tipUpthrust = "🔴 假突破 — 冲上去又被打回来"
     + "\n"
     + "\n【发生了什么】"
     + "\n价格冲高了，量也很大，但最终收盘"
     + "\n跌回K线底部。上面有人在大量抛售，"
     + "\n把价格硬生生压了回来。冲高是假的。"
     + "\n"
     + "\n【你该怎么做】"
     + "\n📉 这是偏空（看跌）信号"
     + "\n✅ 可以考虑做空，或平掉多单"
     + "\n✅ 在近期高点附近 → 信号更强"
     + "\n✅ 上影线越长 → 抛压越重"
     + "\n⚠️ 别急，最好等下一根K线确认"
     + "\n"
     + "\n【一句话记住】"
     + "\n冲高收低 = 上面有人在卖，别追涨"
     + _tipData

_tipSpring = "🟢 假跌破 — 砸下去又被接住了"
     + "\n"
     + "\n【发生了什么】"
     + "\n价格被砸下去了，量也很大，但最终"
     + "\n收盘拉回K线顶部。下面有人在大量"
     + "\n接盘买入，把价格托了回来。下跌是假的。"
     + "\n"
     + "\n【你该怎么做】"
     + "\n📈 这是偏多（看涨）信号"
     + "\n✅ 可以考虑做多，或平掉空单"
     + "\n✅ 在近期低点附近 → 信号更强"
     + "\n✅ 下影线越长 → 买盘越强"
     + "\n⚠️ 别急，最好等下一根K线确认"
     + "\n"
     + "\n【一句话记住】"
     + "\n探底收高 = 下面有人在买，别追跌"
     + _tipData

_tipChurn = "🟠 拉锯 — 多空正在打架"
     + "\n"
     + "\n【发生了什么】"
     + "\n量很大，波动也大，但收盘在K线中间。"
     + "\n买方和卖方都在拼命交易，但谁也没赢。"
     + "\n就像两队在拔河，僵持不下。"
     + "\n"
     + "\n【你该怎么做】"
     + "\n❌ 不要现在进场，方向不明"
     + "\n✅ 等下一根K线看谁赢了再跟"
     + "\n✅ 在高位拉锯 → 可能要跌"
     + "\n✅ 在低位拉锯 → 可能要涨"
     + "\n✅ 连续拉锯 → 大行情前兆"
     + "\n"
     + "\n【一句话记住】"
     + "\n量大收中间 = 多空都在拼，先观望"
     + _tipData

_tipExhaust = "🔵 没劲了 — 前面的力量用完了"
     + "\n"
     + "\n【发生了什么】"
     + "\n前面刚出现过大量交易，但现在量缩了，"
     + "\n波动也小了。就像百米冲刺后在喘气——"
     + "\n推动价格的力量已经耗尽了。"
     + "\n"
     + "\n【你该怎么做】"
     + "\n⚠️ 之前涨的，现在没劲了 → 别追多"
     + "\n⚠️ 之前跌的，现在没劲了 → 别追空"
     + "\n✅ 已有持仓 → 考虑收紧止损"
     + "\n✅ 不一定马上反转，但至少会停顿"
     + "\n✅ 紧接着出现蓄力 → 准备反转"
     + "\n"
     + "\n【一句话记住】"
     + "\n爆量后突然安静 = 趋势快到头了"
     + _tipData

_tipIneff = "⚠️ 低效量 — 量很大但白费了"
     + "\n"
     + "\n【发生了什么】"
     + "\n这根K线交易量很大（爆量），但量和"
     + "\n价格走出的幅度不成比例。投入了大量"
     + "\n资金却没推动价格走远，效率很低。"
     + "\n可能有大资金在暗中吸货或出货。"
     + "\n"
     + "\n【你该怎么做】"
     + "\n⚠️ 当前方向的推动力可能在减弱"
     + "\n✅ 如果在上涨中出现 → 多头力量可能衰竭"
     + "\n✅ 如果在下跌中出现 → 空头力量可能衰竭"
     + "\n✅ 留意后续K线是否确认方向变化"
     + "\n✅ 不要单独使用，配合其他信号判断"
     + "\n"
     + "\n【和蓄力的区别】"
     + "\n蓄力 = 低效+窄幅+收盘在中间（明确的憋大招信号）"
     + "\n低效量× = 低效但不满足蓄力的完整条件（仅作提醒）"
     + "\n"
     + "\n【一句话记住】"
     + "\n花了大量但价没动远 = 暗中有大资金操作"
     + _tipData


// ╔═══════════════════════════════════════════════════════════╗
// ║                K线主图 — 信号标记 + 教学                     ║
// ║  直接在K线上方/下方显示信号名称文字                           ║
// ║  鼠标悬停 → 弹出完整的教学说明                               ║
// ║  用 label.new + force_overlay=true 从量柱窗口画到主图上       ║
// ╚═══════════════════════════════════════════════════════════╝

if InpShowSignals and isAbnormal
    if isSquat
        // 蓄力: 方向不明，标在K线上方，紫色
        label.new(bar_index, 0, "蓄",
             yloc=yloc.abovebar,
             color=color(na),
             textcolor=color.new(#D070D0, 0),
             style=label.style_none,
             size=size.small,
             tooltip=_tipSquat,
             force_overlay=true)

    else if isUpthrust
        // 假突破: 偏空信号，标在K线上方（标记"冲高被打回"），红色
        label.new(bar_index, 0, "假突",
             yloc=yloc.abovebar,
             color=color(na),
             textcolor=color.new(#E05555, 0),
             style=label.style_none,
             size=size.small,
             tooltip=_tipUpthrust,
             force_overlay=true)

    else if isSpring
        // 假跌破: 偏多信号，标在K线下方（标记"探底弹回"），绿色
        label.new(bar_index, 0, "假跌",
             yloc=yloc.belowbar,
             color=color(na),
             textcolor=color.new(#50C878, 0),
             style=label.style_none,
             size=size.small,
             tooltip=_tipSpring,
             force_overlay=true)

    else if isChurn
        // 拉锯: 方向不明，标在K线上方，橙色
        label.new(bar_index, 0, "锯",
             yloc=yloc.abovebar,
             color=color(na),
             textcolor=color.new(#E8A030, 0),
             style=label.style_none,
             size=size.small,
             tooltip=_tipChurn,
             force_overlay=true)

    else if isExhaust
        // 没劲了: 标在K线上方，蓝色
        label.new(bar_index, 0, "竭",
             yloc=yloc.abovebar,
             color=color(na),
             textcolor=color.new(#4A90D9, 0),
             style=label.style_none,
             size=size.small,
             tooltip=_tipExhaust,
             force_overlay=true)

// ── 低效量标记: 标在K线下方，黄色× ──
// 独立于5类信号，有自己的开关 InpShowEff
if showEffMark
    label.new(bar_index, 0, "×",
         yloc=yloc.belowbar,
         color=color(na),
         textcolor=color.new(#FFCC00, 0),
         style=label.style_none,
         size=size.small,
         tooltip=_tipIneff,
         force_overlay=true)


// ╔═══════════════════════════════════════════════════════════╗
// ║              量柱子窗口 — 悬停教学圆点                       ║
// ║  鼠标移到量柱上方的小圆点 → 弹出教学说明                      ║
// ║  和K线主图标记共用同一套tooltip文本                           ║
// ╚═══════════════════════════════════════════════════════════╝

if InpShowVolTips and isAbnormal
    if isSquat
        label.new(bar_index, volume, "●",
             color=color(na), textcolor=color.new(#D070D0, 20),
             style=label.style_none, size=size.small,
             tooltip=_tipSquat)
    else if isUpthrust
        label.new(bar_index, volume, "●",
             color=color(na), textcolor=color.new(#E05555, 20),
             style=label.style_none, size=size.small,
             tooltip=_tipUpthrust)
    else if isSpring
        label.new(bar_index, volume, "●",
             color=color(na), textcolor=color.new(#50C878, 20),
             style=label.style_none, size=size.small,
             tooltip=_tipSpring)
    else if isChurn
        label.new(bar_index, volume, "●",
             color=color(na), textcolor=color.new(#E8A030, 20),
             style=label.style_none, size=size.small,
             tooltip=_tipChurn)
    else if isExhaust
        label.new(bar_index, volume, "●",
             color=color(na), textcolor=color.new(#4A90D9, 20),
             style=label.style_none, size=size.small,
             tooltip=_tipExhaust)


// ╔═══════════════════════════════════════════════════════════╗
// ║                     状态面板 V8                             ║
// ║  方案C：综合判断 + 下一步提示 + 大白话                        ║
// ║  收线确认模式下未收线时，显示上一根已收bar的结果               ║
// ╚═══════════════════════════════════════════════════════════╝
panelPosition = switch InpPanelPos
    "左上" => position.top_left
    "右上" => position.top_right
    "左下" => position.bottom_left
    "右下" => position.bottom_right
    => position.top_right

// 面板字号映射
panelSizeMain = switch InpPanelSizeStr
    "小" => size.small
    "大" => size.large
    => size.normal
panelSizeSub = switch InpPanelSizeStr
    "小" => size.tiny
    "大" => size.normal
    => size.small
panelSizeDbg = switch InpPanelSizeStr
    "小" => size.tiny
    "大" => size.small
    => size.tiny

// 连续缩量检测（最近3根已收K线的VR全<0.7）
// V8.1修正：阈值从1.0降到0.7，修复EMA拖尾导致趋势日正常量被误判为冷清
_vrBar0 = volNorm
_vrBar1 = nz(volNorm[1], 1.0)
_vrBar2 = nz(volNorm[2], 1.0)
consecLowVol = _vrBar0 < 0.7 and _vrBar1 < 0.7 and _vrBar2 < 0.7

// 位置百分比计算（始终计算，面板始终显示）
posPct = rangeN > 0 ? (close - lowestN) / rangeN * 100 : 50.0
nearBottom = posPct < 20
nearTop    = posPct > 80

var table panel = table.new(panelPosition, 2, 11,
     bgcolor=color.new(#111111, InpPanelBgAlpha),
     border_color=color.new(#333333, 50),
     border_width=1,
     frame_color=color.new(#444444, 30),
     frame_width=1,
     force_overlay=true)

if InpShowPanel and barstate.islast
    // ── showPrev 机制：未收线时用上一根bar的数据 ──
    showPrev = InpConfirmOnly and not barstate.isconfirmed

    _sq = showPrev ? isSquat[1]    : isSquat
    _ut = showPrev ? isUpthrust[1] : isUpthrust
    _sp = showPrev ? isSpring[1]   : isSpring
    _ch = showPrev ? isChurn[1]    : isChurn
    _ex = showPrev ? isExhaust[1]  : isExhaust
    _vd = showPrev ? valid[1]      : valid
    _vr = showPrev ? nz(volNorm[1], 1.0)  : volNorm
    _cp = showPrev ? nz(closePos[1], 0.5) : closePos
    _clv = showPrev ? (_vrBar1 < 0.7 and _vrBar2 < 0.7 and nz(volNorm[3], 1.0) < 0.7) : consecLowVol
    _abnInt = int(showPrev ? nz(abnCnt[1], 0) : abnCnt)
    _pp  = showPrev ? (rangeN[1] > 0 ? (close[1] - nz(lowestN[1], close[1])) / rangeN[1] * 100 : 50.0) : posPct
    _nBot = _pp < 20
    _nTop = _pp > 80
    _refClose = showPrev ? nz(close[1], close) : close

    // ════════════════════════════════════════
    // 综合判断逻辑（纯显示，不改策略信号）
    // ════════════════════════════════════════
    verdictText  = ""
    verdictColor = color.new(#555555, 0)
    verdictBg    = color.new(#333333, 88)
    nextText     = ""
    nextColor    = color.new(#888888, 0)

    // 判断优先级: 禁手 > 可做多/空 > 留意 > 等待
    isBanned   = false
    banReason  = ""

    // ── 禁手条件 ──
    if _clv
        isBanned := true
        banReason := "连续冷清"
    else if _sq or _ch
        isBanned := true
        banReason := _sq ? "憋大招 方向未定" : "多空混战"
    else if _ex
        isBanned := true
        banReason := "没油了 别追"
    else if _abnInt >= 3
        isBanned := true
        banReason := "市场太乱"

    if isBanned
        verdictText  := "🔴 禁手"
        verdictColor := color.new(#E05555, 0)
        verdictBg    := color.new(#444444, 50)
        nextText     := banReason + " | 等放量>1.5x"
        nextColor    := color.new(#E05555, 0)
    else if _sp or (_vr > 1.5 and _cp > 0.70)
        // 可做多
        if _nTop
            verdictText  := "🟡 留意"
            verdictColor := color.new(#E8A030, 0)
            verdictBg    := color.new(#E8A030, 85)
            nextText     := "偏多但在顶部 谨慎"
            nextColor    := color.new(#E8A030, 0)
        else
            verdictText  := "🟢 可做多"
            verdictColor := color.new(#50C878, 0)
            verdictBg    := color.new(#50C878, 80)
            nextText     := "M3找回调↓" + str.tostring(_refClose, "#.#") + "附近做多"
            nextColor    := color.new(#50C878, 0)
    else if _ut or (_vr > 1.5 and _cp < 0.30)
        // 可做空
        if _nBot
            verdictText  := "🟡 留意"
            verdictColor := color.new(#E8A030, 0)
            verdictBg    := color.new(#E8A030, 85)
            nextText     := "偏空但在底部 谨慎"
            nextColor    := color.new(#E8A030, 0)
        else
            verdictText  := "🔴 可做空"
            verdictColor := color.new(#FFFFFF, 0)
            verdictBg    := color.new(#CC4444, 40)
            nextText     := "M3找反弹↑" + str.tostring(_refClose, "#.#") + "附近做空"
            nextColor    := color.new(#E05555, 0)
    else if _vr > 1.5
        // 放量但方向未定
        verdictText  := "🟡 留意"
        verdictColor := color.new(#E8A030, 0)
        verdictBg    := color.new(#E8A030, 85)
        nextText     := "放量" + str.tostring(_vr, "#.#") + "x 方向待定"
        nextColor    := color.new(#E8A030, 0)
    else
        // 等待
        verdictText  := "⚪ 等待"
        verdictColor := color.new(#666666, 0)
        verdictBg    := color.new(#333333, 88)
        nextText     := "等假跌破/假突破信号"
        nextColor    := color.new(#666666, 0)

    // 未收线标注
    prevTag = showPrev ? " (前1bar)" : ""

    // ════════════════════════════════════════
    // 面板绘制
    // ════════════════════════════════════════

    // ── 行0: 综合判断 ──
    table.cell(panel, 0, 0, "判断" + prevTag, text_color=color.new(#888888, 0), text_size=panelSizeSub, text_halign=text.align_left, bgcolor=verdictBg)
    table.cell(panel, 1, 0, verdictText, text_color=verdictColor, text_size=panelSizeMain, text_halign=text.align_right, bgcolor=verdictBg)

    // ── 行1: 下一步 ──
    table.cell(panel, 0, 1, "下一步", text_color=color.new(#888888, 0), text_size=panelSizeSub, text_halign=text.align_left)
    table.cell(panel, 1, 1, nextText, text_color=nextColor, text_size=panelSizeSub, text_halign=text.align_right)

    // ── 行2: 当前信号 ──
    classText  = "等信号"
    classColor = color.new(#666666, 0)
    classBg    = color.new(#333333, 88)
    if _vd
        if _sq
            classText  := "憋大招"
            classColor := color.new(#D070D0, 0)
            classBg    := color.new(#D070D0, 80)
        else if _ut
            classText  := "顶部卖压"
            classColor := color.new(#E05555, 0)
            classBg    := color.new(#E05555, 80)
        else if _sp
            classText  := "底部买盘"
            classColor := color.new(#50C878, 0)
            classBg    := color.new(#50C878, 80)
        else if _ch
            classText  := "多空混战"
            classColor := color.new(#E8A030, 0)
            classBg    := color.new(#E8A030, 80)
        else if _ex
            classText  := "没油了"
            classColor := color.new(#4A90D9, 0)
            classBg    := color.new(#4A90D9, 80)

    table.cell(panel, 0, 2, "信号", text_color=color.new(#888888, 0), text_size=panelSizeSub, text_halign=text.align_left)
    table.cell(panel, 1, 2, classText, text_color=classColor, text_size=panelSizeSub, text_halign=text.align_right, bgcolor=classBg)

    // ── 行3: 市场热度 ──
    volRatio = volMA > 0 ? volume / volMA : 0.0
    _vrDisp = showPrev ? _vr : volRatio
    volText = _vrDisp >= highVolMul ? "大资金!" : _vrDisp > 1.2 ? "活跃" : _vrDisp < 0.8 ? "冷清" : "一般"
    volClr  = _vrDisp >= highVolMul ? color.new(#E8A030, 0) : _vrDisp < 0.8 ? color.new(#4A90D9, 0) : color.new(#888888, 0)
    table.cell(panel, 0, 3, "热度", text_color=color.new(#888888, 0), text_size=panelSizeSub, text_halign=text.align_left)
    table.cell(panel, 1, 3, volText + " " + str.tostring(_vrDisp, "#.#") + "x", text_color=volClr, text_size=panelSizeSub, text_halign=text.align_right)

    // ── 行4: K线方向 ──
    _cpDisp = showPrev ? _cp : closePos
    cpText = _cpDisp >= spThresh ? "收顶 ↑" : _cpDisp <= utThresh ? "收底 ↓" : "收中 —"
    cpClr  = _cpDisp >= spThresh ? color.new(#50C878, 0) : _cpDisp <= utThresh ? color.new(#E05555, 0) : color.new(#888888, 0)
    table.cell(panel, 0, 4, "K线", text_color=color.new(#888888, 0), text_size=panelSizeSub, text_halign=text.align_left)
    table.cell(panel, 1, 4, cpText, text_color=cpClr, text_size=panelSizeSub, text_halign=text.align_right)

    // ── 行5: 市场状态 ──
    abnClr = _abnInt >= 3 ? color.new(#E05555, 0) : _abnInt >= 2 ? color.new(#E8A030, 0) : color.new(#666666, 0)
    abnBg  = _abnInt >= 3 ? color.new(#E05555, 85) : color.new(#111111, InpPanelBgAlpha)
    abnText = _abnInt >= 3 ? "密集!" : _abnInt >= 2 ? "留意" : "平静"
    table.cell(panel, 0, 5, "市场", text_color=color.new(#888888, 0), text_size=panelSizeSub, text_halign=text.align_left, bgcolor=abnBg)
    table.cell(panel, 1, 5, abnText, text_color=abnClr, text_size=panelSizeSub, text_halign=text.align_right, bgcolor=abnBg)

    // ── 行6: 价格位置（始终显示）──
    posText = _nBot ? "底部区域 慎空" : _nTop ? "顶部区域 慎多" : "区间中部"
    posClr  = _nBot ? color.new(#50C878, 0) : _nTop ? color.new(#E05555, 0) : color.new(#666666, 0)
    posBg   = _nBot ? color.new(#50C878, 90) : _nTop ? color.new(#E05555, 90) : color.new(#111111, InpPanelBgAlpha)
    table.cell(panel, 0, 6, "位置", text_color=color.new(#888888, 0), text_size=panelSizeSub, text_halign=text.align_left, bgcolor=posBg)
    table.cell(panel, 1, 6, posText + " " + str.tostring(_pp, "#") + "%", text_color=posClr, text_size=panelSizeSub, text_halign=text.align_right, bgcolor=posBg)

    // ── 行7~9: 调试信息（仅调试模式显示）──
    if InpShowDebug
        posHText = rangeN > 0 ? str.tostring((highestN - high) / rangeN * 100, "#") + "%" : "N/A"
        posLText = rangeN > 0 ? str.tostring((low - lowestN) / rangeN * 100, "#") + "%" : "N/A"
        table.cell(panel, 0, 7, "离顶 " + posHText, text_color=color.new(#777777, 0), text_size=panelSizeDbg, text_halign=text.align_left)
        table.cell(panel, 1, 7, "离底 " + posLText, text_color=color.new(#777777, 0), text_size=panelSizeDbg, text_halign=text.align_right)

        burstText = hadRecentBurst ? "有爆量" : "无爆量"
        burstClr  = hadRecentBurst ? color.new(#E8A030, 0) : color.new(#555555, 0)
        table.cell(panel, 0, 8, "前" + str.tostring(exhaustBack) + "bar", text_color=color.new(#777777, 0), text_size=panelSizeDbg, text_halign=text.align_left)
        table.cell(panel, 1, 8, burstText, text_color=burstClr, text_size=panelSizeDbg, text_halign=text.align_right)

        table.cell(panel, 0, 9, "幅比 " + str.tostring(sprdNorm, "#.##"), text_color=color.new(#777777, 0), text_size=panelSizeDbg, text_halign=text.align_left)
        table.cell(panel, 1, 9, isNarrow ? "窄幅" : "正常幅", text_color=isNarrow ? color.new(#4A90D9, 0) : color.new(#555555, 0), text_size=panelSizeDbg, text_halign=text.align_right)

        // 连续缩量调试
        table.cell(panel, 0, 10, "VR连续", text_color=color.new(#777777, 0), text_size=panelSizeDbg, text_halign=text.align_left)
        table.cell(panel, 1, 10, _clv ? "3根<0.7 禁手!" : "正常", text_color=_clv ? color.new(#E05555, 0) : color.new(#555555, 0), text_size=panelSizeDbg, text_halign=text.align_right)


// ╔═══════════════════════════════════════════════════════════╗
// ║                      报警条件                              ║
// ╚═══════════════════════════════════════════════════════════╝
alertcondition(isSquat,    title="蓄力",      message="🟣 蓄力: 量大但没走出来，可能在憋大招")
alertcondition(isUpthrust, title="假突破",   message="🔴 假突破: 冲高回落，上方有阻力")
alertcondition(isSpring,   title="假跌破",   message="🟢 假跌破: 探底弹回，下方有支撑")
alertcondition(isChurn,    title="拉锯",      message="🟠 拉锯: 多空激烈交战，方向未明")
alertcondition(isExhaust,  title="没劲了",    message="🔵 没劲了: 前面力量耗尽，趋势可能停顿")
alertcondition(isAbnormal, title="任意异常",   message="⚠️ 出现异常量价信号")


// ╔═══════════════════════════════════════════════════════════╗
// ║                        图例                                ║
// ╚═══════════════════════════════════════════════════════════╝
plotshape(false, "■ 正常",             style=shape.square, color=#505050, location=location.bottom)
plotshape(false, "■ 没劲了(动力耗尽)",  style=shape.square, color=#4A90D9, location=location.bottom)
plotshape(false, "■ 蓄力(量大不动)",    style=shape.square, color=#D070D0, location=location.bottom)
plotshape(false, "■ 假突破(冲高被打)", style=shape.square, color=#E05555, location=location.bottom)
plotshape(false, "■ 假跌破(探底弹回)", style=shape.square, color=#50C878, location=location.bottom)
plotshape(false, "■ 拉锯(多空对打)",    style=shape.square, color=#E8A030, location=location.bottom)
