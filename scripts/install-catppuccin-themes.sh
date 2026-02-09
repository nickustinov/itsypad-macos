#!/bin/bash
# Copies custom highlight.js themes into the Highlightr checkout.
# Run this after `swift package resolve` or `swift package reset`.

set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$DIR/.build/checkouts/Highlightr/src/assets/styles"

if [ ! -d "$DEST" ]; then
  echo "Highlightr checkout not found. Run 'swift package resolve' first."
  exit 1
fi

cp "$DIR/Sources/Resources/catppuccin-"*.min.css "$DEST/"
cp "$DIR/Sources/Resources/itsypad-"*.min.css "$DEST/"
echo "Custom themes installed into Highlightr."
