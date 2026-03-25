# Scope history to the current working directory.
# Idea from https://github.com/jimhester/per-directory-history
# https://github.com/ericfreese/zsh-cwd-history
# v0.4.0
# Copyright (c) 2016 Eric Freese
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

# Exit if history is disabled
[[ -n "$HISTFILE" ]] || return

# Extended history gives us timestamps for ordering
setopt EXTENDED_HISTORY

# Incremental append after each command finishes — prevents history loss
# when we reload the history list on directory change.
setopt INC_APPEND_HISTORY_TIME

# Load modules once at source time (not per-hook)
zmodload -F zsh/datetime +p:EPOCHSECONDS 2>/dev/null
zmodload -F zsh/parameter +p:commands 2>/dev/null

# Config: where per-directory history files live
: ${ZSH_PRIORITIZE_CWD_HISTORY_DIR:="$HOME/.zsh_prioritize_cwd_history"}
# Config: max lines kept per directory (physical lines; generous for multiline cmds)
: ${ZSH_PRIORITIZE_CWD_HISTORY_MAX:=2000}

# Track whether we've pushed onto the fc history stack
typeset -gi _zsh_pcwdh_pushed=0

#--------------------------------------------------------------------#
# Per-directory history files (cwdhist-<md5>)                        #
#                                                                    #
# Each file stores EXTENDED_HISTORY entries executed in that dir.    #
# On chpwd: fc -p $HISTFILE (global) then fc -R <cwdhist> (overlay) #
# → CWD commands always appear most-recent in UP-arrow / search.    #
#--------------------------------------------------------------------#

_zsh_prioritize_cwd_history_md5() {
	if (( $+commands[md5sum] )); then
		printf '%s' "$1" | command md5sum | command cut -d ' ' -f 1
	elif (( $+commands[md5] )); then
		printf '%s' "$1" | command md5 -q
	else
		print -u2 "zsh-prioritize-cwd-history: md5sum or md5 required"
		return 1
	fi
}

# Returns path to per-CWD history file
_zsh_prioritize_cwd_history_file_for_cwd() {
	local md5
	md5=$(_zsh_prioritize_cwd_history_md5 "${PWD:A}") || return 1
	print -r -- "${ZSH_PRIORITIZE_CWD_HISTORY_DIR}/cwdhist-${md5}"
}

# Amortised trim: only when file exceeds 2× max (avoids constant I/O).
# Uses PID-suffixed tmp to avoid clobbering concurrent trims.
_zsh_prioritize_cwd_history_trim() {
	local file=$1
	[[ -f $file ]] || return 0
	local -i lines
	lines=$(command wc -l < "$file" 2>/dev/null) || return 0
	(( lines > ZSH_PRIORITIZE_CWD_HISTORY_MAX * 2 )) || return 0
	local tmp="${file}.trim.$$"
	command tail -n "$ZSH_PRIORITIZE_CWD_HISTORY_MAX" "$file" >| "$tmp" && \
		command mv -f "$tmp" "$file" || \
		command rm -f "$tmp"
}

#--------------------------------------------------------------------#
# Hooks                                                              #
#--------------------------------------------------------------------#

# Initialize on first prompt, then remove itself
_zsh_prioritize_cwd_history_initialize() {
	add-zsh-hook -d precmd _zsh_prioritize_cwd_history_initialize
	_zsh_prioritize_cwd_history_cwd_changed
	add-zsh-hook zshaddhistory _zsh_prioritize_cwd_history_addhistory
	add-zsh-hook chpwd _zsh_prioritize_cwd_history_cwd_changed
}

# Reload history on directory change:
#   1. Pop previous push (skip on very first call — nothing to pop)
#   2. Push fresh global history from $HISTFILE
#   3. Overlay CWD-specific entries → they appear most-recent
_zsh_prioritize_cwd_history_cwd_changed() {
	(( _zsh_pcwdh_pushed )) && fc -P
	fc -p "$HISTFILE"
	_zsh_pcwdh_pushed=1

	local cwd_histfile
	cwd_histfile=$(_zsh_prioritize_cwd_history_file_for_cwd) || return
	[[ -s $cwd_histfile ]] || return
	_zsh_prioritize_cwd_history_trim "$cwd_histfile"
	fc -R "$cwd_histfile"
}

# Write each command to the per-CWD history file in EXTENDED_HISTORY format.
# Always returns 0 so normal history saving is never blocked.
_zsh_prioritize_cwd_history_addhistory() {
	local cwd_histfile
	cwd_histfile=$(_zsh_prioritize_cwd_history_file_for_cwd) || return 0
	[[ -d $ZSH_PRIORITIZE_CWD_HISTORY_DIR ]] || command mkdir -p "$ZSH_PRIORITIZE_CWD_HISTORY_DIR"

	# Format: `: timestamp:0;command`  (duration unknown at entry time)
	# Strip trailing newline; escape embedded newlines for multiline cmds
	local cmd=${1%%$'\n'}
	cmd=${cmd//$'\n'/$'\\\n'}
	print -r -- ": ${EPOCHSECONDS}:0;${cmd}" >>| "$cwd_histfile"
	return 0
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _zsh_prioritize_cwd_history_initialize
