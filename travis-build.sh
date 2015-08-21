#!/bin/bash -ex

# Run GitUpKit unit tests
pushd "GitUpKit"
xcodebuild test -scheme "GitUpKit"  # We can't use xctool here because customized GIGraphTests
popd

# Build GitUp without signing
pushd "GitUp"
xctool build -scheme "Application" -configuration "Release" "CODE_SIGN_IDENTITY="
popd
