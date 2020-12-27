#!/bin/bash -ex

# Run GitUpKit unit tests
pushd "GitUpKit"
xcodebuild test -scheme "GitUpKit (macOS)"
popd

# Build GitUp without signing
pushd "GitUp"
xcodebuild build -scheme "Application" -configuration "Release" "CODE_SIGN_IDENTITY=" > /dev/null
popd

# Build OS X examples
pushd "Examples/GitDown"
xcodebuild build -scheme "GitDown" -sdk "macosx" -configuration "Release" > /dev/null
popd
pushd "Examples/GitDiff"
xcodebuild build -scheme "GitDiff" -sdk "macosx" -configuration "Release" > /dev/null
popd
pushd "Examples/GitY"
xcodebuild build -scheme "GitY" -sdk "macosx" -configuration "Release" > /dev/null
popd

# Build iOS example
pushd "Examples/iGit"
xcodebuild build -scheme "iGit" -sdk "iphonesimulator" -configuration "Release" > /dev/null
popd
