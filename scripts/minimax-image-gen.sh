#!/bin/bash
# MiniMax Image Generation Test Script
# Usage: ./minimax-image-gen.sh "your prompt here" [aspect_ratio]

API_KEY="${MINIMAX_API_KEY}"
PROMPT="${1:-a beautiful sunset over the ocean}"
ASPECT_RATIO="${2:-1:1}"

echo "Generating image..."
echo "Prompt: $PROMPT"
echo "Aspect Ratio: $ASPECT_RATIO"

RESPONSE=$(curl -s -X POST "https://api.minimaxi.com/v1/image_generation" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"image-01\",
    \"prompt\": \"$PROMPT\",
    \"aspect_ratio\": \"$ASPECT_RATIO\"
  }")

echo "Response:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
