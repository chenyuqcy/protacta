#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PREVIEW_BUILD="$PROJECT_ROOT/output/catalog-previews"
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--compile-only" ) ]]; then
  echo "Usage: $0 [--compile-only]" >&2
  exit 2
fi
mkdir -p "$PREVIEW_BUILD/module-cache"
xcrun swiftc -O -module-cache-path "$PREVIEW_BUILD/module-cache" \
  "$PROJECT_ROOT/scripts/render_everyday_catalog_thumbnails.swift" \
  "$PROJECT_ROOT/ios/PaperSteps/EverydayTutorialCourse.swift" \
  "$PROJECT_ROOT/ios/PaperSteps/EverydayMeshGeometry.swift" \
  "$PROJECT_ROOT/ios/PaperSteps/EverydayClothGeometry.swift" \
  "$PROJECT_ROOT/ios/PaperSteps/EverydaySoftTowelGeometry.swift" \
  "$PROJECT_ROOT/ios/PaperSteps/EverydayKnotGeometry.swift" \
  "$PROJECT_ROOT/ios/PaperSteps/Towel3DGeometry.swift" \
  "$PROJECT_ROOT/ios/PaperSteps/EverydaySurfaceMesh.swift" \
  "$PROJECT_ROOT/ios/PaperSteps/EverydaySurfaceStyle.swift" \
  "$PROJECT_ROOT/ios/PaperSteps/EverydayFabricStyle.swift" \
  -o "$PREVIEW_BUILD/render-everyday"
if [[ "${1:-}" == "--compile-only" ]]; then
  exit 0
fi
"$PREVIEW_BUILD/render-everyday" \
  "$PROJECT_ROOT/ios/PaperSteps/Resources" \
  "$PREVIEW_BUILD/everyday-preview-manifest.json"
