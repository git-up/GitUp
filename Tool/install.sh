#!/bin/sh -ex

TOOL_PATH="$1"
INSTALL_PATH="$2"
INSTALL_DIR=`dirname "$INSTALL_PATH"`

mkdir -p "$INSTALL_DIR"
ln -sf "$TOOL_PATH" "$INSTALL_PATH"

# Check if gitup-completion is present in /etc/bashrc ( grep -q ...),
# otherwise (grep || ...) add our completion loading script to /etc/bashrc
# more info on here documents: http://tldp.org/LDP/abs/html/here-docs.html
grep -q gitup-completion /etc/bashrc || cat << EOF >> /etc/bashrc
# load gitup-completion.sh if it exists; enables command line completion
gitup="${TOOL_PATH}-completion.sh"; [ -f "\${gitup}" ] && source "\${gitup}"
EOF

printf "OK"
