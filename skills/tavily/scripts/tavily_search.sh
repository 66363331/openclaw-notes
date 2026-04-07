#!/bin/bash
# Tavily search wrapper - injects API key from openclaw config then calls the Python script
cd ~/.openclaw/workspace/skills/tavily

# Try multiple paths for openclaw.json (isolated sessions may have different HOME)
for CONFIG in \
    "/home/lilei/.openclaw/openclaw.json" \
    "$HOME/.openclaw/openclaw.json" \
    "${HOME:-/home/lilei}/.openclaw/openclaw.json"
do
    if [ -f "$CONFIG" ]; then
        KEY=$(python3 -c "
import json
with open('$CONFIG') as f:
    data = json.load(f)
print(data.get('skills', {}).get('entries', {}).get('tavily', {}).get('apiKey', ''))
" 2>/dev/null)
        if [ -n "$KEY" ]; then
            break
        fi
    fi
done

export TAVILY_API_KEY="${KEY:-}"
echo "[DEBUG] TAVILY_API_KEY: ${KEY:+OK (len=${#KEY})}" >&2
exec python3 scripts/tavily_search.py "$@"
