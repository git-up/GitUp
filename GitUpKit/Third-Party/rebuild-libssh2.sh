#!/bin/sh -ex -o pipefail

VERSION="1.9.0"
DIRNAME="`pwd`"

. ./common.sh

function build_arch_library() {
  local PLATFORM="$1"
  local ARCH="$2"
  local PREFIX="$3"

  if [[ "$PLATFORM" == "macosx" ]]; then
    XCFRAMEWORK_SUBDIR="macos-${MACOS_ARCHS// /_}"
  elif [[ "$PLATFORM" == "iphonesimulator" ]]; then
    XCFRAMEWORK_SUBDIR="ios-${IOS_SIMULATOR_ARCHS// /_}-simulator"
  elif [[ "$PLATFORM" == "iphoneos" ]]; then
    XCFRAMEWORK_SUBDIR="ios-${IOS_DEVICE_ARCHS// /_}"
  else
    exit 1
  fi
  LIBSSL_PREFIX="$DIRNAME/libssl.xcframework/$XCFRAMEWORK_SUBDIR"
  LIBCRYPTO_PREFIX="$DIRNAME/libcrypto.xcframework/$XCFRAMEWORK_SUBDIR"
  EXTRA_LDFLAGS="-L$LIBSSL_PREFIX -L$LIBCRYPTO_PREFIX"
  EXTRA_CFLAGS="-I$LIBSSL_PREFIX/Headers -I$LIBCRYPTO_PREFIX/Headers"

  if [[ "$ARCH" == "x86_64" ]]; then
    HOST="x86_64-apple-darwin"
  elif [[ "$ARCH" == "arm64" ]]; then
    HOST="arm-apple-darwin"
  else
    exit 1
  fi

  configure_environment "$PLATFORM" "$ARCH"

  ./configure --prefix="$PREFIX" --host="$HOST" --disable-shared --disable-debug --disable-examples-build --with-libz --with-crypto=openssl
  make install
  make clean
}

# Setup
mkdir -p "build"
cd "build"
if [[ ! -f "libssh2-$VERSION.tar.gz" ]]; then
  curl -sfLO "http://www.libssh2.org/download/libssh2-$VERSION.tar.gz"
fi
rm -rf "libssh2-$VERSION"
tar -xvf "libssh2-$VERSION.tar.gz"

# Build
cd "libssh2-$VERSION"
build_libraries "$DIRNAME" "libssh2"
