#!/bin/bash -ex

XCODE_SCHEME="Application"

# Run unit tests
xcodebuild test -scheme "$XCODE_SCHEME"

# Build app
xcodebuild build -scheme "$XCODE_SCHEME" -configuration "Release" "CODE_SIGN_IDENTITY="
