#!/bin/bash
# Tavily search wrapper - injects API key from openclaw config then calls the Python script
cd ~/.openclaw/workspace/skills/tavily

# Read API key from openclaw config and set as env var
KEY=$(python3 -c "
import json, re
with open('/home/lilei/.openclaw/openclaw.json') as f:
    data = json.load(f)
print(data.get('skills', {}).get('entries', {}).get('tavily', {}).get('apiKey', ''))
" 2>/dev/null)

export TAVILY_API_KEY="$KEY"
exec python3 scripts/tavily_search.py "$@"
