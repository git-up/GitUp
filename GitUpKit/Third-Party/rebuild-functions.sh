#!/bin/sh

OSX_MIN_VERSION="10.8"
OSX_ARCHS="x86_64 i386"

IOS_MIN_VERSION="8.0"
IOS_SIMULATOR_ARCHS="i386 x86_64"
IOS_DEVICE_ARCHS="armv7 arm64"

IOS_SDK_VERSION=`xcodebuild -version -sdk | grep -A 1 '^iPhone' | tail -n 1 |  awk '{ print $2 }'`
OSX_SDK_VERSION=`xcodebuild -version -sdk | grep -A 1 '^MacOSX' | tail -n 1 |  awk '{ print $2 }'`
DEVELOPER_DIR=`xcode-select --print-path`

function build_library_arch () {
  local LIBRARY="$1"
  local DESTINATION="$2"
  local PLATFORM="$3"
  local ARCH="$4"

  local PREFIX="$DESTINATION-$ARCH"
  local LOG="$PREFIX.log"

  # Find SDK
  export DEVROOT="$DEVELOPER_DIR/Platforms/$PLATFORM.platform/Developer"
  if [ "$PLATFORM" == "MacOSX" ]
  then
    export SDKROOT="$DEVROOT/SDKs/$PLATFORM$OSX_SDK_VERSION.sdk"
  else
    export SDKROOT="$DEVROOT/SDKs/$PLATFORM$IOS_SDK_VERSION.sdk"
  fi

  # Find tools
  export CC=`xcrun -find clang`
  export CPP="$CC -E"
  export LD=`xcrun -find ld`
  export AR=`xcrun -find ar`
  export RANLIB=`xcrun -find ranlib`
  export LIPO=$(xcrun -find lipo)

  # Set up build environment
  export CFLAGS="-arch $ARCH -isysroot $SDKROOT -I$SDKROOT/usr/include"
  export LDFLAGS="-arch $ARCH -isysroot $SDKROOT -L$SDKROOT/usr/lib"
  if [ "$PLATFORM" == "MacOSX" ]
  then
    export CFLAGS="$CFLAGS -mmacosx-version-min=$OSX_MIN_VERSION"
    export LDFLAGS="$LDFLAGS -mmacosx-version-min=$OSX_MIN_VERSION"
  elif [ "$PLATFORM" == "iPhoneSimulator" ]
  then
    export CFLAGS="$CFLAGS -mios-simulator-version-min=$IOS_MIN_VERSION"
    export LDFLAGS="$LDFLAGS -mios-simulator-version-min=$IOS_MIN_VERSION"
  elif [ "$PLATFORM" == "iPhoneOS" ]
  then
    export CFLAGS="$CFLAGS -miphoneos-version-min=$IOS_MIN_VERSION"
    export LDFLAGS="$LDFLAGS -miphoneos-version-min=$IOS_MIN_VERSION"
  fi
  export CFLAGS="$CFLAGS $EXTRA_CFLAGS"
  export CPPFLAGS="$CFLAGS"
  if [ "$ARCH" == "x86_64" ]
  then
    HOST="i386"
  elif [ "$ARCH" == "arm64" ]
  then
    HOST="arm"
  else
    HOST="$ARCH"
  fi

  # Configure and build
  rm -f "$LOG"
  touch "$LOG"
  rm -rf "$PREFIX"
  ./configure \
    --prefix="$PREFIX" \
    --host=$HOST-apple-darwin \
    --enable-static \
    --disable-shared \
    $EXTRA_CONFIGURE_OPTIONS > "$LOG"
  make -j4 > "$LOG"
  make install > "$LOG"
  make clean > "$LOG"

  # Combine
  if [ -e "$DESTINATION/lib/$LIBRARY.a" ]
  then
    $LIPO -create "$DESTINATION/lib/$LIBRARY.a" "$PREFIX/lib/$LIBRARY.a" -output "$DESTINATION/lib/$LIBRARY.a"
  else
    mv "$PREFIX/include" "$DESTINATION/include"
    mkdir "$DESTINATION/lib"
    mv "$PREFIX/lib/$LIBRARY.a" "$DESTINATION/lib/$LIBRARY.a"
  fi

  # Clean up
  rm -rf "$PREFIX"
  rm -f "$LOG"
}

function build_library_platform () {
  local LIBRARY="$1"
  local PREFIX="$2"
  local PLATFORM="$3"
  local ARCHS="$4"

  local PREFIX="$PREFIX/$LIBRARY-$PLATFORM"

  # Build each arch for the platform
  rm -rf "$PREFIX"
  mkdir -p "$PREFIX"
  for ARCH in ${ARCHS}
  do
    build_library_arch "$LIBRARY" "$PREFIX" "$PLATFORM" "$ARCH"
  done
}

function build_library_macosx () {
  local LIBRARY="$1"
  local PREFIX="$2"

  build_library_platform "$LIBRARY" "$PREFIX" "MacOSX" "$OSX_ARCHS"
}

function build_library_iphonesimulator () {
  local LIBRARY="$1"
  local PREFIX="$2"

  build_library_platform "$LIBRARY" "$PREFIX" "iPhoneSimulator" "$IOS_SIMULATOR_ARCHS"
}

function build_library_iphoneos () {
  local LIBRARY="$1"
  local PREFIX="$2"

  build_library_platform "$LIBRARY" "$PREFIX" "iPhoneOS" "$IOS_DEVICE_ARCHS"
}
