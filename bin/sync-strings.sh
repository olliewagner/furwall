#!/usr/bin/env bash
# Sync extracted strings from the latest Debug build into Localizable.xcstrings.
#
# Why this exists: when you build via Xcode IDE the .xcstrings catalog source
# auto-populates with strings extracted from Swift code. CLI builds
# (`xcodebuild …`) produce per-file .stringsdata but don't write them back to
# the catalog source. Run this after a CLI build that introduces or removes
# user-facing strings, then commit the catalog diff.
#
# Usage: bin/sync-strings.sh [debug|release]   # default: debug

set -euo pipefail

CONFIG="${1:-Debug}"
case "$CONFIG" in
  debug|Debug) CONFIG=Debug ;;
  release|Release) CONFIG=Release ;;
  *) echo "usage: $0 [debug|release]" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CATALOG="$ROOT/Resources/Localizable.xcstrings"
SD_ROOT="$ROOT/build/dd/Build/Intermediates.noindex/Furwall.build/$CONFIG/Furwall.build/Objects-normal"

if [ ! -d "$SD_ROOT" ]; then
  echo "no .stringsdata under $SD_ROOT — build first with:" >&2
  echo "  xcodebuild -project Furwall.xcodeproj -scheme Furwall \\" >&2
  echo "    -configuration $CONFIG -derivedDataPath build/dd build" >&2
  exit 1
fi

ARGS=()
while IFS= read -r -d '' f; do
  case "$f" in *ExtractedAppShortcuts*) continue ;; esac
  ARGS+=(--stringsdata "$f")
done < <(find "$SD_ROOT" -name '*.stringsdata' -print0)

if [ ${#ARGS[@]} -eq 0 ]; then
  echo "no .stringsdata files found under $SD_ROOT" >&2
  exit 1
fi

xcrun xcstringstool sync "$CATALOG" "${ARGS[@]}"
echo "synced $((${#ARGS[@]} / 2)) .stringsdata file(s) into $CATALOG"
