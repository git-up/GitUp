#!/bin/sh
set -ex

VERSION="3080900"
DESTINATION="`pwd`/libsqlite3"

# Download source
rm -f "sqlite-autoconf-$VERSION.tar.gz"
curl -O "http://www.sqlite.org/2015/sqlite-autoconf-$VERSION.tar.gz"

# Extract source
rm -rf "sqlite-autoconf-$VERSION"
tar -xvf "sqlite-autoconf-$VERSION.tar.gz"

# Patch configure so that SQLITE_THREADSAFE=2 instead of SQLITE_THREADSAFE=1
/usr/bin/perl -p -e "s/SQLITE_THREADSAFE=1/SQLITE_THREADSAFE=2/g" "sqlite-autoconf-$VERSION/configure" > "sqlite-autoconf-$VERSION/configure~"
/bin/mv -f "sqlite-autoconf-$VERSION/configure~" "sqlite-autoconf-$VERSION/configure"
chmod a+x "sqlite-autoconf-$VERSION/configure"

# Build
rm -rf "$DESTINATION"
pushd "sqlite-autoconf-$VERSION"
export MACOSX_DEPLOYMENT_TARGET=10.8
./configure --prefix="$DESTINATION" --enable-static --disable-shared CFLAGS="-DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS"
make -j4
make install
popd
rm -rf "$DESTINATION/bin"
rm -rf "$DESTINATION/share"
rm -rf "$DESTINATION/lib/libsqlite3.la"
rm -rf "$DESTINATION/lib/pkgconfig"

# Clean up
rm -rf "sqlite-autoconf-$VERSION"
rm -f "sqlite-autoconf-$VERSION.tar.gz"
