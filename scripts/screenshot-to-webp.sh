#!/usr/bin/env bash
# screenshot-to-webp.sh
# Converts a macOS retina screenshot PNG to an optimized WebP image with optional coordinate-based blur.
# Usage: ./scripts/screenshot-to-webp.sh <input.png> <output-base-name> [x1:y1:x2:y2]

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT="$1"
OUTPUT_NAME="$2"
BLUR_BOX="$3"

if [ -z "$INPUT" ] || [ -z "$OUTPUT_NAME" ]; then
    echo "Usage: $0 <input.png> <output-base-name> [x1:y1:x2:y2]"
    echo "Example: $0 ~/Desktop/shot.png main-window 788:252:926:292"
    exit 1
fi

DEST_DIR="$DIR/docs/src/assets/screenshots"
mkdir -p "$DEST_DIR"
OUTPUT_WEBP="$DEST_DIR/${OUTPUT_NAME}.webp"

TEMP_PNG="/tmp/${OUTPUT_NAME}_processed.png"

if [ -n "$BLUR_BOX" ]; then
    echo "🔍 Applying Gaussian blur to region $BLUR_BOX..."
    python3 -c "
from PIL import Image, ImageFilter
import sys

im = Image.open('$INPUT')
box = tuple(map(int, '$BLUR_BOX'.split(':')))
region = im.crop(box)
blurred = region.filter(ImageFilter.GaussianBlur(radius=7))
im.paste(blurred, box)
im.save('$TEMP_PNG')
"
    SOURCE_FOR_CWEBP="$TEMP_PNG"
else
    SOURCE_FOR_CWEBP="$INPUT"
fi

echo "📦 Converting to WebP: $OUTPUT_WEBP"
cwebp -q 82 "$SOURCE_FOR_CWEBP" -o "$OUTPUT_WEBP"

if [ -f "$TEMP_PNG" ]; then
    rm -f "$TEMP_PNG"
fi

echo "✅ Saved: $OUTPUT_WEBP ($(ls -lh "$OUTPUT_WEBP" | awk '{print $5}'))"
