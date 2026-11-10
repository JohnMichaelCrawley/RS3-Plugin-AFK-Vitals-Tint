
#!/usr/bin/env bash
# =============================================================================
# File:        deploy-rc.sh
# Project:     RS3 AFK Vitals Tint
# Author:      John Crawley
#
# Description:
#   Packages and deploys the current plugin to the local RuneScape 3
#   Developer Beta environment on macOS for in-game validation.
#
#   This deployment does not publish the plugin to mod.io.
#
# Usage:
#   bash .jenkins/scripts/deploy-rc.sh
#
# =============================================================================
set -euo pipefail
# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PLUGIN_NAME="afk-vitals-tint"
SOURCE_DIR="${PROJECT_ROOT}/src"
ARTIFACT="${PROJECT_ROOT}/dist/${PLUGIN_NAME}.zip"
BETA_ROOT="${RS3_BETA_ROOT:-${HOME}/Jagex/RuneScape-BETA}"
TARGET_DIR="${BETA_ROOT}/dev_plugins/${PLUGIN_NAME}"
# -----------------------------------------------------------------------------
# Validation 
# -----------------------------------------------------------------------------
# Verify the RuneScape Developer Beta installation exists.
validate_environment() {
    if [[ ! -d "${BETA_ROOT}" ]]; then
        echo "ERROR: RuneScape Developer Beta directory not found."
        echo "Expected: ${BETA_ROOT}"
        exit 1
    fi
    if [[ ! -d "${SOURCE_DIR}" ]]; then
        echo "ERROR: Plugin source directory not found."
        exit 1
    fi
}

# Verify the deployment archive contains all required plugin files.

# Validates the packaged plugin before deployment.
# Ensures the archive is readable and contains all required files.
validate_artifact() {
    echo "Validating plugin artifact..."

    if [[ ! -s "${ARTIFACT}" ]]; then
        echo "ERROR: Plugin artifact does not exist or is empty."
        exit 1
    fi

    if ! unzip -tq "${ARTIFACT}" > /dev/null; then
        echo "ERROR: Plugin archive is invalid or corrupted."
        exit 1
    fi

    # Read archive entries once to avoid pipeline-related false failures.
    local archive_entries
    archive_entries="$(unzip -Z -1 "${ARTIFACT}")"

    local required_files=(
        "main.lua"
        "plugin.json"
        "logic.lua"
        "settings.lua"
    )

    # Confirm each file exists at the archive root.
    local file
    for file in "${required_files[@]}"; do
        if ! grep -Fxq -- "${file}" <<< "${archive_entries}"; then
            echo "ERROR: Missing ${file} in plugin archive."
            exit 1
        fi

        echo "Verified: ${file}"
    done

    echo "Plugin artifact validation passed."
}

# -----------------------------------------------------------------------------
# Deployment
# -----------------------------------------------------------------------------
# Generate a fresh plugin package from the current source code.
package_plugin() {
    echo "Packaging plugin..."
    bash "${SCRIPT_DIR}/package.sh"
    validate_artifact
}

# Extract the verified plugin package into the local beta installation.
deploy_plugin() {
    echo "Deploying ${PLUGIN_NAME}..."
    mkdir -p "${TARGET_DIR}"
    unzip -oq "${ARTIFACT}" -d "${TARGET_DIR}"
    echo "Deployment completed successfully."
    echo "Destination: ${TARGET_DIR}"
}



# -----------------------------------------------------------------------------
# Open beta
# -----------------------------------------------------------------------------
# Opens the RuneScape Developer Beta through the Jagex Launcher.
# Launching is optional to support both local testing and Jenkins builds.
launch_beta() {
    local launch_url='jagex:launch=runescape,args=[configURI=rs-launch://www.runescape.com/jav_config_beta.ws]'

    if [[ "${LAUNCH_BETA:-false}" != "true" ]]; then
        echo "Beta auto-launch disabled."
        return 0
    fi

    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "ERROR: Automatic beta launch is supported only on macOS."
        return 1
    fi

    echo "Opening RuneScape Developer Beta..."
    open "${launch_url}"
}



# -----------------------------------------------------------------------------
# Entry Point
# -----------------------------------------------------------------------------
# Runs validation before packaging and deploying the plugin.
# Deployment stops immediately if any CI check fails.

# Runs CI validation, packages the plugin, and deploys it locally.
# Optionally launches RuneScape Developer Beta after successful deployment.
main() {
    echo "=== RuneScape Developer Beta Deployment ==="

    validate_environment

    echo "Running CI checks..."
    bash "${SCRIPT_DIR}/ci.sh"

    package_plugin
    deploy_plugin

    echo "=== Launching Developer Beta ==="
    launch_beta

    echo "=== Deployment Process Completed ==="
    echo "Destination: ${TARGET_DIR}"
    echo "Reload the plugin using: prl ${PLUGIN_NAME}"
}

main "$@"
