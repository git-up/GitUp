#!/bin/sh -ex -o pipefail

DIRNAME="`pwd`"

. ./common.sh

function build_arch_library() {
  local PLATFORM="$1"
  local ARCH="$2"
  local PREFIX="$3"
  local BUILD_DIR="$PREFIX-build"

  if [[ "$PLATFORM" == "macosx" ]]; then
    XCFRAMEWORK_SUBDIR="macos-${MACOS_ARCHS// /_}"
  elif [[ "$PLATFORM" == "iphonesimulator" ]]; then
    XCFRAMEWORK_SUBDIR="ios-${IOS_SIMULATOR_ARCHS// /_}-simulator"
  elif [[ "$PLATFORM" == "iphoneos" ]]; then
    XCFRAMEWORK_SUBDIR="ios-${IOS_DEVICE_ARCHS// /_}"
  else
    exit 1
  fi

  local SDKROOT="`xcrun --sdk "$PLATFORM" --show-sdk-path`"
  local DEPLOYMENT_TARGET="$IOS_VERSION_MIN"
  local REGEX_BACKEND="builtin"

  if [[ "$PLATFORM" == "macosx" ]]; then
    DEPLOYMENT_TARGET="$MACOS_VERSION_MIN"
    REGEX_BACKEND="regcomp_l"
  fi

  rm -rf "$BUILD_DIR" "$PREFIX"

  cmake -S "$DIRNAME/libgit2" -B "$BUILD_DIR" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_SYSROOT="$SDKROOT" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTS=OFF \
    -DBUILD_CLI=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_FUZZERS=OFF \
    -DUSE_SSH=exec \
    -DUSE_HTTPS=SecureTransport \
    -DUSE_SHA1=CollisionDetection \
    -DUSE_SHA256=CommonCrypto \
    -DREGEX_BACKEND="$REGEX_BACKEND" \
    -DUSE_HTTP_PARSER=builtin \
    -DPKG_CONFIG_EXECUTABLE=/usr/bin/false

  cmake --build "$BUILD_DIR" --target install --config Release
}

# Setup
mkdir -p "build"

# Build
build_libraries "$DIRNAME" "libgit2"
