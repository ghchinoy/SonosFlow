#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

mkdir -p docs/diagrams docs/src/assets/diagrams

echo "🎨 Rendering Graphviz architecture diagram..."
dot -Tpng -Gdpi=192 docs/diagrams/architecture.dot -o docs/diagrams/architecture.png

echo "🖼️  Converting to high-resolution WebP..."
cwebp -q 90 docs/diagrams/architecture.png -o docs/src/assets/diagrams/architecture.webp

echo "✅ Generated: docs/src/assets/diagrams/architecture.webp ($(wc -c < docs/src/assets/diagrams/architecture.webp | tr -d ' ') bytes)"
