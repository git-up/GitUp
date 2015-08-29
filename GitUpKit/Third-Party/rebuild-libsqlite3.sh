#!/bin/sh
set -ex

VERSION="3081101"

source "rebuild-functions.sh"

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

# Build library
pushd "sqlite-autoconf-$VERSION"
EXTRA_CFLAGS="-DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS"
build_library_macosx "libsqlite3" "`pwd`/.."
build_library_iphonesimulator "libsqlite3" "`pwd`/.."
build_library_iphoneos "libsqlite3" "`pwd`/.."
popd

# Clean up
rm -rf "sqlite-autoconf-$VERSION"
rm -f "sqlite-autoconf-$VERSION.tar.gz"
