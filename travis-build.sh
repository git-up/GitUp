#!/bin/bash -ex

# Run GitUpKit unit tests
pushd "GitUpKit"
xcodebuild test -scheme "GitUpKit (OSX)"  # We can't use xctool here because of customized GIGraphTests
popd

# Build GitUp without signing
pushd "GitUp"
xctool build -scheme "Application" -configuration "Release" "CODE_SIGN_IDENTITY="
popd

# Build OS X examples
pushd "Examples/GitDown"
xctool build -scheme "GitDown" -sdk "macosx" -configuration "Release"
popd
pushd "Examples/GitY"
xctool build -scheme "GitY" -sdk "macosx" -configuration "Release"
popd

# Build iOS example
pushd "Examples/iGit"
xctool build -scheme "iGit" -sdk "iphonesimulator" -configuration "Release"
popd
