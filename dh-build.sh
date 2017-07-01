#!/bin/sh -ex

PRODUCT_NAME="GitUp"

MAX_VERSION=`git tag -l "dh*" | sed 's/dh//g' | sort -nr | head -n 1`
VERSION=$((MAX_VERSION + 1))

##### Archive and export app

rm -rf "build"
pushd "GitUp"
xcodebuild archive -scheme "Application" -archivePath "../build/$PRODUCT_NAME.xcarchive" "BUNDLE_VERSION=$VERSION"
xcodebuild -exportArchive -exportOptionsPlist "Export-Options.plist" -archivePath "../build/$PRODUCT_NAME.xcarchive" -exportPath "../build/$PRODUCT_NAME"
popd

##### Tag build

git tag -f "dh$VERSION"
