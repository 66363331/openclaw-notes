#!/usr/bin/env python3
"""
Feishu 群发消息脚本
用法: feishu_send_group.py <chat_id> <message>
"""
import sys
import json
import re
import urllib.request

def get_app_config():
    with open('/home/lilei/.openclaw/openclaw.json') as f:
        content = f.read()
    match = re.search(r'appSecret["\']:\s*["\']([^"\']{20,})["\']', content)
    if not match:
        raise Exception("appSecret not found in config")
    app_secret = match.group(1)
    app_id = "cli_a937bc46a1395cb2"
    return app_id, app_secret

def get_token(app_id, app_secret):
    req = urllib.request.Request(
        "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
        data=json.dumps({"app_id": app_id, "app_secret": app_secret}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.loads(r.read())
    token = data.get("tenant_access_token", "")
    if not token:
        raise Exception(f"Failed to get token: {data}")
    return token

def send_message(token, receive_id, receive_id_type, text):
    url = f"https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type={receive_id_type}"
    payload = json.dumps({
        "receive_id": receive_id,
        "msg_type": "text",
        "content": json.dumps({"text": text})
    }).encode()
    req = urllib.request.Request(url, data=payload,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        result = json.loads(r.read())
    code = result.get("code", -1)
    if code != 0:
        raise Exception(f"Feishu API error {code}: {result.get('msg')} | {result}")
    return result

def main():
    if len(sys.argv) < 3:
        print("Usage: feishu_send_group.py <chat_id> <message>")
        sys.exit(1)

    chat_id = sys.argv[1]
    message = sys.argv[2]

    app_id, app_secret = get_app_config()
    token = get_token(app_id, app_secret)
    result = send_message(token, chat_id, "chat_id", message)
    print("OK")

if __name__ == "__main__":
    main()
