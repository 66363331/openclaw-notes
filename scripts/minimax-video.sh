#!/bin/bash
# MiniMax Video Generation Script
# Usage: ./minimax-video.sh "video description" [model]

API_KEY="${MINIMAX_API_KEY}"
PROMPT="${1:-A beautiful sunset over the ocean with waves crashing on the beach}"
MODEL="${2:-MiniMax-Hailuo-2.3-Fast}"

echo "Generating video..."
echo "Prompt: $PROMPT"
echo "Model: $MODEL"

RESPONSE=$(curl -s -X POST "https://api.minimaxi.com/v1/video_generation" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"prompt\": \"$PROMPT\"
  }")

echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
