#!/bin/sh -ex

CHANNEL="continuous"

PRODUCT_NAME="GitUp"
APPCAST_NAME="appcast.xml"

MAX_VERSION=`git tag -l "b*" | sed 's/b//g' | sort -nr | head -n 1`
VERSION=$((MAX_VERSION + 1))

##### Archive and export app

rm -rf "build"
pushd "GitUp"
xcodebuild archive -scheme "Application" -archivePath "../build/$PRODUCT_NAME.xcarchive" "BUNDLE_VERSION=$VERSION"
xcodebuild -exportArchive -exportOptionsPlist "Export-Options.plist" -archivePath "../build/$PRODUCT_NAME.xcarchive" -exportPath "../build/$PRODUCT_NAME"
popd

FULL_PRODUCT_NAME="$PRODUCT_NAME.app"
PRODUCT_PATH="`pwd`/build/$PRODUCT_NAME/$FULL_PRODUCT_NAME"  # Must be absolute path
ARCHIVE_NAME="$PRODUCT_NAME.zip"
ARCHIVE_PATH="build/$ARCHIVE_NAME"

##### Notarize zip file

ditto -c -k --keepParent "$PRODUCT_PATH" "$ARCHIVE_PATH"

# "PersonalNotary" is the profile name assigned from `notarytool store-credentials`
xcrun notarytool submit $ARCHIVE_PATH --keychain-profile "PersonalNotary" --wait

echo "Notarization has completed"

##### Staple app and regenerate zip

xcrun stapler staple "$PRODUCT_PATH"

ditto -c -k --keepParent "$PRODUCT_PATH" "$ARCHIVE_PATH"

##### Tag build

git tag -f "b$VERSION"
git push -f origin "b$VERSION"

osascript -e 'display notification "Successfully completed continuous build" with title "GitUp Script" sound name "Hero"'
