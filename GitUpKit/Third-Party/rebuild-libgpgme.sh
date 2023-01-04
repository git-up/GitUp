#!/usr/bin/env bash

LIBGPG_ERROR_VERSION=${LIBGPG_ERROR_VERSION:-"gpgrt-1.45"}
LIBASSUAN_VERSION=${LIBASSUAN_VERSION:-"libassuan-2.5.5"}
GPGME_VERSION=${GPGME_VERSION:-"gpgme-1.18.0"}

rm -rf build || true
mkdir build

cd build || exit

echo "Clone repositories"
git clone git://git.gnupg.org/libgpg-error.git 2>/dev/null
git clone git://git.gnupg.org/libassuan.git 2>/dev/null &
LIBASSUAN_PID=$!
git clone git://git.gnupg.org/gpgme.git 2>/dev/null &
GPGME_PID=$!

export CFLAGS="-arch x86_64 -arch arm64 -mmacosx-version-min=10.13"
echo -e "\033[33m""Building libgpg-error""\033[0m"
echo "Build log in build/libgpg-error.log"
(
    pushd libgpg-error || exit
    git checkout "$LIBGPG_ERROR_VERSION"
    ./autogen.sh
    ./configure --prefix="$(pwd)/../" --disable-shared --enable-static --disable-doc --disable-tests --enable-install-gpg-error-config
    make install
    popd || exit
) > libgpg-error.log 2>&1

echo -e "\033[33m""Building libassuan""\033[0m"
echo "Build log in build/libassuan.log"
wait $LIBASSUAN_PID
(
    pushd libassuan || exit
    git checkout "$LIBASSUAN_VERSION"
    ./autogen.sh
    ./configure --with-libgpg-error-prefix="$(pwd)/../" \
                --prefix="$(pwd)/../" --disable-shared --enable-static --disable-doc --disable-tests
    make install
    popd || exit
) > libassuan.log 2>&1

echo -e "\033[33m""Building gpgme""\033[0m"
echo "Build log in build/gpgme.log"
(
    wait $GPGME_PID
    pushd gpgme || exit
    git checkout "$GPGME_VERSION"
    ./autogen.sh
    ./configure --with-libgpg-error-prefix="$(pwd)/../" \
                --with-libassuan-prefix="$(pwd)/../" \
                --prefix="$(pwd)/../" --disable-shared --enable-static --disable-doc --disable-tests
    make install
    popd || exit
) > gpgme.log 2>&1

echo "Combine static libraries into one"
libtool -static -o libgpgme.a lib/libgpg-error.a lib/libassuan.a lib/libgpgme.a

echo "Create xcframework"
xcodebuild -create-xcframework \
    -library libgpgme.a \
    -headers include \
    -output libgpgme.xcframework

echo "Set version to XCFramework"
/usr/libexec/PlistBuddy -c "Add :LibGPGErrorVersion string" libgpgme.xcframework/Info.plist
/usr/libexec/PlistBuddy -c "Set :LibGPGErrorVersion $LIBGPG_ERROR_VERSION" libgpgme.xcframework/Info.plist

/usr/libexec/PlistBuddy -c "Add :LibAssuanVersion string" libgpgme.xcframework/Info.plist
/usr/libexec/PlistBuddy -c "Set :LibAssuanVersion $LIBASSUAN_VERSION" libgpgme.xcframework/Info.plist

/usr/libexec/PlistBuddy -c "Add :GPGMeVersion string" libgpgme.xcframework/Info.plist
/usr/libexec/PlistBuddy -c "Set :GPGMeVersion $GPGME_VERSION" libgpgme.xcframework/Info.plist

if [ -d "../libgpgme.xcframework" ]; then
    rm -rf "../libgpgme.xcframework"
fi
mv libgpgme.xcframework ../

