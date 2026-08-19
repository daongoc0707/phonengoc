#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$REPO_ROOT/phoneME.xcodeproj"
SCHEME="${SCHEME:-phoneME}"
CONFIGURATION="Release"
OUTPUT_ROOT="${OUTPUT_ROOT:-$REPO_ROOT/Artifacts}"
OUTPUT_IPA="${OUTPUT_IPA:-$OUTPUT_ROOT/phoneME-0.3.4-build6-fixed-unsigned.ipa}"
DERIVED_DATA="${DERIVED_DATA:-$REPO_ROOT/.build/fixed-unsigned-device}"
BUILD_LOG="${BUILD_LOG:-$OUTPUT_ROOT/phoneME-build6-fixed-build.log}"
CLEAN_BUILD=false
RUN_CORE_TESTS=false

usage() {
  cat <<'USAGE'
Build the patched phoneME app as an unsigned iPhone IPA.

Usage:
  bash Scripts/build-unsigned-ipa.sh [options]

Options:
  --clean              Remove cached DerivedData before building.
  --rebuild-core       Run the host Core tests before the iPhone build.
  --output PATH        Output IPA path.
  --output-root PATH   Artifact directory.
  --derived-data PATH  Xcode DerivedData directory.
  -h, --help           Show this help.

Environment overrides:
  OUTPUT_ROOT, OUTPUT_IPA, DERIVED_DATA, BUILD_LOG, SCHEME

The result is intentionally unsigned. Install it with a compatible sideloading
or permanent-signing workflow, or sign it with your own Apple certificate.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      CLEAN_BUILD=true
      shift
      ;;
    --rebuild-core)
      RUN_CORE_TESTS=true
      shift
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "Missing value for --output" >&2; exit 2; }
      OUTPUT_IPA="$2"
      shift 2
      ;;
    --output-root)
      [[ $# -ge 2 ]] || { echo "Missing value for --output-root" >&2; exit 2; }
      OUTPUT_ROOT="$2"
      OUTPUT_IPA="$OUTPUT_ROOT/phoneME-0.3.4-build6-fixed-unsigned.ipa"
      BUILD_LOG="$OUTPUT_ROOT/phoneME-build6-fixed-build.log"
      shift 2
      ;;
    --derived-data)
      [[ $# -ge 2 ]] || { echo "Missing value for --derived-data" >&2; exit 2; }
      DERIVED_DATA="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for command in xcodebuild zip unzip find mktemp cp rm mkdir tee; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

[[ -d "$PROJECT_PATH" ]] || {
  echo "Xcode project not found: $PROJECT_PATH" >&2
  exit 1
}

mkdir -p "$OUTPUT_ROOT" "$(dirname "$OUTPUT_IPA")"

if [[ "$CLEAN_BUILD" == true ]]; then
  rm -rf "$DERIVED_DATA"
fi

if [[ "$RUN_CORE_TESTS" == true ]]; then
  echo "== Running phoneME Core host tests =="
  bash "$REPO_ROOT/Core/Tools/test-host.sh"
fi

echo "== Building phoneME 0.3.4 build 6 (unsigned) =="
set +e
set -o pipefail
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM='' \
  TARGETED_DEVICE_FAMILY=1 \
  build \
  2>&1 | tee "$BUILD_LOG"
build_status=${PIPESTATUS[0]}
set +o pipefail
set -e

if [[ "$build_status" -ne 0 ]]; then
  echo "==================== BUILD FAILED: LOG OUTPUT ====================" >&2
  tail -n 100 "$BUILD_LOG" >&2 || cat "$BUILD_LOG" >&2
  echo "==================================================================" >&2
  echo "Unsigned iPhone build failed. See: $BUILD_LOG" >&2
  exit "$build_status"
fi

APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos/phoneME.app"
if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="$(find "$DERIVED_DATA/Build/Products" \
    -type d -path '*-iphoneos/*.app' -name 'phoneME.app' -print -quit)"
fi
[[ -n "${APP_PATH:-}" && -d "$APP_PATH" ]] || {
  echo "Built phoneME.app not found in $DERIVED_DATA" >&2
  exit 1
}

PACKAGE_ROOT="$(mktemp -d /tmp/phoneme-fixed-ipa.XXXXXX)"
cleanup() {
  rm -rf "$PACKAGE_ROOT"
}
trap cleanup EXIT

mkdir -p "$PACKAGE_ROOT/Payload"
cp -R "$APP_PATH" "$PACKAGE_ROOT/Payload/"
rm -f "$OUTPUT_IPA"
(
  cd "$PACKAGE_ROOT"
  zip -qry "$OUTPUT_IPA" Payload
)
unzip -tq "$OUTPUT_IPA" >/dev/null

cat <<RESULT

Unsigned IPA created successfully.
IPA: $OUTPUT_IPA
Build log: $BUILD_LOG
RESULT
