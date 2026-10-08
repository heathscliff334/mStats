#!/usr/bin/env bash
# Builds mStats: regenerates the Xcode project via xcodegen, then builds it
# unsigned (no Apple Developer enrollment yet, see PRD/PRD.md §10).
#
# Usage: ./build.sh [--release] [--run] [--clean]
#   --release  Build the Release configuration instead of Debug.
#   --run      Open the built .app once the build succeeds.
#   --clean    Remove ./build before building.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

CONFIGURATION="Debug"
RUN_AFTER_BUILD=false
CLEAN=false

for arg in "$@"; do
  case "$arg" in
    --release) CONFIGURATION="Release" ;;
    --run) RUN_AFTER_BUILD=true ;;
    --clean) CLEAN=true ;;
    -h|--help)
      grep '^#' "$0" | cut -c3-
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (see --help)" >&2
      exit 1
      ;;
  esac
done

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found. Install it with: brew install xcodegen" >&2
  exit 1
fi

if [ "$CLEAN" = true ]; then
  echo "==> Removing ./build"
  rm -rf build
fi

echo "==> Generating mStats.xcodeproj"
xcodegen generate

echo "==> Building ($CONFIGURATION)"
xcodebuild -project mStats.xcodeproj -scheme mStats -configuration "$CONFIGURATION" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

APP_PATH="build/Build/Products/$CONFIGURATION/mStats.app"
echo "==> Built $APP_PATH"

if [ "$RUN_AFTER_BUILD" = true ]; then
  open "$APP_PATH"
fi
