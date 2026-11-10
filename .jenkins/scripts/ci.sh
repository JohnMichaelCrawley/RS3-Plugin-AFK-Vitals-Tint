
#!/usr/bin/env bash
# =============================================================================
#
# File:        ci.sh
# Project:     RS3 AFK Vitals Tint
# Author:      John Crawley
#
# Description:
#   Executes the Continuous Integration (CI) checks for the RuneScape 3 plugin.
#   Validates Lua source code, runs automated tests, and verifies that the
#   project meets the required quality checks before deployment.
#
# Usage:
#   bash .jenkins/scripts/ci.sh
#
# =============================================================================
set -euo pipefail

# Navigate to the repository root.
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
# Use the Homebrew Lua 5.4 installation on macOS.
LUA="/opt/homebrew/opt/lua@5.4/bin/lua"
LUAC="/opt/homebrew/opt/lua@5.4/bin/luac"
echo "=== Validating Lua Source ==="
for file in src/*.lua tests/*.lua; do
    "$LUAC" -p "$file"
done
echo "=== Validating Plugin Manifest ==="
python3 -m json.tool src/plugin.json > /dev/null
echo "=== Running Unit Tests ==="
LUA_PATH="$PWD/src/?.lua;;" "$LUA" tests/test_logic.lua
echo "=== CI Checks Passed ==="