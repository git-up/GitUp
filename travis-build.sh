#!/bin/bash -ex

XCODE_SCHEME="Application"

xcodebuild test -scheme "$XCODE_SCHEME"
