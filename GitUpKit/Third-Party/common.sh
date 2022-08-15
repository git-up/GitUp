#!/bin/sh -ex -o pipefail

MACOS_VERSION_MIN="10.13"
MACOS_ARCHS="arm64 x86_64"

IOS_VERSION_MIN="12.0"
IOS_SIMULATOR_ARCHS="arm64 x86_64"
IOS_DEVICE_ARCHS="arm64"

PREFIXES=()

function configure_environment() {
  local PLATFORM="$1"
  local ARCH="$2"
  local XCRUN="xcrun --sdk $PLATFORM"
  local SDKROOT=`$XCRUN --show-sdk-path`

  # Find tools
  export CC=`$XCRUN -find clang`
  export CPP="$CC -E"
  export CXX=`$XCRUN -find clang++`
  export CXXCPP="$CC -E"
  export LD=`$XCRUN -find ld`
  export AR=`$XCRUN -find ar`
  export RANLIB=`$XCRUN -find ranlib`
  export LIPO=`$XCRUN -find lipo`
  export CC_FOR_BUILD=`$CC`

  # Override tools to compile for SDK
  CC_FLAGS="-isysroot $SDKROOT -arch $ARCH"
  LD_FLAGS="-isysroot $SDKROOT -arch $ARCH"
  if [[ "$PLATFORM" == "macosx" ]]; then
    CC_FLAGS="$CC_FLAGS -mmacosx-version-min=$MACOS_VERSION_MIN"
  elif [[ "$PLATFORM" == "iphonesimulator" ]]; then
    CC_FLAGS="$CC_FLAGS -mios-simulator-version-min=$IOS_VERSION_MIN"
  elif [[ "$PLATFORM" == "iphoneos" ]]; then
    CC_FLAGS="$CC_FLAGS -fembed-bitcode -mios-version-min=$IOS_VERSION_MIN"
  else
    exit 1
  fi
  export CFLAGS="$CC_FLAGS $EXTRA_CFLAGS"
  export LDFLAGS="$LD_FLAGS $EXTRA_LDFLAGS"
}

function build_fat_library() {
  local PLATFORM="$1"
  local ARCHS="$2"
  local DESTINATION="$3/$PLATFORM"
  local LIPO=`xcrun -find lipo`

  mkdir -p "$DESTINATION"
  for ARCH in $ARCHS; do
    local PREFIX="$3/$PLATFORM/$ARCH"

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
        if [[ -e "$DESTINATION/lib/$LIBRARY" ]]; then
          $LIPO -create "$DESTINATION/lib/$LIBRARY" "$LIBRARY" -output "$DESTINATION/lib/$LIBRARY"
        else
          mv "$LIBRARY" "$DESTINATION/lib/$LIBRARY"
        fi
      fi
    done
    popd
  done

  PREFIXES+=("$DESTINATION")
}

function build_xcframework() {
  local DESTINATION="$1"
  local TARGETS=($2)
  local NAME="${TARGETS[0]}"

  for TARGET in "${TARGETS[@]}"; do
    local XCFRAMEWORK="$DESTINATION/$TARGET.xcframework"
    local XCODEBUILD_ARGUMENTS=("-create-xcframework" "-output" "$XCFRAMEWORK")

    rm -rf "$XCFRAMEWORK"
    for PREFIX in "${PREFIXES[@]}"; do
      XCODEBUILD_ARGUMENTS+=("-library" "$PREFIX/lib/$TARGET.a")
      echo "$TARGET $NAME"
      if [[ "$TARGET" == "$NAME" ]]; then
        XCODEBUILD_ARGUMENTS+=("-headers" "$PREFIX/include")
      fi
    done
    xcodebuild "${XCODEBUILD_ARGUMENTS[@]}"
  done
}

function build_libraries() {
  local DESTINATION="$1"
  local TARGETS="${@:2}"
  local ROOT="`mktemp -d`"

  build_fat_library "macosx" "$MACOS_ARCHS" "$ROOT"
  build_fat_library "iphonesimulator" "$IOS_SIMULATOR_ARCHS" "$ROOT"
  build_fat_library "iphoneos" "$IOS_DEVICE_ARCHS" "$ROOT"
  build_xcframework "$DESTINATION" "${TARGETS[@]}"
  rm -rf "$ROOT"
}
