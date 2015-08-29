#!/bin/sh
set -ex

XCODE_OBJROOT="/tmp/GitUpKit-Build"
XCODE_SYMROOT="/tmp/GitUpKit-Products"

rm -rf "$XCODE_SYMROOT"

rm -rf "$XCODE_OBJROOT"
xcodebuild build -sdk "macosx" -scheme "GitUpKit (OSX)" -configuration "Release" "OBJROOT=$XCODE_OBJROOT" "SYMROOT=$XCODE_SYMROOT"

rm -rf "GitUpKit-MacOSX"
mkdir -p "GitUpKit-MacOSX"
mv "$XCODE_SYMROOT/Release/GitUpKit.framework" "GitUpKit-MacOSX"

rm -rf "$XCODE_OBJROOT"
xcodebuild build -sdk "iphonesimulator" -scheme "GitUpKit (iOS)" -configuration "Release" "OBJROOT=$XCODE_OBJROOT" "SYMROOT=$XCODE_SYMROOT"

rm -rf "GitUpKit-iPhoneSimulator"
mkdir -p "GitUpKit-iPhoneSimulator"
mv "$XCODE_SYMROOT/Release-iphonesimulator/GitUpKit.framework" "GitUpKit-iPhoneSimulator"

rm -rf "$XCODE_OBJROOT"
xcodebuild build -sdk "iphoneos" -scheme "GitUpKit (iOS)" -configuration "Release" "OBJROOT=$XCODE_OBJROOT" "SYMROOT=$XCODE_SYMROOT"

rm -rf "GitUpKit-iPhoneOS"
mkdir -p "GitUpKit-iPhoneOS"
mv "$XCODE_SYMROOT/Release-iphoneos/GitUpKit.framework" "GitUpKit-iPhoneOS"
