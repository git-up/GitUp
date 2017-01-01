#!/bin/bash -ex

# Run GitUpKit unit tests
pushd "GitUpKit"
xcodebuild test -scheme "GitUpKit (OSX)"
popd

# Build GitUp without signing
pushd "GitUp"
xcodebuild build -scheme "Application" -configuration "Release" "CODE_SIGN_IDENTITY="
popd

# Build OS X examples
pushd "Examples/GitDown"
xcodebuild build -scheme "GitDown" -sdk "macosx" -configuration "Release"
popd
pushd "Examples/GitDiff"
xcodebuild build -scheme "GitDiff" -sdk "macosx" -configuration "Release"
popd
pushd "Examples/GitY"
xcodebuild build -scheme "GitY" -sdk "macosx" -configuration "Release"
popd

# Build iOS example
pushd "Examples/iGit"
xcodebuild build -scheme "iGit" -sdk "iphonesimulator" -configuration "Release"
popd
