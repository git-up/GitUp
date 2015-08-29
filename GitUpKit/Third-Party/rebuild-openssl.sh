#!/bin/sh
set -ex

rm -rf "build"
mkdir "build"

pushd "build"
curl -O "https://raw.githubusercontent.com/x2on/OpenSSL-for-iPhone/21c4109c4f5a9f9c7b6312472d59d849a59579d7/build-libssl.sh"  # Version 1.0.2d
chmod a+x build-libssl.sh
./build-libssl.sh
popd

rm -rf "libopenssl"
mkdir "libopenssl"
mv "build/include" "libopenssl/include"
mv "build/lib" "libopenssl/lib"

rm -rf "build"
