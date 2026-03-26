---
name: news-editor
description: 新闻播报编辑审核工作流。在撰写和发送任何新闻播报前，必须执行此工作流。触发场景：(1) 定时新闻任务（08:00/20:00）发稿前；(2) 用户要求发布新闻；(3) 任何需要发布市场动态资讯之前。核心流程：草稿 → 自检清单 → 修正 → 发送。
---

# News Editor 工作流

## 触发时机

- 定时任务（08:00 / 20:00）发稿前
- 用户要求发布新闻播报
- 任何市场资讯发布前

## ⚠️ 数据源规范（强制）

**只允许使用以下数据源，禁止使用 xueqiu.com：**
- ✅ Tavily Search API（`tavily_search.py`）— 首选，已配置
- ✅ 权威财经媒体：Reuters、CNBC、Kitco、Mining.com、CoinDesk
- ✅ 美联储/央行官网
- ❌ **禁止：xueqiu.com（雪球网）** — 反爬严格，容易 404/403，导致 cron 任务报错

**数据采集优先级：**
1. Tavily Search（`scripts/tavily_search.py`）
2. 直接访问 Reuters/CNBC/Kitco 页面
3. 其他开放财经媒体

**Tavily 调用示例：**
```bash
cd ~/.openclaw/workspace/skills/tavily && python3 scripts/tavily_search.py "关键词" --topic news --max-results 5 --depth basic
```
环境变量 `TAVILY_API_KEY` 已配置在 openclaw config 中，无需手动设置。

## 工作流（3步）

### Step 1: 草稿

使用 Tavily 采集数据后，直接撰写新闻内容，**先不发送**。

### Step 2: 自检清单

读取 `references/checklist.md`，逐项核对草稿：

```
❌ 任何一项不通过 → 修正草稿 → 重新过清单
✅ 全部通过 → 进入 Step 3
```

重点核查：
- 黄金/BTC 必须是**收盘价**，不是盘中价
- 原油要分清 WTI 和 Brent
- 美联储数字要精确
- 所有数据标注来源和时间

### Step 3: 发送

自检通过后：
1. 先发飞书群（ELP16 + 黄金屋）
2. 再发 QQ 邮箱
3. 最后更新 HEARTBEAT.md 状态

---

## 快速自检命令

发稿前在草稿中找到并核对以下关键项：

| 检查项 | 正确格式 | 常见错误 |
|--------|---------|---------|
| 黄金收盘价 | `$4,674.29/oz` | `$4,852`（期货价） |
| BTC价格 | `~$71,000（CoinDesk）` | `$75,000（过时峰值）` |
| 美联储利率 | `3.5%-3.75%` | 写错小数点位 |
| 原油单位 | `美元/桶` | 忘记标注单位 |

---

## 记忆库更新

发稿成功后：
1. 更新 `HEARTBEAT.md` 当日状态
2. 如有错误被用户纠正 → 记录到 `MEMORY.md` 作为案例
