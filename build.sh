#!/usr/bin/env bash
# Builds mStats: regenerates the Xcode project via xcodegen, then builds it.
# Unsigned by default (see PRD/PRD.md §10).
#
# Usage: ./build.sh [--release] [--run] [--clean] [--sign]
#   --release  Build the Release configuration instead of Debug.
#   --run      Open the built .app once the build succeeds.
#   --clean    Remove ./build before building.
#   --sign     Sign with your "Apple Development" identity so the code
#              signature stays stable across rebuilds. macOS ties Camera and
#              Accessibility grants to it; an unsigned build loses them on
#              every rebuild. Override the identity with MSTATS_SIGN_IDENTITY.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

CONFIGURATION="Debug"
RUN_AFTER_BUILD=false
CLEAN=false
SIGN=false

for arg in "$@"; do
  case "$arg" in
    --release) CONFIGURATION="Release" ;;
    --run) RUN_AFTER_BUILD=true ;;
    --clean) CLEAN=true ;;
    --sign) SIGN=true ;;
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

if [ "$SIGN" = true ]; then
  IDENTITY="${MSTATS_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)}"
  if [ -z "$IDENTITY" ]; then
    echo "error: no 'Apple Development' signing identity found. Sign in to Xcode" >&2
    echo "       (Settings > Accounts), or set MSTATS_SIGN_IDENTITY." >&2
    exit 1
  fi
  TEAM_ID="$(security find-certificate -c "$IDENTITY" -p \
    | openssl x509 -noout -subject | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')"
  echo "==> Signing as: $IDENTITY (team $TEAM_ID)"
  SIGN_ARGS=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID"
             CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES)
else
  SIGN_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")
fi

echo "==> Building ($CONFIGURATION)"
xcodebuild -project mStats.xcodeproj -scheme mStats -configuration "$CONFIGURATION" \
  -derivedDataPath build "${SIGN_ARGS[@]}" build

APP_PATH="build/Build/Products/$CONFIGURATION/mStats.app"
echo "==> Built $APP_PATH"

if [ "$RUN_AFTER_BUILD" = true ]; then
  open "$APP_PATH"
fi
