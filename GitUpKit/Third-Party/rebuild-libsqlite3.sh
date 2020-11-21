#!/bin/sh -ex -o pipefail

VERSION="3220000"
DIRNAME="`pwd`"

. ./common.sh

function build_arch_library() {
  local PLATFORM="$1"
  local ARCH="$2"
  local PREFIX="$3"

  if [[ "$ARCH" == "x86_64" ]]; then
    HOST="x86_64-apple-darwin"
  elif [[ "$ARCH" == "arm64" ]]; then
    HOST="arm-apple-darwin"
  else
    exit 1
  fi

  configure_environment "$PLATFORM" "$ARCH"

  ./configure --prefix="$PREFIX" --host="$HOST" --disable-shared --disable-dynamic-extensions
  make install-includeHEADERS
  make install-libLTLIBRARIES
  make clean
}

# Setup
mkdir -p "build"
cd "build"
if [[ ! -f "sqlite-autoconf-$VERSION.tar.gz" ]]; then
  curl -sfLO "https://www.sqlite.org/2018/sqlite-autoconf-$VERSION.tar.gz"
fi
rm -rf "sqlite-autoconf-$VERSION"
tar -xvf "sqlite-autoconf-$VERSION.tar.gz"

# Patch
cd "sqlite-autoconf-$VERSION"
perl -pi -e "s/SQLITE_THREADSAFE=1/SQLITE_THREADSAFE=2/g" "configure"  # Patch configure so that SQLITE_THREADSAFE=2 instead of SQLITE_THREADSAFE=1

# Build
EXTRA_CFLAGS="-DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS"
build_libraries "$DIRNAME" "libsqlite3"
