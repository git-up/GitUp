#!/bin/sh -ex

TOOL_PATH="$1"
INSTALL_PATH="$2"
INSTALL_DIR=`dirname "$INSTALL_PATH"`

mkdir -p "$INSTALL_DIR"
ln -sf "$TOOL_PATH" "$INSTALL_PATH"

printf "OK"
