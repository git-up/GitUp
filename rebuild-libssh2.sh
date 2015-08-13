#!/bin/sh
set -ex

VERSION="1.5.0"
DESTINATION="`pwd`/libssh2"

# Download source
rm -f "libssh2-$VERSION.tar.gz"
curl -O "http://www.libssh2.org/download/libssh2-$VERSION.tar.gz"

# Extract source
rm -rf "libssh2-$VERSION"
tar -xvf "libssh2-$VERSION.tar.gz"

# Build
rm -rf "$DESTINATION"
pushd "libssh2-$VERSION"
export MACOSX_DEPLOYMENT_TARGET=10.8
./configure --prefix="$DESTINATION" --disable-debug --with-openssl --with-libz --enable-static --disable-shared
make -j4
make install
popd
rm -rf "$DESTINATION/share"
rm -rf "$DESTINATION/lib/libssh2.la"
rm -rf "$DESTINATION/lib/pkgconfig"

# Clean up
rm -rf "libssh2-$VERSION"
rm -f "libssh2-$VERSION.tar.gz"
