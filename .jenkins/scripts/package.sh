
#!/usr/bin/env bash
# =============================================================================
# File:        package.sh
# Project:     RS3 AFK Vitals Tint
# Author:      John Crawley
# Description:
#   Packages the plugin, embeds its manifest version in the settings UI,
#   and generates release metadata for mod.io.
# =============================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

ROOT="$PWD"
ARTIFACT="$ROOT/dist/afk-vitals-tint.zip"
FILES=(
    main.lua
    plugin.json
    logic.lua
    settings.lua
    settings_ui.lua
    version.lua
)
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/afk-vitals-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

echo "=== Packaging RuneScape Plugin ==="
mkdir -p "$ROOT/dist"

# Copy the required source files.
for file in main.lua plugin.json logic.lua settings.lua settings_ui.lua; do
    if [[ ! -f "$ROOT/src/$file" ]]; then
        echo "ERROR: Missing src/$file" >&2
        exit 1
    fi
    cp "$ROOT/src/$file" "$STAGE/$file"
done

# Generate version.lua and embed the manifest version in settings_ui.lua.
python3 - "$STAGE" <<'PY'
import json
import re
import sys
from pathlib import Path

stage = Path(sys.argv[1])
manifest = json.loads((stage / "plugin.json").read_text(encoding="utf-8"))
version = manifest.get("version")

if not isinstance(version, str) or not re.fullmatch(r"\d+(?:\.\d+){2}", version):
    raise SystemExit("ERROR: Invalid plugin.json version.")

settings_path = stage / "settings_ui.lua"
source = settings_path.read_text(encoding="utf-8")

placeholder = 'local VERSION = "__PLUGIN_VERSION__"'
replacement = f"local VERSION = {json.dumps(version)}"

if source.count(placeholder) != 1:
    raise SystemExit(
        "ERROR: settings_ui.lua must contain exactly one version placeholder."
    )

settings_path.write_text(
    source.replace(placeholder, replacement, 1),
    encoding="utf-8"
)

(stage / "version.lua").write_text(
    f"return {json.dumps(version)}\n",
    encoding="utf-8"
)

print(f"Manifest version: {version}")
print("Embedded version into settings_ui.lua")
print("Generated version.lua")
PY

# Create a clean ZIP with all files at the archive root.
rm -f "$ARTIFACT"
(
    cd "$STAGE"
    zip -q "$ARTIFACT" "${FILES[@]}"
)

# Verify archive integrity and required files.
echo "=== Validating Package ==="
unzip -tq "$ARTIFACT" > /dev/null
entries="$(unzip -Z -1 "$ARTIFACT")"

for file in "${FILES[@]}"; do
    if ! grep -Fxq "$file" <<< "$entries"; then
        echo "ERROR: Missing $file in ZIP." >&2
        exit 1
    fi
    echo "Verified: $file"
done

# Confirm the generated settings file has no unresolved placeholder.
if unzip -p "$ARTIFACT" settings_ui.lua |
    grep -Fq '__PLUGIN_VERSION__'; then
    echo "ERROR: Version placeholder was not replaced." >&2
    exit 1
fi

echo "Package created: $ARTIFACT"
