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

##### Tag build

git tag -f "b$VERSION"
git push -f origin "b$VERSION"

##### Upload to S3 and update Appcast

FULL_PRODUCT_NAME="$PRODUCT_NAME.app"
PRODUCT_PATH="`pwd`/build/$PRODUCT_NAME/$FULL_PRODUCT_NAME"  # Must be absolute path
INFO_PLIST_PATH="$PRODUCT_PATH/Contents/Info.plist"
VERSION_ID=`defaults read "$INFO_PLIST_PATH" "CFBundleVersion"`
VERSION_STRING=`defaults read "$INFO_PLIST_PATH" "CFBundleShortVersionString"`
MIN_OS=`defaults read "$INFO_PLIST_PATH" "LSMinimumSystemVersion"`

ARCHIVE_NAME="$PRODUCT_NAME.zip"
BACKUP_ARCHIVE_NAME="$PRODUCT_NAME-$VERSION_ID.zip"
APPCAST_URL="https://s3-us-west-2.amazonaws.com/gitup-builds/$CHANNEL/$APPCAST_NAME"
ARCHIVE_URL="https://s3-us-west-2.amazonaws.com/gitup-builds/$CHANNEL/$ARCHIVE_NAME"
BACKUP_ARCHIVE_URL="https://s3-us-west-2.amazonaws.com/gitup-builds/$CHANNEL/$BACKUP_ARCHIVE_NAME"

ARCHIVE_PATH="build/$ARCHIVE_NAME"
APPCAST_PATH="GitUp/SparkleAppcast.xml"

ditto -c -k --keepParent "$PRODUCT_PATH" "$ARCHIVE_PATH"

ARCHIVE_SIZE=`stat -f "%z" "$ARCHIVE_PATH"`

EDITED_APPCAST_PATH="build/appcast.xml"
perl -p -e "s|__APPCAST_TITLE__|$PRODUCT_NAME|g;s|__APPCAST_URL__|$APPCAST_URL|g;s|__VERSION_ID__|$VERSION_ID|g;s|__VERSION_STRING__|$VERSION_STRING|g;s|__ARCHIVE_URL__|$ARCHIVE_URL|g;s|__ARCHIVE_SIZE__|$ARCHIVE_SIZE|g;s|__MIN_OS__|$MIN_OS|g" "$APPCAST_PATH" > "$EDITED_APPCAST_PATH"

aws s3 cp "$ARCHIVE_PATH" "s3://gitup-builds/$CHANNEL/$BACKUP_ARCHIVE_NAME"
aws s3 cp "s3://gitup-builds/$CHANNEL/$BACKUP_ARCHIVE_NAME" "s3://gitup-builds/$CHANNEL/$ARCHIVE_NAME"
aws s3 cp "$EDITED_APPCAST_PATH" "s3://gitup-builds/$CHANNEL/$APPCAST_NAME"
