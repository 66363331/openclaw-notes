#!/bin/bash
# 用法: feishu_send_group.sh <chat_id> <message>
# 依赖: jq, curl

APP_ID="cli_a937bc46a1395cb2"
APP_SECRET=$(cat /home/lilei/.openclaw/credentials.bak.2026-03-20-041806/feishu-pairing.json 2>/dev/null | jq -r '.appSecret // empty')

# 如果 credentials 里没有 secret，尝试从主配置读取（需要解密）
if [ -z "$APP_SECRET" ] || [ "$APP_SECRET" = "null" ]; then
  APP_SECRET=$(cat /home/lilei/.openclaw/openclaw.json 2>/dev/null | jq -r '.channels.feishu.accounts.main.appSecret // empty')
fi

CHAT_ID="$1"
MESSAGE="$2"

if [ -z "$CHAT_ID" ] || [ -z "$MESSAGE" ]; then
  echo "Usage: feishu_send_group.sh <chat_id> <message>"
  exit 1
fi

# 获取 tenant access token
TOKEN_RESP=$(curl -s -X POST "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
  -H "Content-Type: application/json" \
  -d "{\"app_id\":\"$APP_ID\",\"app_secret\":\"$APP_SECRET\"}")

TOKEN=$(echo "$TOKEN_RESP" | jq -r '.tenant_access_token // empty')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "Failed to get token: $TOKEN_RESP"
  exit 1
fi

# 发送文本消息到群
RESP=$(curl -s -X POST "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"receive_id\":\"$CHAT_ID\",\"msg_type\":\"text\",\"content\":\"{\\\"text\\\":\\\"$MESSAGE\\\"}\"}")

CODE=$(echo "$RESP" | jq -r '.code // -1')
if [ "$CODE" = "0" ]; then
  echo "OK"
else
  echo "Error $CODE: $RESP"
fi
