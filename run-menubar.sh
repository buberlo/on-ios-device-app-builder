#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

pkill -x BuilderHost 2>/dev/null || true
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build \
  -scheme BuilderHost \
  -configuration Debug \
  -derivedDataPath .derived
open .derived/Build/Products/Debug/BuilderHost.app
