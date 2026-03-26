#!/bin/bash
# MiniMax Text-to-Speech Synthesis Script
# Usage: ./minimax-speech.sh "your text here" [voice_id] [model]

API_KEY="${MINIMAX_API_KEY}"
TEXT="${1:-今天是不是很开心呀，当然了！}"
VOICE_ID="${2:-female-tianmei}"
MODEL="${3:-speech-2.8-hd}"
SPEED="${4:-1}"
EMOTION="${5:-happy}"

echo "Generating speech..."
echo "Text: $TEXT"
echo "Voice: $VOICE_ID"
echo "Model: $MODEL"

RESPONSE=$(curl -s -X POST "https://api.minimaxi.com/v1/t2a_v2" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"text\": \"$TEXT\",
    \"stream\": false,
    \"voice_setting\": {
      \"voice_id\": \"$VOICE_ID\",
      \"speed\": $SPEED,
      \"vol\": 1,
      \"pitch\": 0,
      \"emotion\": \"$EMOTION\"
    },
    \"audio_setting\": {
      \"sample_rate\": 32000,
      \"bitrate\": 128000,
      \"format\": \"mp3\",
      \"channel\": 1
    }
  }")

# Check if we got an audio URL or data
echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'data' in data and 'audio_url' in data['data']:
        print('Audio URL:', data['data']['audio_url'])
    elif 'data' in data and 'audio_file' in data['data']:
        print('Audio file:', data['data']['audio_file'])
    else:
        print(json.dumps(data, indent=2, ensure_ascii=False))
except:
    print(sys.stdin.read())
" 2>/dev/null || echo "$RESPONSE"
