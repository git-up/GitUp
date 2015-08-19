#!/bin/sh -e
function _gitup() {
	local cur opts
	COMPREPLY=()
	cur="${COMP_WORDS[COMP_CWORD]}"
	opts="help open map commit stash"
	COMPREPLY=($(compgen -W "$opts" -- $cur))
	return 0
}
complete -F _gitup gitup
