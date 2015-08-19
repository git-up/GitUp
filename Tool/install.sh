#!/bin/sh -ex

TOOL_PATH="$1"
INSTALL_PATH="$2"
INSTALL_DIR=`dirname "$INSTALL_PATH"`

mkdir -p "$INSTALL_DIR"
ln -sf "$TOOL_PATH" "$INSTALL_PATH"

grep -q gitup-completion /etc/bashrc || cat << EOF >> /etc/bashrc
gitup="${TOOL_PATH}-completion.sh"; [ -f "\${gitup}" ] && source "\${gitup}"
EOF

printf "OK"
