# Himalaya 邮件配置指南

## 快速配置步骤

### 1. 运行配置向导
```bash
himalaya account configure
```

### 2. 或使用配置文件
创建文件: `~/.config/himalaya/config.toml`

```toml
[accounts.default]
email = "your-email@gmail.com"

[accounts.default.imap]
host = "imap.gmail.com"
port = 993
login = "your-email@gmail.com"
# 对于Gmail，需要应用专用密码: https://myaccount.google.com/apppasswords
passwd.command = "echo 'your-app-password'"

[accounts.default.smtp]
host = "smtp.gmail.com"
port = 465
login = "your-email@gmail.com"
passwd.command = "echo 'your-app-password'"
```

### 3. 常用邮箱IMAP/SMTP设置

**Gmail:**
- IMAP: imap.gmail.com:993
- SMTP: smtp.gmail.com:465
- 密码: 需要应用专用密码

**Outlook/Hotmail:**
- IMAP: outlook.office365.com:993
- SMTP: smtp.office365.com:587

**QQ邮箱:**
- IMAP: imap.qq.com:993
- SMTP: smtp.qq.com:465

### 4. 测试命令
```bash
# 查看邮件列表
himalaya

# 查看文件夹
himalaya folder list

# 读取邮件
himalaya message read 1

# 搜索邮件
himalaya envelope search "subject:交易"
```

---

# Notion API 配置指南

## 步骤 1: 创建 Notion Integration

1. 访问: https://www.notion.so/my-integrations
2. 点击 "New integration"
3. 填写:
   - Name: "Jassica Memory"
   - Associated workspace: 选择你的工作区
4. 点击 "Submit"
5. 复制 "Internal Integration Token" (以 `secret_` 开头)

## 步骤 2: 设置环境变量

```bash
# 临时设置 (当前会话)
export NOTION_API_KEY="secret_xxxxxxxxxx"

# 永久设置 (添加到 ~/.bashrc)
echo 'export NOTION_API_KEY="secret_xxxxxxxxxx"' >> ~/.bashrc
source ~/.bashrc
```

## 步骤 3: 创建数据库页面

1. 在Notion中创建一个新页面
2. 点击 "Share" → "Add connections"
3. 选择你创建的 "Jassica Memory" integration
4. 复制页面URL中的database ID

## 步骤 4: 测试

```bash
# 验证配置
openclaw skills info notion

# 应该显示: Environment: ✓ NOTION_API_KEY
```

---

## 安全提醒 ⚠️

1. **不要把API Key提交到GitHub!**
2. 使用 `.env` 文件或环境变量存储密钥
3. Gmail需要使用"应用专用密码"，不是登录密码

## 需要帮助?

告诉我你使用哪个邮箱(Gmail/Outlook/QQ)，我帮你生成具体的配置文件！
