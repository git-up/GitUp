#!/bin/sh
set -ex

VERSION="1.5.0"

source "rebuild-functions.sh"

# Download source
rm -f "libssh2-$VERSION.tar.gz"
curl -O "http://www.libssh2.org/download/libssh2-$VERSION.tar.gz"

# Extract source
rm -rf "libssh2-$VERSION"
tar -xvf "libssh2-$VERSION.tar.gz"

# Build library
pushd "libssh2-$VERSION"
EXTRA_CONFIGURE_OPTIONS="--disable-debug --with-openssl --with-libz"
build_library_macosx "libssh2" "`pwd`/.."
EXTRA_CONFIGURE_OPTIONS="$EXTRA_CONFIGURE_OPTIONS --with-libssl-prefix=`pwd`/../libopenssl"  # Use local libssl on iOS
build_library_iphonesimulator "libssh2" "`pwd`/.."
build_library_iphoneos "libssh2" "`pwd`/.."
popd

# Clean up
rm -rf "libssh2-$VERSION"
rm -f "libssh2-$VERSION.tar.gz"
