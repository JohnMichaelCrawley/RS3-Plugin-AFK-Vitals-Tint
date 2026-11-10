
#!/usr/bin/env bash
# =============================================================================
# File:        deploy-modio.sh
# Project:     RS3 AFK Vitals Tint
# Description:
#   Uploads an approved, versioned plugin ZIP to an existing mod.io listing.
# =============================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

: "${MODIO_GAME_ID:?Set the numerical mod.io game ID}"
: "${MODIO_MOD_ID:?Set the numerical mod.io plugin listing ID}"
: "${MODIO_TOKEN:?Configure the Jenkins modio-oauth-token credential}"
: "${RELEASE_CHANGELOG:?Enter a changelog for this release}"

# Validate listing identifiers.
[[ "$MODIO_GAME_ID" =~ ^[0-9]+$ && "$MODIO_MOD_ID" =~ ^[0-9]+$ ]] || {
    echo "mod.io IDs must be numbers." >&2
    exit 1
}

# Require approval from the Jenkins release stage.
[[ "${MODIO_UPLOAD_CONFIRM:-}" == "YES" ]] || {
    echo "Upload blocked: Jenkins manual approval is required." >&2
    exit 1
}

ARTIFACT="dist/afk-vitals-tint.zip"
test -s "$ARTIFACT" || {
    echo "Missing ZIP: $ARTIFACT" >&2
    exit 1
}

# Read the release version from plugin.json.
VERSION="$(python3 - <<'PY'
import json
import re
from pathlib import Path

version = json.loads(Path("src/plugin.json").read_text())["version"]
if not re.fullmatch(r"\d+(?:\.\d+){2}", version):
    raise SystemExit("Invalid plugin.json version")
print(version)
PY
)"

# Refuse to upload a package with a mismatched version.
ZIP_VERSION="$(unzip -p "$ARTIFACT" version.lua)"
[[ "$ZIP_VERSION" == "return \"$VERSION\"" ]] || {
    echo "ZIP version differs from plugin.json. Repackage first." >&2
    exit 1
}

API_URL="https://g-${MODIO_GAME_ID}.modapi.io/v1/games/${MODIO_GAME_ID}/mods/${MODIO_MOD_ID}/files"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/afk-vitals-modio.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

RELEASE_ZIP="$TMP/afk-vitals-tint-${VERSION//./-}.zip"
cp "$ARTIFACT" "$RELEASE_ZIP"

# Prevent uploading a version already submitted to mod.io.
curl --silent --show-error --fail --get \
    --header "Accept: application/json" \
    --header "Authorization: Bearer ${MODIO_TOKEN}" \
    --data-urlencode "version=${VERSION}" \
    --output "$TMP/existing.json" "$API_URL"

python3 - "$TMP/existing.json" <<'PY'
import json
import sys
from pathlib import Path

result = json.loads(Path(sys.argv[1]).read_text())
if not isinstance(result.get("data"), list):
    raise SystemExit("Could not check existing mod.io versions; upload blocked.")
if result["data"]:
    raise SystemExit("This version already exists on mod.io; bump plugin.json.")
PY

echo "Submitting AFK Vitals Tint v${VERSION} to mod.io for moderation..."

# Upload to Windows, Mac and Linux platforms.
HTTP_CODE="$(curl --silent --show-error \
    --output "$TMP/upload.json" \
    --write-out "%{http_code}" \
    --request POST \
    --header "Accept: application/json" \
    --header "Authorization: Bearer ${MODIO_TOKEN}" \
    --form "filedata=@${RELEASE_ZIP};type=application/zip" \
    --form-string "version=${VERSION}" \
    --form-string "changelog=${RELEASE_CHANGELOG}" \
    --form "platforms[]=WINDOWS" \
    --form "platforms[]=MAC" \
    --form "platforms[]=LINUX" \
    --form "active=true" \
    "$API_URL")"

if [[ "$HTTP_CODE" != "201" ]]; then
    echo "mod.io upload failed (HTTP ${HTTP_CODE})." >&2
    cat "$TMP/upload.json" >&2
    exit 1
fi

# Validate and report the successful upload response.
python3 - "$TMP/upload.json" "$VERSION" <<'PY'
import json
import sys
from pathlib import Path

response = json.loads(Path(sys.argv[1]).read_text())
if not isinstance(response.get("id"), int):
    raise SystemExit("mod.io returned HTTP 201 without a modfile ID; inspect submission.")

print(f"Submitted version {sys.argv[2]} as mod.io file ID {response['id']}.")
print("Submission is not public until Jagex moderation approves it.")
PY
