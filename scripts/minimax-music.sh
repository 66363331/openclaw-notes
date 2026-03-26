#!/bin/bash
# MiniMax Music Generation Script
# Usage: ./minimax-music.sh "music description" [lyrics]

API_KEY="${MINIMAX_API_KEY}"
PROMPT="${1:-流行音乐, 开心, 适合在阳光明媚的早晨}"
LYRICS="${2:-}"
MODEL="music-2.5+"

echo "Generating music..."
echo "Prompt: $PROMPT"

if [ -z "$LYRICS" ]; then
  DATA="{\"model\": \"$MODEL\", \"prompt\": \"$PROMPT\", \"is_instrumental\": true}"
else
  DATA="{\"model\": \"$MODEL\", \"prompt\": \"$PROMPT\", \"lyrics\": \"$LYRICS\", \"is_instrumental\": false}"
fi

RESPONSE=$(curl -s -X POST "https://api.minimaxi.com/v1/music_generation" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$DATA")

echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
