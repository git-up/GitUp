#!/bin/sh

REMOTE_URL="git@github.com:git-up/libgit2.git"
REMOTE_BRANCH="gitup"

if [ ! -d "libgit2-repo" ]; then 
  git clone "$REMOTE_URL" "libgit2-repo"
fi
cd "libgit2-repo"
git fetch "origin"
git checkout "$REMOTE_BRANCH"
git reset --hard "origin/$REMOTE_BRANCH"

rm -rf "build"
mkdir "build"
cd "build"
export CMAKE_INCLUDE_PATH="`pwd`/../../libssh2/include"
export CMAKE_LIBRARY_PATH="`pwd`/../../libssh2/lib"
rm -rf "../../libgit2"
cmake .. "-DCMAKE_INSTALL_PREFIX=`pwd`/../../libgit2" -DCMAKE_OSX_DEPLOYMENT_TARGET=10.8 -DBUILD_SHARED_LIBS=OFF -DBUILD_CLAR=OFF -DTHREADSAFE=ON -DCURL=OFF
cmake --build . --target install

rm -rf "../../libgit2/lib/pkgconfig"
