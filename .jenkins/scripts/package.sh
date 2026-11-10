
#!/usr/bin/env bash
# =============================================================================
#
# File:        package.sh
# Project:     RS3 AFK Vitals Tint
# Author:      John Crawley
#
# Description:
#   Packages the RuneScape 3 plugin source files into a distributable ZIP
#   archive. Ensures that the required plugin files are included in the
#   correct structure for local testing and mod.io release submissions.
#
# Usage:
#   bash .jenkins/scripts/package.sh
#
# Output:
#   dist/afk-vitals-tint.zip
#
# =============================================================================
set -euo pipefail

# Navigate to the repository root.
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
ARTIFACT="dist/afk-vitals-tint.zip"
echo "=== Packaging RuneScape Plugin ==="
# Make dist directory
mkdir -p dist
rm -f "$ARTIFACT"
# -j removes the src/ directory from ZIP entry paths.
zip -q -j "$ARTIFACT" \
    src/main.lua \
    src/plugin.json \
    src/logic.lua \
    src/settings.lua
echo "=== Validating Package ==="
for file in main.lua plugin.json logic.lua settings.lua; do
    unzip -Z -1 "$ARTIFACT" | grep -Fxq "$file"
done
echo "Package created: $ARTIFACT"