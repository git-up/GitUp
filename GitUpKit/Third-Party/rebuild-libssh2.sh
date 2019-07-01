#!/bin/sh -ex -o pipefail

VERSION="1.8.0"

OSX_MIN_VERSION="10.10"
OSX_ARCHS="x86_64"

IOS_MIN_VERSION="8.0"
IOS_SIMULATOR_ARCHS="i386 x86_64"
IOS_DEVICE_ARCHS="armv7 arm64"

DEVELOPER_DIR=`xcode-select --print-path`

function build_arch_library() {
  local PLATFORM="$1"
  local ARCH="$2"
  local PREFIX="$3"
  local DEVROOT="$DEVELOPER_DIR/Platforms/$PLATFORM.platform/Developer"
  local SDKROOT="$DEVROOT/SDKs/$PLATFORM.sdk"

  # Find tools
  export CC=`xcrun -find clang`
  export CPP="$CC -E"
  export CXX=`xcrun -find clang++`
  export CXXCPP="$CC -E"
  export LD=`xcrun -find ld`
  export AR=`xcrun -find ar`
  export RANLIB=`xcrun -find ranlib`
  export LIPO=`xcrun -find lipo`
  export STRIP=`xcrun -find strip`
  export CC_FOR_BUILD=`$CC`

  # Override tools to compile for SDK
  CC_FLAGS="-isysroot $SDKROOT -arch $ARCH"
  LD_FLAGS="-isysroot $SDKROOT -arch $ARCH"
  if [[ "$PLATFORM" == "MacOSX" ]]; then
    CC_FLAGS="$CC_FLAGS -mmacosx-version-min=$OSX_MIN_VERSION"
  elif [[ "$PLATFORM" == "iPhoneSimulator" ]]; then
    CC_FLAGS="$CC_FLAGS -mios-simulator-version-min=$IOS_MIN_VERSION"
  elif [[ "$PLATFORM" == "iPhoneOS" ]]; then
    CC_FLAGS="$CC_FLAGS -fembed-bitcode -miphoneos-version-min=$IOS_MIN_VERSION"
  else
    exit 1
  fi
  export CC="$CC $CC_FLAGS $EXTRA_CFLAGS"
  export CPP="$CPP $CC_FLAGS $EXTRA_CFLAGS"
  export CXX="$CXX $CC_FLAGS $EXTRA_CFLAGS"
  export CXXCPP="$CXXCPP $CC_FLAGS $EXTRA_CFLAGS"
  export LD="$LD $LD_FLAGS"

  if [[ "$ARCH" == "x86_64" || "$ARCH" == "i386" ]]; then
    HOST="i386-apple-darwin"
  elif [[ "$ARCH" == "arm64" || "$ARCH" == "armv7" ]]; then
    HOST="arm-apple-darwin"
  else
    exit 1
  fi
  
  ./configure --prefix="$PREFIX" --host="$HOST" --disable-shared --disable-debug --disable-examples-build --with-libz --with-openssl --with-libssl-prefix="`pwd`/../../libssl/$PLATFORM"
  make install
  make clean
}

function build_fat_library() {
  local PLATFORM="$1"
  local ARCHS="$2"
  local DESTINATION="$3"
  local LIPO=`xcrun -find lipo`
  local STRIP=`xcrun -find strip`

  rm -rf "$DESTINATION"
  mkdir -p "$DESTINATION"
  for ARCH in $ARCHS; do
    local PREFIX="$TMPDIR/$PLATFORM-$ARCH"

    rm -rf "$PREFIX"
    build_arch_library "$PLATFORM" "$ARCH" "$PREFIX"

    if [[ ! -d "$DESTINATION/include" ]]; then
      mv "$PREFIX/include" "$DESTINATION/include"
    fi
    
    mkdir -p "$DESTINATION/lib"
    pushd "$PREFIX/lib"
    for LIBRARY in *.a; do
      if [[ -L "$LIBRARY" ]]; then  # Preserve symbolic link as-is
        if [[ ! -e "$DESTINATION/lib/$LIBRARY" ]]; then
          mv "$LIBRARY" "$DESTINATION/lib/$LIBRARY"
        fi
      else
        $STRIP -S -o "$LIBRARY~" "$LIBRARY"  # Strip debugging symbols
        mv -f "$LIBRARY~" "$LIBRARY"
        if [[ -e "$DESTINATION/lib/$LIBRARY" ]]; then
          $LIPO -create "$DESTINATION/lib/$LIBRARY" "$LIBRARY" -output "$DESTINATION/lib/$LIBRARY"
        else
          mv "$LIBRARY" "$DESTINATION/lib/$LIBRARY"
        fi
      fi
    done
    popd
    
    rm -rf "$PREFIX"
  done
}

function build_library() {
  local DESTINATION="$1"

  build_fat_library "MacOSX" "$OSX_ARCHS" "$DESTINATION/MacOSX"
  build_fat_library "iPhoneSimulator" "$IOS_SIMULATOR_ARCHS" "$DESTINATION/iPhoneSimulator"
  build_fat_library "iPhoneOS" "$IOS_DEVICE_ARCHS" "$DESTINATION/iPhoneOS"
}

DESTINATION="`pwd`/libssh2"

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
rm -rf "$DESTINATION"
build_library "$DESTINATION"
