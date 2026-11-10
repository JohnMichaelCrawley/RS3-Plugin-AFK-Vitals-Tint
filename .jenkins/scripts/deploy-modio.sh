
#!/usr/bin/env bash
# =============================================================================
#
# File:        deploy-modio.sh
# Project:     RS3 AFK Vitals Tint
# Author:      John Crawley
#
# Description:
#   Submits a validated and versioned RuneScape 3 plugin release to mod.io
#   using authenticated API requests.
#
#   Intended for use within the Jenkins release pipeline following
#   successful CI checks and explicit release approval.
#
#   Submitted releases remain subject to Jagex moderation before they
#   become available to RuneScape players.
#
# Usage:
#   bash .jenkins/scripts/deploy-modio.sh
#
# Security:
#   API credentials must be provided through Jenkins Credentials.
#   Never hardcode authentication tokens or secrets into this script.
#
# =============================================================================
set -euo pipefail
