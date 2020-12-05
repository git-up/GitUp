#!/bin/sh -ex -o pipefail

VERSION="1.1.1h"
DIRNAME="`pwd`"

. ./common.sh

function build_arch_library() {
  local PLATFORM="$1"
  local ARCH="$2"
  local PREFIX="$3"

  configure_environment "$PLATFORM" "$ARCH"

  if [[ "$PLATFORM" == "macosx" ]]; then
    if [[ "$ARCH" == "arm64" ]]; then
      CONFIGURATION="darwin64-arm64-cc"
    elif [[ "$ARCH" == "x86_64" ]]; then
      CONFIGURATION="darwin64-x86_64-cc"
    else
      exit 1
    fi
  elif [[ "$PLATFORM" == "iphonesimulator" ]]; then
    if [[ "$ARCH" == "arm64" ]]; then
      CONFIGURATION="iossimulator64-arm64-xcrun"
    elif [[ "$ARCH" == "x86_64" ]]; then
      CONFIGURATION="iossimulator64-x86_64-xcrun"
    else
      exit 1
    fi
  elif [[ "$PLATFORM" == "iphoneos" ]]; then
    if [[ "$ARCH" == "arm64" ]]; then
      CONFIGURATION="ios64-xcrun"
    else
      exit 1
    fi
  fi

  ./Configure $CONFIGURATION --prefix="$PREFIX" no-shared zlib threads no-ssl2 no-ssl3 no-dso
  make depend
  make install_sw
  make clean
}

# Setup
mkdir -p "build"
cd "build"
if [[ ! -f "openssl-$VERSION.tar.gz" ]]; then
  curl -sfLO "https://www.openssl.org/source/openssl-$VERSION.tar.gz"
fi
rm -rf "openssl-$VERSION"
tar -xvf "openssl-$VERSION.tar.gz"

# Patch
cd "openssl-$VERSION"
patch -p1 << EOF
diff --git a/Configurations/10-main.conf b/Configurations/10-main.conf
index fc9f3bbea6..d7580bf3e1 100644
--- a/Configurations/10-main.conf
+++ b/Configurations/10-main.conf
@@ -1615,6 +1615,16 @@ my %targets = (
         asm_arch         => 'x86_64',
         perlasm_scheme   => "macosx",
     },
+    "darwin64-arm64-cc" => { inherit_from => [ "darwin64-arm64" ] }, # "Historic" alias
+    "darwin64-arm64" => {
+        inherit_from     => [ "darwin-common" ],
+        CFLAGS           => add("-Wall"),
+        cflags           => add("-arch arm64"),
+        lib_cppflags     => add("-DL_ENDIAN"),
+        bn_ops           => "SIXTY_FOUR_BIT_LONG",
+        asm_arch         => 'aarch64_asm',
+        perlasm_scheme   => "ios64",
+    },

 ##### GNU Hurd
     "hurd-x86" => {
--- a/Configurations/15-ios.conf
+++ b/Configurations/15-ios.conf
@@ -32,6 +32,20 @@ my %targets = (
         inherit_from     => [ "ios-common" ],
         CC               => "xcrun -sdk iphonesimulator cc",
     },
+    "iossimulator64-x86_64-xcrun" => {
+        inherit_from     => [ "ios-common", asm("x86_64_asm") ],
+        CC               => "xcrun -sdk iphonesimulator cc",
+        cflags           => add("-arch x86_64 -mios-simulator-version-min=7.0.0 -fno-common"),
+        bn_ops           => "SIXTY_FOUR_BIT_LONG RC4_CHAR",
+        perlasm_scheme   => "macosx",
+    },
+    "iossimulator64-arm64-xcrun" => {
+        inherit_from     => [ "ios-common", asm("aarch64_asm") ],
+        CC               => "xcrun -sdk iphonesimulator cc",
+        cflags           => add("-arch arm64 -mios-simulator-version-min=7.0.0 -fno-common"),
+        bn_ops           => "SIXTY_FOUR_BIT_LONG RC4_CHAR",
+        perlasm_scheme   => "ios64",
+    },
 # It takes three prior-set environment variables to make it work:
 #
 # CROSS_COMPILE=/where/toolchain/is/usr/bin/ [note ending slash]
EOF

# Build
build_libraries "$DIRNAME" "libssl" "libcrypto"
