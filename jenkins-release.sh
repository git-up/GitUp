#!/bin/sh
set -ex

VERSION="$1"
CHANNEL="$2"
if [ "$VERSION" == "" ] || [ "$CHANNEL" == "" ]; then
  echo "Usage $0 version channel"
  exit 1
fi

PRODUCT_NAME="GitUp"
APPCAST_NAME="appcast.xml"

FULL_PRODUCT_NAME="$PRODUCT_NAME.app"
ARCHIVE_NAME="$PRODUCT_NAME.zip"
BACKUP_ARCHIVE_NAME="$PRODUCT_NAME-$VERSION.zip"

APPCAST_URL="https://s3-us-west-2.amazonaws.com/gitup-builds/$CHANNEL/$APPCAST_NAME"
ARCHIVE_URL="https://s3-us-west-2.amazonaws.com/gitup-builds/$CHANNEL/$ARCHIVE_NAME"

ARCHIVE_PATH="$TMPDIR/$ARCHIVE_NAME"
PAYLOAD_PATH="$TMPDIR/payload"
APPCAST_PATH="GitUp/SparkleAppcast.xml"

##### Download build

/usr/local/bin/aws s3 cp "s3://gitup-builds/continuous/GitUp-$VERSION.zip" "$ARCHIVE_PATH"

ARCHIVE_SIZE=`stat -f "%z" "$ARCHIVE_PATH"`

##### Examine app

rm -rf "$PAYLOAD_PATH"
ditto -x -k "$ARCHIVE_PATH" "$PAYLOAD_PATH"

INFO_PLIST_PATH="$PAYLOAD_PATH/$FULL_PRODUCT_NAME/Contents/Info.plist"
VERSION_ID=`defaults read "$INFO_PLIST_PATH" "CFBundleVersion"`
VERSION_STRING=`defaults read "$INFO_PLIST_PATH" "CFBundleShortVersionString"`
MIN_OS=`defaults read "$INFO_PLIST_PATH" "LSMinimumSystemVersion"`
if [ "$VERSION_ID" != "$VERSION" ]; then
  exit 1
fi

INFO_PLIST_PATH="$PAYLOAD_PATH/$FULL_PRODUCT_NAME/Contents/Frameworks/GitUpKit.framework/Versions/A/Resources/Info.plist"
GIT_SHA1=`defaults read "$INFO_PLIST_PATH" "GitSHA1"`
if [ "$GIT_SHA1" == "" ]; then
  exit 1
fi

##### Upload to S3 and update Appcast

EDITED_APPCAST_PATH="$TMPDIR/appcast.xml"
/usr/bin/perl -p -e "s|__APPCAST_TITLE__|$PRODUCT_NAME|g;s|__APPCAST_URL__|$APPCAST_URL|g;s|__VERSION_ID__|$VERSION_ID|g;s|__VERSION_STRING__|$VERSION_STRING|g;s|__ARCHIVE_URL__|$ARCHIVE_URL|g;s|__ARCHIVE_SIZE__|$ARCHIVE_SIZE|g;s|__MIN_OS__|$MIN_OS|g" "$APPCAST_PATH" > "$EDITED_APPCAST_PATH"

/usr/local/bin/aws s3 cp "$ARCHIVE_PATH" "s3://gitup-builds/$CHANNEL/$BACKUP_ARCHIVE_NAME"
/usr/local/bin/aws s3 cp "s3://gitup-builds/$CHANNEL/$BACKUP_ARCHIVE_NAME" "s3://gitup-builds/$CHANNEL/$ARCHIVE_NAME"
/usr/local/bin/aws s3 cp "$EDITED_APPCAST_PATH" "s3://gitup-builds/$CHANNEL/$APPCAST_NAME"

##### Tag release

git tag -f "v$VERSION_STRING" "$GIT_SHA1"
git push -f origin "v$VERSION_STRING"

##### We're done!

echo "Success!"
