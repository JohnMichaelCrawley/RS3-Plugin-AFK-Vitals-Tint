
#!/usr/bin/env bash
# =============================================================================
# File:        deploy-rc.sh
# Project:     RS3 AFK Vitals Tint
# Author:      John Crawley
# Description:
#   Validates, packages and deploys the plugin to Developer Beta.
# =============================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

ARTIFACT="$PWD/dist/afk-vitals-tint.zip"
TARGET="${RS3_BETA_PLUGIN_DIR:-$HOME/Jagex/RuneScape-BETA/dev_plugins/afk-vitals-tint}"
REQUIRED=(
    main.lua
    plugin.json
    logic.lua
    settings.lua
    settings_ui.lua
    version.lua
)

echo "=== RuneScape Developer Beta Deployment ==="

# Validate the project and build a fresh release archive.
bash .jenkins/scripts/ci.sh
bash .jenkins/scripts/package.sh

# Verify the complete package before deployment.
echo "=== Validating Plugin Artifact ==="
unzip -tq "$ARTIFACT" > /dev/null
entries="$(unzip -Z -1 "$ARTIFACT")"

for file in "${REQUIRED[@]}"; do
    if ! grep -Fxq "$file" <<< "$entries"; then
        echo "ERROR: Missing $file in ZIP." >&2
        exit 1
    fi
    echo "Verified: $file"
done

# Deploy the packaged plugin.
echo "=== Deploying AFK Vitals Tint ==="
mkdir -p "$TARGET"
unzip -oq "$ARTIFACT" -d "$TARGET"

# Ensure the runtime settings file contains the embedded version.
if grep -Fq '__PLUGIN_VERSION__' "$TARGET/settings_ui.lua"; then
    echo "ERROR: Deployed settings contain an unresolved version." >&2
    exit 1
fi

echo "Deployment completed successfully."
echo "Destination: $TARGET"

# Optionally launch the Developer Beta client.
if [[ "${LAUNCH_BETA:-false}" == "true" ]]; then
    echo "Opening RuneScape Developer Beta..."
    open 'jagex:launch=runescape,args=[configURI=rs-launch://www.runescape.com/jav_config_beta.ws]'
else
    echo "Beta auto-launch disabled."
fi

echo "Reload the plugin using: prl afk-vitals-tint"
