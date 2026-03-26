# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## What Goes Here

Things like:

- Camera names and locations
- SSH hosts and aliases
- Preferred voices for TTS
- Speaker/room names
- Device nicknames
- Anything environment-specific

## Examples

```markdown
### Cameras

- living-room → Main area, 180° wide angle
- front-door → Entrance, motion-triggered

### SSH

- home-server → 192.168.1.100, user: admin

### TTS

- Preferred voice: "Nova" (warm, slightly British)
- Default speaker: Kitchen HomePod
```

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

Add whatever helps you do your job. This is your cheat sheet.

## 🔒 安全规则 - GitHub/公开仓库上传（红线）

**绝对禁止上传的内容（一经发现立即删除）：**
- ❌ **私钥、密钥** — SSH私钥、API Secret、任何private key
- ❌ **账号密码** — 各种登录密码、授权码
- ❌ **真实身份信息** — 姓名、地址、电话、身份证号等
- ❌ **具体资金细节** — 持仓金额、账户余额、银行卡号
- ❌ **API Token** — GitHub Token、飞书 App Secret、邮箱授权码等

**可以上传的内容：**
- ✅ 交易笔记中的价格数字（如黄金底线 $5,278）
- ✅ 一般性的市场分析、摘要
- ✅ 昵称、代号（如 HoneyRay、Jassica）

**每次上传前强制检查：**
1. 扫描文件内容，搜索关键词：`token`、`secret`、`password`、`key`、`auth`
2. 确认没有16位以上的随机字符串（可能是密钥）
3. 确认没有邮箱授权码格式的字符串

**违规后果：** 如果误传敏感信息，立即撤销Token/更换密码，并从GitHub history中彻底删除。
