#!/bin/sh
set -ex

XCODE_OBJROOT="/tmp/GitUpKit-Build"
XCODE_SYMROOT="/tmp/GitUpKit-Products"

LIPO=$(xcrun -find lipo)

rm -rf "$XCODE_SYMROOT"

# Build for OS X
rm -rf "$XCODE_OBJROOT"
xcodebuild build -sdk "macosx" -scheme "GitUpKit (OSX)" -configuration "Release" "OBJROOT=$XCODE_OBJROOT" "SYMROOT=$XCODE_SYMROOT"

# Build for iPhone Simulator
rm -rf "$XCODE_OBJROOT"
xcodebuild build -sdk "iphonesimulator" -scheme "GitUpKit (iOS)" -configuration "Release" "OBJROOT=$XCODE_OBJROOT" "SYMROOT=$XCODE_SYMROOT"

# Build for iOS
rm -rf "$XCODE_OBJROOT"
xcodebuild build -sdk "iphoneos" -scheme "GitUpKit (iOS)" -configuration "Release" "OBJROOT=$XCODE_OBJROOT" "SYMROOT=$XCODE_SYMROOT"

# Copy for OS X
rm -rf "GitUpKit-OSX"
mkdir -p "GitUpKit-OSX"
mv "$XCODE_SYMROOT/Release/GitUpKit.framework" "GitUpKit-OSX"

# Copy for iOS (universal simulator & device)
rm -rf "GitUpKit-iOS"
mkdir -p "GitUpKit-iOS"
mv "$XCODE_SYMROOT/Release-iphonesimulator/GitUpKit.framework" "GitUpKit-iOS"
$LIPO -create "GitUpKit-iOS/GitUpKit.framework/GitUpKit" "$XCODE_SYMROOT/Release-iphoneos/GitUpKit.framework/GitUpKit" -output "GitUpKit-iOS/GitUpKit.framework/GitUpKit~"
mv -f "GitUpKit-iOS/GitUpKit.framework/GitUpKit~" "GitUpKit-iOS/GitUpKit.framework/GitUpKit"
