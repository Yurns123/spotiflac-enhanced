#!/bin/bash
# SpotiFLAC Enhanced - Complete iOS IPA Build Script
# Must be run on macOS with Xcode + Go + Flutter installed
#
# This builds:
#   1. Go backend -> Gobackend.xcframework (streaming, preloading, downloads)
#   2. Flutter app -> unsigned IPA (for SideStore/AltStore sideloading)
#
# Usage: ./scripts/build_ios_ipa.sh [--unsigned|--appstore]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GO_BACKEND_DIR="$PROJECT_DIR/go_backend"
IOS_DIR="$PROJECT_DIR/ios"
OUTPUT_DIR="$IOS_DIR/Frameworks"
BUILD_TYPE="${1:-unsigned}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================================"
echo "  SpotiFLAC Enhanced - iOS Build"
echo "  Build type: $BUILD_TYPE"
echo "  $(date)"
echo "============================================================"

# ─── PREREQUISITES ───────────────────────────────────────────

if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}ERROR: This script must run on macOS with Xcode.${NC}"
    echo "Cross-compilation from Windows/Linux is not supported."
    exit 1
fi

for cmd in go flutter xcodebuild; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${YELLOW}WARNING: $cmd not found on PATH${NC}"
    else
        echo "  $cmd: $($cmd version 2>/dev/null | head -1 || echo 'found')"
    fi
done

# ─── STEP 1: Go Backend XCFramework ───────────────────────────

echo ""
echo "────────────────────────────────────────────────────────────"
echo "  STEP 1/3: Building Go backend XCFramework"
echo "────────────────────────────────────────────────────────────"

cd "$GO_BACKEND_DIR"

if ! command -v gomobile &> /dev/null; then
    echo "Installing gomobile..."
    go install golang.org/x/mobile/cmd/gomobile@latest
    go install golang.org/x/mobile/cmd/gobind@latest
fi

echo "Initializing gomobile (downloads NDK/SDK)..."
gomobile init 2>&1 | tail -1

echo "Downloading Go dependencies..."
go mod download
go mod tidy

echo "Verifying Go code..."
if ! go build ./... 2>&1; then
    echo -e "${RED}Go build failed. Fix errors above and retry.${NC}"
    exit 1
fi
echo -e "${GREEN}Go code compiles cleanly.${NC}"

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/Gobackend.xcframework"

echo "Building Gobackend.xcframework for iOS..."
echo "  (this takes 2-5 minutes the first time)"
gomobile bind \
    -target=ios \
    -o "$OUTPUT_DIR/Gobackend.xcframework" \
    .

if [ -d "$OUTPUT_DIR/Gobackend.xcframework" ]; then
    echo -e "${GREEN}STEP 1 COMPLETE: Gobackend.xcframework built${NC}"
    echo ""
    echo "  Architectures:"
    for arch in "$OUTPUT_DIR/Gobackend.xcframework/"*; do
        echo "    $(basename "$arch")"
    done
else
    echo -e "${RED}Failed to build XCFramework${NC}"
    exit 1
fi

# ─── STEP 2: Flutter Build ───────────────────────────────────

echo ""
echo "────────────────────────────────────────────────────────────"
echo "  STEP 2/3: Building Flutter app"
echo "────────────────────────────────────────────────────────────"

cd "$PROJECT_DIR"

echo "Getting Flutter dependencies..."
flutter pub get

# Regenerate Riverpod/l10n code if needed
if [ -f "pubspec.yaml" ] && grep -q "riverpod_generator\|build_runner" pubspec.yaml 2>/dev/null; then
    echo "Running build_runner..."
    dart run build_runner build --delete-conflicting-outputs 2>/dev/null || true
fi

# ─── STEP 3: IPA Build ───────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────────────────"
echo "  STEP 3/3: Building IPA"
echo "────────────────────────────────────────────────────────────"

case "$BUILD_TYPE" in
    unsigned)
        echo "Building unsigned IPA (for SideStore/AltStore)..."
        flutter build ios --no-codesign --release 2>&1 | tail -5
        
        FLUTTER_OUTPUT="$PROJECT_DIR/build/ios/iphoneos/Runner.app"
        if [ -d "$FLUTTER_OUTPUT" ]; then
            # Create IPA manually (unsigned - works with SideStore)
            IPA_DIR="$PROJECT_DIR/build/ios/ipa"
            mkdir -p "$IPA_DIR/Payload"
            cp -R "$FLUTTER_OUTPUT" "$IPA_DIR/Payload/Runner.app"
            cd "$IPA_DIR"
            zip -qr "$PROJECT_DIR/build/ios/SpotiFLAC-unsigned.ipa" Payload/
            cd "$PROJECT_DIR"
            rm -rf "$IPA_DIR"
            
            IPA_SIZE=$(du -h "$PROJECT_DIR/build/ios/SpotiFLAC-unsigned.ipa" | cut -f1)
            echo -e "${GREEN}IPA BUILT SUCCESSFULLY${NC}"
            echo ""
            echo "  File: build/ios/SpotiFLAC-unsigned.ipa"
            echo "  Size: $IPA_SIZE"
            echo ""
            echo "  Install via SideStore/AltStore:"
            echo "    1. Upload the IPA to a web server or transfer to iPhone"
            echo "    2. In SideStore: Browse → + → paste IPA URL"
            echo "    3. Valid for 7 days (free Apple ID)"
        else
            echo -e "${RED}Flutter build failed - Runner.app not found${NC}"
            exit 1
        fi
        ;;
        
    appstore)
        echo "Building App Store IPA..."
        echo -e "${YELLOW}Make sure to set your team ID in ios/Runner.xcodeproj${NC}"
        flutter build ipa --release 2>&1 | tail -10
        
        if [ -f "$PROJECT_DIR/build/ios/ipa/"*.ipa ]; then
            echo -e "${GREEN}App Store IPA built${NC}"
            ls -lh "$PROJECT_DIR/build/ios/ipa/"*.ipa
        else
            echo -e "${RED}IPA build failed${NC}"
            exit 1
        fi
        ;;
        
    *)
        echo -e "${RED}Unknown build type: $BUILD_TYPE${NC}"
        echo "Usage: $0 [unsigned|appstore]"
        exit 1
        ;;
esac

echo ""
echo "============================================================"
echo "  BUILD COMPLETE"
echo "============================================================"
echo ""
echo "Files created:"
echo "  go_backend → ios/Frameworks/Gobackend.xcframework"
if [ "$BUILD_TYPE" = "unsigned" ]; then
    echo "  IPA        → build/ios/SpotiFLAC-unsigned.ipa"
fi
echo ""
echo "Features included in this build:"
echo "  ✅ Progressive FLAC streaming (play while downloading)"
echo "  ✅ Background preloading (N+1, N+2 ready before track ends)"
echo "  ✅ Hybrid mode (lossy Opus → FLAC auto-switch)"
echo "  ✅ Apple Music-style UI (4 tabs, blurred player, lyrics)"
echo "  ✅ Extension-based download providers (Tidal, Qobuz, Deezer)"
