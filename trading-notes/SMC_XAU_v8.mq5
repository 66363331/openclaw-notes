// This source code is subject to the terms of the Mozilla Public License 2.0 at https://mozilla.org/MPL/2.0/
// XAU SMC v8 — EQH/EQL流动性池 · PDH/PDL关键水平线
// 基于 v7.1 · Sweep过滤修复 · 触及计数修复 · 配色同步
// © Gemini_Refined / 优化 Claude

//@version=6
indicator("SMC XAU v8", shorttitle="SMC v8", overlay=true, max_labels_count=500, max_boxes_count=500, max_lines_count=500, max_bars_back=1000)

//=============================================================================
//  ① 核心
//=============================================================================
T_MODE = "【参数档位】\n" +
 "精选信号: H1:SL18/BW2.5(PF2.47) M15:SL28/BW1.5(PF2.81) M3:SL18/BW1.5(PF2.44)\n" +
 "密集标记: H1:SL14/BW1.5(PF1.95) M15:SL14/BW2.5(PF2.40) M3:SL14/BW1.5(PF2.44)\n" +
 "宽区引导: H1:SL18/BW4.0(PF1.90) M15/M3同精选"

param_mode = input.string("密集标记", title="参数档位", options=["精选信号","密集标记","宽区引导","手动"], group="① 核心", tooltip=T_MODE)

T_OBSL = "【结构摆动长度】值越大→zone越少越可靠，值越小→zone越多噪音也多"
manual_ob_sl = input.int(14, '结构摆动长度 (手动)', group='① 核心', minval=1, maxval=50, tooltip=T_OBSL)

T_BW = "【供需区宽度】= ATR(20)×(此值÷10)\n回测: H1 BW2.5→PF2.47 vs BW6→PF1.38"
manual_bw = input.float(1.5, '供需区宽度 (手动)', group='① 核心', minval=0.5, maxval=10, step=0.5, tooltip=T_BW)

manual_hist = input.int(15, '历史保留数 (手动)', group='① 核心', minval=5, maxval=50, tooltip='超过15后对结果几乎无影响')

tf_sec = timeframe.in_seconds()

f_ob_sl() =>
    _m = param_mode
    if _m == "精选信号"
        tf_sec>=2592000?3:tf_sec>=604800?3:tf_sec>=86400?10:tf_sec>=14400?5:tf_sec>=3600?18:tf_sec>=900?28:tf_sec>=180?18:tf_sec>=60?14:10
    else if _m == "密集标记"
        tf_sec>=2592000?3:tf_sec>=604800?3:tf_sec>=86400?7:tf_sec>=14400?5:tf_sec>=3600?14:tf_sec>=900?14:tf_sec>=180?14:tf_sec>=60?10:10
    else if _m == "宽区引导"
        tf_sec>=2592000?3:tf_sec>=604800?3:tf_sec>=86400?10:tf_sec>=14400?5:tf_sec>=3600?18:tf_sec>=900?28:tf_sec>=180?18:tf_sec>=60?14:10
    else
        manual_ob_sl

f_bw() =>
    _m = param_mode
    if _m == "精选信号"
        tf_sec>=604800?1.5:tf_sec>=86400?1.5:tf_sec>=14400?1.5:tf_sec>=3600?2.5:tf_sec>=900?1.5:tf_sec>=180?1.5:tf_sec>=60?1.5:2.5
    else if _m == "密集标记"
        tf_sec>=604800?1.5:tf_sec>=86400?1.5:tf_sec>=14400?1.5:tf_sec>=3600?1.5:tf_sec>=900?2.5:tf_sec>=180?1.5:tf_sec>=60?1.5:2.5
    else if _m == "宽区引导"
        tf_sec>=604800?1.5:tf_sec>=86400?1.5:tf_sec>=14400?1.5:tf_sec>=3600?4.0:tf_sec>=900?1.5:tf_sec>=180?1.5:tf_sec>=60?1.5:2.5
    else
        manual_bw

f_hist() => param_mode=="手动"?manual_hist:(tf_sec>=604800?8:15)

swing_length              = f_ob_sl()
box_width                 = f_bw()
history_of_demand_to_keep = f_hist()

//=============================================================================
//  ② CHoCH
//=============================================================================
T_CHOCH = "【CHoCH】趋势转折预警，不是入场信号，需配合zone确认"
show_choch = input.bool(true, '显示 CHoCH', group='② CHoCH', tooltip=T_CHOCH)
manual_choch_sl = input.int(10, '转折摆动长度 (手动)', group='② CHoCH', minval=1, maxval=50, tooltip='独立于OB，回测最优7~10')
manual_choch_len = input.int(5, 'CHoCH 线段长度', group='② CHoCH', minval=1, maxval=100)
choch_line_type = input.string("实线", title="CHoCH 线型", options=["实线","虚线","点线","隐藏"], group='② CHoCH')
choch_show_label = input.bool(false, '显示 CHoCH 文字', group='② CHoCH')
choch_label_text = input.string("CHoCH", 'CHoCH 标签内容', group='② CHoCH')
choch_label_size = input.string("Tiny", options=["Tiny","Small","Normal"], title="文字大小", group='② CHoCH')
choch_bull_color = input.color(color.new(#FFD740,20), '多头', group='② CHoCH', inline='c1')
choch_bear_color = input.color(color.new(#FFD740,20), '空头', group='② CHoCH', inline='c1')

f_choch_sl() =>
    _m = param_mode
    if _m=="手动"
        manual_choch_sl
    else if _m=="密集标记"
        tf_sec>=86400?5:tf_sec>=14400?5:tf_sec>=3600?7:tf_sec>=900?7:tf_sec>=180?5:tf_sec>=60?5:7
    else
        tf_sec>=86400?7:tf_sec>=14400?7:tf_sec>=3600?10:tf_sec>=900?10:tf_sec>=180?7:tf_sec>=60?5:10

f_choch_len() => param_mode=="手动"?manual_choch_len:tf_sec>=86400?20:tf_sec>=14400?15:tf_sec>=3600?12:tf_sec>=900?10:tf_sec>=180?8:tf_sec>=60?6:10

choch_swing_length = f_choch_sl()
choch_line_length = f_choch_len()

f_lstyle(s) => s=="实线"?line.style_solid:s=="虚线"?line.style_dashed:s=="点线"?line.style_dotted:line.style_dotted
choch_style = f_lstyle(choch_line_type)
choch_vis = choch_line_type!="隐藏"

//=============================================================================
//  ③ BOS
//=============================================================================
T_BOS = "【BOS】结构突破确认趋势延续，方向与持仓相反=考虑停手"
bos_line_type = input.string("实线", title="BOS 线型", options=["实线","虚线","点线","隐藏"], group='③ BOS', tooltip=T_BOS)
bos_show_label = input.bool(false, '显示 BOS 文字', group='③ BOS')
bos_label_text = input.string("BOS", 'BOS 标签内容', group='③ BOS')
bos_line_color = input.color(color.new(#FFD740,50), 'BOS 线条', group='③ BOS', inline='b1')
bos_label_col = input.color(color.new(#FFD740,20), 'BOS 文字', group='③ BOS', inline='b1')

bos_style = f_lstyle(bos_line_type)
bos_visible = bos_line_type!="隐藏"

//=============================================================================
//  ④ FVG
//=============================================================================
T_FVG = "【FVG】三根K线间价格缺口，与zone重叠=高概率位"
show_fvg = input.bool(true, '显示 FVG', group='④ FVG', tooltip=T_FVG)
fvg_gap_atr = input.float(0.3, '最小缺口 (ATR倍)', group='④ FVG', minval=0, maxval=2, step=0.1, tooltip='0.3→反弹率55%  0.5→65%信号减半')
fvg_body_ratio = input.float(0.5, '最小实体比', group='④ FVG', minval=0, maxval=1, step=0.1)
fvg_max_age = input.int(50, '最大存活K线数', group='④ FVG', minval=10, maxval=200)
fvg_max_show = input.int(10, '最大显示数量', group='④ FVG', minval=1, maxval=30)
fvg_mitigate = input.bool(true, '已填补自动隐藏', group='④ FVG')
fvg_bull_color = input.color(color.new(#004D40,85), '多头 FVG', group='④ FVG', inline='f1')
fvg_bear_color = input.color(color.new(#B71C1C,85), '空头 FVG', group='④ FVG', inline='f1')

//=============================================================================
//  ⑤ Zone质量
//=============================================================================
T_TOUCH = "【触及计数】zone被价格碰几次\n" +
 "显示方式: zone右上角出现 ①②③ 数字标签\n" +
 "①首次触及=最佳首仓 ②第二次=谨慎 ③以上=不建议入场\n" +
 "计数规则: 价格进入zone后离开，算一次触及"
show_touch_count = input.bool(true, '显示触及次数', group='⑤ Zone质量', tooltip=T_TOUCH)
touch_fade_at = input.int(3, '淡化触及次数', group='⑤ Zone质量', minval=2, maxval=5, tooltip='达到此次数后zone变灰=不再可靠')

T_SWEEP = "【流动性扫取】仅在供需区内部显示\n" +
 "◆标记=影线刺穿Swing点后收回（机构扫止损）\n" +
 "zone内◆ + 威科夫假突破 = S级入场信号"
show_sweep = input.bool(true, '显示流动性扫取', group='⑤ Zone质量', tooltip=T_SWEEP)
sweep_color = input.color(color.new(#FFD740,20), '扫取标记颜色', group='⑤ Zone质量')
sweep_cooldown = input.int(5, '扫取冷却K线数', group='⑤ Zone质量', minval=1, maxval=20, tooltip='同一区域连续触发时，两个标记之间最少间隔几根K线')

T_CONF = "【共振高亮】FVG与zone重叠时边框变金色=最高概率位"
show_confluence = input.bool(true, '显示共振高亮', group='⑤ Zone质量', tooltip=T_CONF)
confluence_color = input.color(color.new(#FFD740,40), '共振边框颜色', group='⑤ Zone质量')

//=============================================================================
//  ⑥ 外观 (默认配色匹配用户截图)
//=============================================================================
show_pa_labels = input.bool(true, '显示 HH/HL/LH/LL', group='⑥ 外观', tooltip='HH+HL=多头  LH+LL=空头')
show_zigzag = input.bool(false, '显示 ZigZag', group='⑥ 外观')
show_param_table = input.bool(false, '显示参数表', group='⑥ 外观')

supply_color = input.color(color.new(#B71C1C,82), '供给区填充', group='⑥ 外观', inline='s1')
supply_outline_color = input.color(color.new(#B71C1C,88), '边框', group='⑥ 外观', inline='s1')
demand_color = input.color(color.new(#004D40,78), '需求区填充', group='⑥ 外观', inline='d1')
demand_outline_color = input.color(color.new(#004D40,88), '边框', group='⑥ 外观', inline='d1')
pa_label_color = input.color(color.new(color.white,40), 'PA标签', group='⑥ 外观')
zone_text_col = input.color(color.new(color.white,88), '区域文字', group='⑥ 外观')
poi_show = input.bool(false, '显示 POI 中线', group='⑥ 外观', tooltip='供需区中点价格线')
poi_color = input.color(color.new(color.white,90), 'POI 颜色', group='⑥ 外观')
poi_label_col = input.color(color.new(color.white,70), 'POI 文字', group='⑥ 外观')
zigzag_color = input.color(color.new(color.white,75), 'ZigZag', group='⑥ 外观')

//=============================================================================
//  ⑦ EQH/EQL（等高/等低 — 流动性池预标记）
//=============================================================================
T_EQL = "【等高/等低】两个相近价位的Swing High或Low = 流动性池\n" +
 "上方堆满空头止损，下方堆满多头止损\n" +
 "机构最喜欢扫这种位置后反转\n" +
 "与 Sweep◆ 形成前后呼应：EQH/EQL是预判，◆是确认"
show_eqhl = input.bool(true, '显示 EQH/EQL', group='⑦ EQH/EQL', tooltip=T_EQL)
eqhl_threshold = input.float(0.25, '相似度阈值 (ATR倍)', group='⑦ EQH/EQL', minval=0.05, maxval=1.0, step=0.05,
     tooltip='两个Swing高/低点价差 < ATR(20)×此值 = 等高/等低\n' +
     'M15回测最优0.25(≈$3) 扫率16%+安全率17%\n越小越严格信号越少')
eqhl_line_type = input.string("点线", title="连线线型", options=["实线","虚线","点线"], group='⑦ EQH/EQL')
eqhl_label_size = input.string("Tiny", options=["Tiny","Small","Normal"], title="文字大小", group='⑦ EQH/EQL')
eqhl_bull_color = input.color(color.new(#00E676,30), 'EQL 颜色(多头流动性)', group='⑦ EQH/EQL', inline='eq1',
     tooltip='等低=下方多头止损池，被扫后可能反弹')
eqhl_bear_color = input.color(color.new(#EF5350,30), 'EQH 颜色(空头流动性)', group='⑦ EQH/EQL', inline='eq1',
     tooltip='等高=上方空头止损池，被扫后可能回落')

eqhl_style = f_lstyle(eqhl_line_type)

//=============================================================================
//  ⑧ PDH/PDL（前日/前周高低水平线）
//=============================================================================
T_PDL = "【PDH/PDL/PWH/PWL】前一日/前一周的最高价和最低价\n" +
 "日内最重要的流动性参考位\n" +
 "早盘扫 PDH 或 PDL 后反转是黄金的经典套路\n" +
 "注意：只在低于对应周期的图表上显示（M15看不到前周线需切H1）"
show_pdhl = input.bool(true, '显示 PDH/PDL (前日高低)', group='⑧ PDH/PDL', tooltip=T_PDL)
pdhl_style_str = input.string("虚线", title="PDH/PDL 线型", options=["实线","虚线","点线"], group='⑧ PDH/PDL')
pdhl_color = input.color(color.new(#2196F3,30), 'PDH/PDL 颜色', group='⑧ PDH/PDL')
show_pwhl = input.bool(false, '显示 PWH/PWL (前周高低)', group='⑧ PDH/PDL',
     tooltip='前周高低线，适合H1/H4周期观察\n日内M15/M3上默认关闭避免遮挡')
pwhl_style_str = input.string("实线", title="PWH/PWL 线型", options=["实线","虚线","点线"], group='⑧ PDH/PDL')
pwhl_color = input.color(color.new(#FF9800,30), 'PWH/PWL 颜色', group='⑧ PDH/PDL')
pdhl_left_bars = input.int(50, 'PDH/PDL 左延伸K线数', group='⑧ PDH/PDL', minval=10, maxval=500, step=10,
     tooltip='线条向左延伸多少根K线\nM15默认50根≈12小时，够看当天行情\n觉得短可以加大')
pwhl_left_bars = input.int(100, 'PWH/PWL 左延伸K线数', group='⑧ PDH/PDL', minval=10, maxval=1000, step=10,
     tooltip='线条向左延伸多少根K线\nH1默认100根≈4天，覆盖本周行情')

pdhl_style = f_lstyle(pdhl_style_str)
pwhl_style = f_lstyle(pwhl_style_str)

//=============================================================================
//  参数表（默认关闭，匹配用户设置）
//=============================================================================
var table ptbl = na
if show_param_table and barstate.islast
    if na(ptbl)
        ptbl := table.new(position.top_right,2,8,bgcolor=color.new(#131722,5),border_color=color.new(#363A45,60),border_width=1)
    _tf = tf_sec>=2592000?"MN":tf_sec>=604800?"W1":tf_sec>=86400?"D1":tf_sec>=14400?"H4":tf_sec>=3600?"H1":tf_sec>=900?"M15":tf_sec>=180?"M3":"M1"
    _ms = param_mode=="精选信号"?"精选":param_mode=="密集标记"?"密集":param_mode=="宽区引导"?"宽区":"手动"
    table.cell(ptbl,0,0,"档位",text_color=#787B86,text_size=size.tiny,text_halign=text.align_left)
    table.cell(ptbl,1,0,_ms+" "+_tf,text_color=#00E676,text_size=size.tiny,text_halign=text.align_right)
    _n = array.from("OB摆动","CHoCH","区宽","历史","ATR(20)","FVG","PF参考")
    _pf = param_mode=="精选信号"?(tf_sec>=3600 and tf_sec<14400?"2.47":tf_sec>=900 and tf_sec<3600?"2.81":tf_sec>=180 and tf_sec<900?"2.44":"-"):param_mode=="密集标记"?(tf_sec>=3600 and tf_sec<14400?"1.95":tf_sec>=900 and tf_sec<3600?"2.40":tf_sec>=180 and tf_sec<900?"2.44":"-"):param_mode=="宽区引导"?(tf_sec>=3600 and tf_sec<14400?"1.90":tf_sec>=900 and tf_sec<3600?"2.81":tf_sec>=180 and tf_sec<900?"2.44":"-"):"-"
    _v = array.from(str.tostring(swing_length),str.tostring(choch_swing_length),str.tostring(box_width,'#.#'),str.tostring(history_of_demand_to_keep),str.tostring(ta.atr(20),'#.##'),">"+str.tostring(fvg_gap_atr,'#.#'),_pf)
    for i=0 to 6
        table.cell(ptbl,0,i+1,array.get(_n,i),text_color=#787B86,text_size=size.tiny,text_halign=text.align_left)
        table.cell(ptbl,1,i+1,array.get(_v,i),text_color=i==6?#FFD740:#00B8D4,text_size=size.tiny,text_halign=text.align_right)
else if not show_param_table and not na(ptbl)
    table.delete(ptbl)
    ptbl := na

//=============================================================================
//  核心函数
//=============================================================================
f_pop_push(arr,val) =>
    array.unshift(arr,val)
    array.pop(arr)

f_lsz(s) => s=="Tiny"?size.tiny:s=="Small"?size.small:size.normal

f_pa_labels(arr,tp) =>
    var string t = na
    if tp==1
        t := array.get(arr,0)>=array.get(arr,1)?'HH':'LH'
        label.new(bar_index-swing_length,array.get(arr,0),t,style=label.style_label_down,textcolor=pa_label_color,color=color.new(pa_label_color,100),size=size.tiny)
    else if tp==-1
        t := array.get(arr,0)>=array.get(arr,1)?'HL':'LL'
        label.new(bar_index-swing_length,array.get(arr,0),t,style=label.style_label_up,textcolor=pa_label_color,color=color.new(pa_label_color,100),size=size.tiny)

f_overlap(pv,ba,av) =>
    ok=true
    if array.size(ba)>0
        for i=0 to array.size(ba)-1
            b=array.get(ba,i)
            if not na(b)
                mid=(box.get_top(b)+box.get_bottom(b))/2
                if pv>=mid-av*2 and pv<=mid+av*2
                    ok:=false
                    break
    ok

//=============================================================================
//  OB + 触及计数（修复版）
//=============================================================================
atr = ta.atr(20)
sh_pivot = ta.pivothigh(high,swing_length,swing_length)
sl_pivot = ta.pivotlow(low,swing_length,swing_length)

var shv=array.new_float(5,0.0),var slv=array.new_float(5,0.0)
var shb=array.new_int(5,0),var slb=array.new_int(5,0)

var csb=array.new_box(history_of_demand_to_keep,na)
var cdb=array.new_box(history_of_demand_to_keep,na)
var csp=array.new_box(history_of_demand_to_keep,na)
var cdp=array.new_box(history_of_demand_to_keep,na)
var sbs=array.new_box(3,na),var dbs=array.new_box(3,na)

// 触及计数 + 状态跟踪（修复：用 was_inside 防止每根K线重复计数）
var s_touch = array.new_int(history_of_demand_to_keep,0)
var d_touch = array.new_int(history_of_demand_to_keep,0)
var s_inside = array.new_bool(history_of_demand_to_keep,false) // 上一根K线是否在zone内
var d_inside = array.new_bool(history_of_demand_to_keep,false)

// 触及标签数组（用独立label显示数字，不依赖zone文字颜色）
var s_touch_lbl = array.new_label(history_of_demand_to_keep,na)
var d_touch_lbl = array.new_label(history_of_demand_to_keep,na)

f_sd(val_arr,bn_arr,box_arr,lbl_arr,touch_arr,inside_arr,touch_lbl_arr,tp,atr_val) =>
    buf = atr_val*(box_width/10)
    bl = array.get(bn_arr,0)
    br = bar_index
    var float bt=0.0,var float bb=0.0,var float pm=0.0
    if tp==1
        bt := array.get(val_arr,0)
        bb := bt-buf
        pm := (bt+bb)/2
    else
        bb := array.get(val_arr,0)
        bt := bb+buf
        pm := (bt+bb)/2
    if f_overlap(pm,box_arr,atr_val)
        box.delete(array.get(box_arr,array.size(box_arr)-1))
        _bg = tp==1?supply_color:demand_color
        _bdr = tp==1?supply_outline_color:demand_outline_color
        _txt = tp==1?'SUPPLY':'DEMAND'
        f_pop_push(box_arr,box.new(bl,bt,br,bb,border_color=_bdr,bgcolor=_bg,extend=extend.right,text=_txt,text_halign=text.align_center,text_valign=text.align_center,text_color=zone_text_col,text_size=size.small,xloc=xloc.bar_index))
        box.delete(array.get(lbl_arr,array.size(lbl_arr)-1))
        _pc = poi_show?poi_color:color.new(color.white,100)
        f_pop_push(lbl_arr,box.new(bl,pm,br,pm,border_color=_pc,bgcolor=_pc,extend=extend.right,text='POI',text_halign=text.align_left,text_valign=text.align_center,text_color=poi_label_col,text_size=size.small,xloc=xloc.bar_index))
        // 触及计数归零
        array.pop(touch_arr)
        array.unshift(touch_arr,0)
        array.pop(inside_arr)
        array.unshift(inside_arr,false)
        // 清理旧label
        _old_lbl = array.get(touch_lbl_arr,array.size(touch_lbl_arr)-1)
        if not na(_old_lbl)
            label.delete(_old_lbl)
        array.pop(touch_lbl_arr)
        array.unshift(touch_lbl_arr,na)

if not na(sh_pivot)
    f_pop_push(shv,sh_pivot)
    f_pop_push(shb,bar_index[swing_length])
    if show_pa_labels
        f_pa_labels(shv,1)
    f_sd(shv,shb,csb,csp,s_touch,s_inside,s_touch_lbl,1,atr)
else if not na(sl_pivot)
    f_pop_push(slv,sl_pivot)
    f_pop_push(slb,bar_index[swing_length])
    if show_pa_labels
        f_pa_labels(slv,-1)
    f_sd(slv,slb,cdb,cdp,d_touch,d_inside,d_touch_lbl,-1,atr)

// ─── EQH/EQL 等高/等低检测 ───
// 当新 swing 出现时，与前一个同方向 swing 比较价差
// 价差 < threshold × ATR → 标记 EQH 或 EQL
bool eqh_detected = false
bool eql_detected = false

if show_eqhl and not na(atr) and atr > 0
    _eqhl_sz = f_lsz(eqhl_label_size)
    _eqhl_thresh = eqhl_threshold * atr
    // EQH: 新 swing high 与前一个 swing high 价差很小
    if not na(sh_pivot) and array.get(shv,1) > 0
        _diff_h = math.abs(array.get(shv,0) - array.get(shv,1))
        if _diff_h <= _eqhl_thresh and _diff_h > 0
            eqh_detected := true
            _eqh_price = math.avg(array.get(shv,0), array.get(shv,1))
            _eqh_left = array.get(shb,1)
            _eqh_right = array.get(shb,0)
            line.new(_eqh_left, array.get(shv,1), _eqh_right, array.get(shv,0), xloc.bar_index, color=eqhl_bear_color, style=eqhl_style, width=1)
            _eqh_mid = math.round((_eqh_left + _eqh_right) / 2)
            label.new(_eqh_mid, _eqh_price, "EQH", xloc.bar_index, color=color.new(color.white,100), textcolor=eqhl_bear_color, style=label.style_label_down, size=_eqhl_sz,
                 tooltip="等高 EQH: " + str.tostring(array.get(shv,1),'#.##') + " ≈ " + str.tostring(array.get(shv,0),'#.##') +
                 "\n价差仅 " + str.tostring(_diff_h,'#.#') + " 美元" +
                 "\n\n上方堆满空头止损单 = 流动性池" +
                 "\n机构可能拉上去扫一遍后反转下杀" +
                 "\n做空止损别卡在EQH上方一点点，要留更宽")
    // EQL: 新 swing low 与前一个 swing low 价差很小
    if not na(sl_pivot) and array.get(slv,1) > 0
        _diff_l = math.abs(array.get(slv,0) - array.get(slv,1))
        if _diff_l <= _eqhl_thresh and _diff_l > 0
            eql_detected := true
            _eql_price = math.avg(array.get(slv,0), array.get(slv,1))
            _eql_left = array.get(slb,1)
            _eql_right = array.get(slb,0)
            line.new(_eql_left, array.get(slv,1), _eql_right, array.get(slv,0), xloc.bar_index, color=eqhl_bull_color, style=eqhl_style, width=1)
            _eql_mid = math.round((_eql_left + _eql_right) / 2)
            label.new(_eql_mid, _eql_price, "EQL", xloc.bar_index, color=color.new(color.white,100), textcolor=eqhl_bull_color, style=label.style_label_up, size=_eqhl_sz,
                 tooltip="等低 EQL: " + str.tostring(array.get(slv,1),'#.##') + " ≈ " + str.tostring(array.get(slv,0),'#.##') +
                 "\n价差仅 " + str.tostring(_diff_l,'#.#') + " 美元" +
                 "\n\n下方堆满多头止损单 = 流动性池" +
                 "\n机构可能砸下去扫一遍后反转拉升" +
                 "\n做多回调等EQL被扫后再进，成功率更高")

// ─── 触及检测（修复版：只在"从外部进入zone"时计数一次）───
f_touch_update(box_arr,touch_arr,inside_arr,touch_lbl_arr,is_supply) =>
    hit_zone = false
    if array.size(box_arr)>0
        for i=0 to array.size(box_arr)-1
            b = array.get(box_arr,i)
            if not na(b)
                zt = box.get_top(b)
                zb = box.get_bottom(b)
                tc = array.get(touch_arr,i)
                was_in = array.get(inside_arr,i)
                
                // 当前K线是否在zone内
                is_in = false
                if is_supply
                    is_in := high >= zb and low <= zt // 价格区间与zone重叠
                else
                    is_in := low <= zt and high >= zb
                if is_in
                    hit_zone := true
                
                // 从外面进来 = 一次新的触及
                if is_in and not was_in and tc < 10
                    tc += 1
                    array.set(touch_arr,i,tc)
                    
                    // 更新label（独立标签，不依赖zone文字颜色）
                    if show_touch_count
                        _old = array.get(touch_lbl_arr,i)
                        if not na(_old)
                            label.delete(_old)
                        _num = tc==1?'①':tc==2?'②':tc==3?'③':tc==4?'④':'⑤+'
                        _lbl_color = tc==1?color.new(#00E676,30):tc==2?color.new(#FFD740,30):color.new(#EF5350,30)
                        _y = is_supply ? zt : zb
                        _sty = is_supply ? label.style_label_down : label.style_label_up
                        _new_lbl = label.new(bar_index, _y, _num, color=color.new(color.white,100), textcolor=_lbl_color, style=_sty, size=size.small)
                        array.set(touch_lbl_arr,i,_new_lbl)
                    
                    // 淡化处理
                    if tc >= touch_fade_at
                        box.set_bgcolor(b,color.new(#363A45,92))
                        box.set_border_color(b,color.new(#363A45,95))
                        box.set_text_color(b,color.new(color.white,95))
                
                array.set(inside_arr,i,is_in)
    hit_zone

bool hit_supply_zone = f_touch_update(csb,s_touch,s_inside,s_touch_lbl,true)
bool hit_demand_zone = f_touch_update(cdb,d_touch,d_inside,d_touch_lbl,false)

// ─── BOS（修复版：box.new替代box.copy，消除历史偏移溢出）───
f_bos(box_arr,bos_arr,lbl_arr,touch_arr,inside_arr,touch_lbl_arr,zt) =>
    for i=0 to array.size(box_arr)-1
        b = array.get(box_arr,i)
        if not na(b)
            lv = zt==1?box.get_top(b):box.get_bottom(b)
            hit = zt==1?close>=lv:close<=lv
            if hit
                if bos_visible
                    mid=(box.get_top(b)+box.get_bottom(b))/2
                    _bt = bos_show_label?bos_label_text:''
                    _bos_left = math.max(box.get_left(b), bar_index - 500)
                    _new_bos = box.new(_bos_left, mid, bar_index, mid, border_color=bos_line_color, bgcolor=bos_line_color, border_style=bos_style, extend=extend.none, text=_bt, text_color=bos_label_col, text_size=size.small, text_halign=text.align_center, text_valign=text.align_center, xloc=xloc.bar_index)
                    f_pop_push(bos_arr,_new_bos)
                box.delete(array.get(box_arr,i))
                box.delete(array.get(lbl_arr,i))
                // 清理触及label
                _tl = array.get(touch_lbl_arr,i)
                if not na(_tl)
                    label.delete(_tl)
                array.set(touch_arr,i,0)
                array.set(inside_arr,i,false)
                array.set(touch_lbl_arr,i,na)

f_bos(csb,sbs,csp,s_touch,s_inside,s_touch_lbl,1)
f_bos(cdb,dbs,cdp,d_touch,d_inside,d_touch_lbl,-1)

f_extend(ba) =>
    _right_target = bar_index+50
    for i=0 to array.size(ba)-1
        b = array.get(ba,i)
        if not na(b)
            if box.get_right(b) != _right_target
                box.set_right(b,_right_target)
f_extend(csb)
f_extend(cdb)

//=============================================================================
//  CHoCH（独立摆动）
//=============================================================================
c_sh = ta.pivothigh(high,choch_swing_length,choch_swing_length)
c_sl = ta.pivotlow(low,choch_swing_length,choch_swing_length)

var float lc_sh=na,var float lc_sl=na
if not na(c_sh)
    lc_sh := c_sh
if not na(c_sl)
    lc_sl := c_sl

_csz = f_lsz(choch_label_size)
bool cb_bull=false,bool cb_bear=false

if show_choch and choch_vis
    if not na(lc_sh) and ta.crossover(close,lc_sh)
        cb_bull:=true
        line.new(bar_index,lc_sh,bar_index-choch_line_length,lc_sh,color=choch_bull_color,style=choch_style,width=1)
        if choch_show_label and str.length(choch_label_text)>0
            label.new(bar_index,lc_sh,choch_label_text,color=color.new(color.white,100),textcolor=choch_bull_color,style=label.style_label_down,size=_csz)
        lc_sh:=na
    if not na(lc_sl) and ta.crossunder(close,lc_sl)
        cb_bear:=true
        line.new(bar_index,lc_sl,bar_index-choch_line_length,lc_sl,color=choch_bear_color,style=choch_style,width=1)
        if choch_show_label and str.length(choch_label_text)>0
            label.new(bar_index,lc_sl,choch_label_text,color=color.new(color.white,100),textcolor=choch_bear_color,style=label.style_label_up,size=_csz)
        lc_sl:=na

//=============================================================================
//  流动性扫取（修复版：仅zone内 + 冷却期 + ◆标记）
//=============================================================================
var float[] recent_sh = array.new_float(10,na)
var float[] recent_sl = array.new_float(10,na)

if not na(sh_pivot)
    array.unshift(recent_sh,sh_pivot)
    if array.size(recent_sh)>10
        array.pop(recent_sh)
if not na(sl_pivot)
    array.unshift(recent_sl,sl_pivot)
    if array.size(recent_sl)>10
        array.pop(recent_sl)

// 冷却计数器
var int last_sweep_bar = 0

// 辅助函数：检查价格是否在任何活跃zone内
f_in_any_zone(price_high, price_low, box_arr) =>
    in_zone = false
    if array.size(box_arr) > 0
        for i = 0 to array.size(box_arr)-1
            b = array.get(box_arr,i)
            if not na(b)
                zt = box.get_top(b)
                zb = box.get_bottom(b)
                if price_high >= zb and price_low <= zt
                    in_zone := true
                    break
    in_zone

bool sweep_bull = false
bool sweep_bear = false

if show_sweep and bar_index - last_sweep_bar >= sweep_cooldown
    // Bearish Sweep: 高点刺穿swing high但收盘收回 + 必须在supply zone内
    for i = 0 to math.min(array.size(recent_sh)-1,4)
        sv = array.get(recent_sh,i)
        if not na(sv) and high > sv and close < sv and open < sv
            // 检查是否在供给区内
            if f_in_any_zone(high,low,csb)
                sweep_bear := true
                label.new(bar_index,high,"◆",color=color.new(color.white,100),textcolor=sweep_color,style=label.style_label_down,size=size.small,tooltip="空头扫取: 影线刺穿前高"+str.tostring(sv,'#.##')+"后收回\n前高上方是空头止损区，机构拉上去扫掉空头止损后反转下杀")
                last_sweep_bar := bar_index
                break
    
    // Bullish Sweep: 低点刺穿swing low但收盘收回 + 必须在demand zone内
    if not sweep_bear
        for i = 0 to math.min(array.size(recent_sl)-1,4)
            sv = array.get(recent_sl,i)
            if not na(sv) and low < sv and close > sv and open > sv
                if f_in_any_zone(high,low,cdb)
                    sweep_bull := true
                    label.new(bar_index,low,"◆",color=color.new(color.white,100),textcolor=sweep_color,style=label.style_label_up,size=size.small,tooltip="多头扫取: 影线刺穿前低"+str.tostring(sv,'#.##')+"后收回\n前低下方是多头止损区，机构砸下去扫掉多头止损后反转拉升")
                    last_sweep_bar := bar_index
                    break

//=============================================================================
//  FVG
//=============================================================================
var fvg_bx=array.new_box(0),var fvg_br=array.new_int(0),var fvg_tp=array.new_int(0)
var fvg_top_cache = array.new_float(0),var fvg_bot_cache = array.new_float(0),var fvg_type_cache = array.new_int(0)

if show_fvg and bar_index>2 and not na(atr)
    _bg1=low-high[2]
    if _bg1>0
        _ga=_bg1/atr
        _bd=math.abs(close[1]-open[1])
        _rn=high[1]-low[1]
        _br=_rn>0?_bd/_rn:0
        if _ga>=fvg_gap_atr and _br>=fvg_body_ratio
            array.push(fvg_bx,box.new(bar_index-2,low,bar_index,high[2],border_color=color.new(fvg_bull_color,70),bgcolor=fvg_bull_color,text='FVG',text_color=color.new(color.white,80),text_size=size.tiny,text_halign=text.align_right,text_valign=text.align_center))
            array.push(fvg_br,bar_index)
            array.push(fvg_tp,1)
    _bg2=low[2]-high
    if _bg2>0
        _ga2=_bg2/atr
        _bd2=math.abs(close[1]-open[1])
        _rn2=high[1]-low[1]
        _br2=_rn2>0?_bd2/_rn2:0
        if _ga2>=fvg_gap_atr and _br2>=fvg_body_ratio
            array.push(fvg_bx,box.new(bar_index-2,low[2],bar_index,high,border_color=color.new(fvg_bear_color,70),bgcolor=fvg_bear_color,text='FVG',text_color=color.new(color.white,80),text_size=size.tiny,text_halign=text.align_right,text_valign=text.align_center))
            array.push(fvg_br,bar_index)
            array.push(fvg_tp,-1)

array.clear(fvg_top_cache)
array.clear(fvg_bot_cache)
array.clear(fvg_type_cache)
if show_fvg and array.size(fvg_bx)>0
    i=array.size(fvg_bx)-1
    while i>=0
        b=array.get(fvg_bx,i)
        rm=false
        if not na(b)
            ft=array.get(fvg_tp,i)
            bt=box.get_top(b)
            bb=box.get_bottom(b)
            if bar_index-array.get(fvg_br,i)>fvg_max_age
                rm:=true
            if fvg_mitigate
                if ft==1 and low<=bb
                    rm:=true
                if ft==-1 and high>=bt
                    rm:=true
            if not rm
                box.set_right(b,bar_index)
                array.unshift(fvg_top_cache,bt)
                array.unshift(fvg_bot_cache,bb)
                array.unshift(fvg_type_cache,ft)
        else
            rm:=true
        if rm
            if not na(b)
                box.delete(b)
            array.remove(fvg_bx,i)
            array.remove(fvg_br,i)
            array.remove(fvg_tp,i)
        i-=1
    while array.size(fvg_bx)>fvg_max_show
        ob=array.shift(fvg_bx)
        array.shift(fvg_br)
        array.shift(fvg_tp)
        array.shift(fvg_top_cache)
        array.shift(fvg_bot_cache)
        array.shift(fvg_type_cache)
        if not na(ob)
            box.delete(ob)
//=============================================================================
//  共振高亮
//=============================================================================
if show_confluence and show_fvg and array.size(fvg_top_cache)>0
    for i=0 to array.size(csb)-1
        b=array.get(csb,i)
        if not na(b)
            _tc = array.get(s_touch,i)
            if _tc < touch_fade_at  // 已淡化的zone不参与共振重置
                zt=box.get_top(b)
                zb=box.get_bottom(b)
                has_conf=false
                for j=0 to array.size(fvg_top_cache)-1
                    if zt>=array.get(fvg_bot_cache,j) and zb<=array.get(fvg_top_cache,j)
                        has_conf:=true
                        break
                if has_conf
                    box.set_border_color(b,confluence_color)
                    box.set_border_width(b,2)
                else
                    box.set_border_color(b,supply_outline_color)
                    box.set_border_width(b,1)
    for i=0 to array.size(cdb)-1
        b=array.get(cdb,i)
        if not na(b)
            _tc = array.get(d_touch,i)
            if _tc < touch_fade_at
                zt=box.get_top(b)
                zb=box.get_bottom(b)
                has_conf=false
                for j=0 to array.size(fvg_top_cache)-1
                    if zt>=array.get(fvg_bot_cache,j) and zb<=array.get(fvg_top_cache,j)
                        has_conf:=true
                        break
                if has_conf
                    box.set_border_color(b,confluence_color)
                    box.set_border_width(b,2)
                else
                    box.set_border_color(b,demand_outline_color)
                    box.set_border_width(b,1)

//=============================================================================
//  警报
//=============================================================================
f_alert_zone(ba,is_sup) =>
    hit=false
    for i=0 to array.size(ba)-1
        b=array.get(ba,i)
        if not na(b)
            t=box.get_top(b)
            bt=box.get_bottom(b)
            if is_sup?(high>=bt and low<=t):(low<=t and high>=bt)
                hit:=true
    hit

if hit_supply_zone
    alert("价格触及供给区",alert.freq_once_per_bar)
if hit_demand_zone
    alert("价格触及需求区",alert.freq_once_per_bar)
if cb_bull
    alert("多头CHoCH",alert.freq_once_per_bar)
if cb_bear
    alert("空头CHoCH",alert.freq_once_per_bar)
if sweep_bull
    alert("多头扫取(zone内Sweep)",alert.freq_once_per_bar)
if sweep_bear
    alert("空头扫取(zone内Sweep)",alert.freq_once_per_bar)
if eqh_detected
    alert("等高EQH检测到(流动性池)",alert.freq_once_per_bar)
if eql_detected
    alert("等低EQL检测到(流动性池)",alert.freq_once_per_bar)

if show_fvg and array.size(fvg_top_cache)>0
    for i=0 to array.size(fvg_top_cache)-1
        t=array.get(fvg_top_cache,i)
        bt=array.get(fvg_bot_cache,i)
        ft=array.get(fvg_type_cache,i)
        if ft==1 and low<=t and close>bt
            alert("价格触及多头FVG",alert.freq_once_per_bar)
            break
        if ft==-1 and high>=bt and close<t
            alert("价格触及空头FVG",alert.freq_once_per_bar)
            break
//=============================================================================
//  ZigZag
//=============================================================================
hzz=ta.highest(high,swing_length*2+1)
lzz=ta.lowest(low,swing_length*2+1)
f_isMin(len)=>lzz==low[len]
f_isMax(len)=>hzz==high[len]
var dirUp=false,var lastLow=high*100,var lastHigh=0.0,var timeLow=bar_index,var timeHigh=bar_index,var line li=na
f_drawLine()=>
    _c=show_zigzag?zigzag_color:color.new(#ffffff,100)
    line.new(timeHigh-swing_length,lastHigh,timeLow-swing_length,lastLow,xloc.bar_index,color=_c,width=1)
if dirUp
    if f_isMin(swing_length) and low[swing_length]<lastLow
        lastLow:=low[swing_length]
        timeLow:=bar_index
        line.delete(li)
        li:=f_drawLine()
    if f_isMax(swing_length) and high[swing_length]>lastLow
        lastHigh:=high[swing_length]
        timeHigh:=bar_index
        dirUp:=false
        li:=f_drawLine()
if not dirUp
    if f_isMax(swing_length) and high[swing_length]>lastHigh
        lastHigh:=high[swing_length]
        timeHigh:=bar_index
        line.delete(li)
        li:=f_drawLine()
    if f_isMin(swing_length) and low[swing_length]<lastHigh
        lastLow:=low[swing_length]
        timeLow:=bar_index
        dirUp:=true
        li:=f_drawLine()
        if f_isMax(swing_length) and high[swing_length]>lastLow
            lastHigh:=high[swing_length]
            timeHigh:=bar_index
            dirUp:=false
            li:=f_drawLine()

//=============================================================================
//  PDH/PDL · PWH/PWL（前日/前周高低水平线）
//=============================================================================
// 仅在低于对应周期的图表上绘制
bool is_below_daily = tf_sec < 86400
bool is_below_weekly = tf_sec < 604800

// PDH/PDL
var line pdh_line = na
var line pdl_line = na
var label pdh_label = na
var label pdl_label = na

if show_pdhl and is_below_daily
    [_pdh, _pdl] = request.security(syminfo.tickerid, "D", [high[1], low[1]], lookahead=barmerge.lookahead_on)
    if not na(_pdh) and not na(_pdl)
        _right_bar = bar_index + 30
        if na(pdh_line)
            pdh_line := line.new(bar_index, _pdh, _right_bar, _pdh, xloc.bar_index, color=pdhl_color, style=pdhl_style, width=1)
            pdh_label := label.new(_right_bar, _pdh, "PDH " + str.tostring(_pdh,'#.#'), xloc.bar_index, color=color.new(color.white,100), textcolor=pdhl_color, style=label.style_label_left, size=size.tiny,
                 tooltip="前日最高价 Previous Day High\n" + str.tostring(_pdh,'#.##') + "\n\n日内关键阻力位，价格冲上PDH后回落 = 假突破做空机会")
            pdl_line := line.new(bar_index, _pdl, _right_bar, _pdl, xloc.bar_index, color=pdhl_color, style=pdhl_style, width=1)
            pdl_label := label.new(_right_bar, _pdl, "PDL " + str.tostring(_pdl,'#.#'), xloc.bar_index, color=color.new(color.white,100), textcolor=pdhl_color, style=label.style_label_left, size=size.tiny,
                 tooltip="前日最低价 Previous Day Low\n" + str.tostring(_pdl,'#.##') + "\n\n日内关键支撑位，价格砸破PDL后收回 = 假跌破做多机会")
        else
            line.set_xy1(pdh_line, bar_index - pdhl_left_bars, _pdh)
            line.set_xy2(pdh_line, _right_bar, _pdh)
            label.set_xy(pdh_label, _right_bar, _pdh)
            label.set_text(pdh_label, "PDH " + str.tostring(_pdh,'#.#'))
            line.set_xy1(pdl_line, bar_index - pdhl_left_bars, _pdl)
            line.set_xy2(pdl_line, _right_bar, _pdl)
            label.set_xy(pdl_label, _right_bar, _pdl)
            label.set_text(pdl_label, "PDL " + str.tostring(_pdl,'#.#'))

// PWH/PWL
var line pwh_line = na
var line pwl_line = na
var label pwh_label = na
var label pwl_label = na

if show_pwhl and is_below_weekly
    [_pwh, _pwl] = request.security(syminfo.tickerid, "W", [high[1], low[1]], lookahead=barmerge.lookahead_on)
    if not na(_pwh) and not na(_pwl)
        _right_bar_w = bar_index + 30
        if na(pwh_line)
            pwh_line := line.new(bar_index, _pwh, _right_bar_w, _pwh, xloc.bar_index, color=pwhl_color, style=pwhl_style, width=1)
            pwh_label := label.new(_right_bar_w, _pwh, "PWH " + str.tostring(_pwh,'#.#'), xloc.bar_index, color=color.new(color.white,100), textcolor=pwhl_color, style=label.style_label_left, size=size.tiny,
                 tooltip="前周最高价 Previous Week High\n" + str.tostring(_pwh,'#.##') + "\n\n周级别阻力位")
            pwl_line := line.new(bar_index, _pwl, _right_bar_w, _pwl, xloc.bar_index, color=pwhl_color, style=pwhl_style, width=1)
            pwl_label := label.new(_right_bar_w, _pwl, "PWL " + str.tostring(_pwl,'#.#'), xloc.bar_index, color=color.new(color.white,100), textcolor=pwhl_color, style=label.style_label_left, size=size.tiny,
                 tooltip="前周最低价 Previous Week Low\n" + str.tostring(_pwl,'#.##') + "\n\n周级别支撑位")
        else
            line.set_xy1(pwh_line, bar_index - pwhl_left_bars, _pwh)
            line.set_xy2(pwh_line, _right_bar_w, _pwh)
            label.set_xy(pwh_label, _right_bar_w, _pwh)
            label.set_text(pwh_label, "PWH " + str.tostring(_pwh,'#.#'))
            line.set_xy1(pwl_line, bar_index - pwhl_left_bars, _pwl)
            line.set_xy2(pwl_line, _right_bar_w, _pwl)
            label.set_xy(pwl_label, _right_bar_w, _pwl)
            label.set_text(pwl_label, "PWL " + str.tostring(_pwl,'#.#'))
