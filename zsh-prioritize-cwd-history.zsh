# Scope history to the current working directory.
# Idea from https://github.com/jimhester/per-directory-history
# https://github.com/ericfreese/zsh-cwd-history
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

# How it works
#
# Every command is also appended to a per-directory file (cwdhist-<md5 of
# the directory>).  After a directory change, the in-memory history list is
# rebuilt: `fc -p` pushes a fresh list read from $HISTFILE and `fc -R`
# appends the entries of the current directory, so they come up first on
# UP-arrow and in searches.
#
# The plugin never writes $HISTFILE.  zsh itself appends each command to it
# (INC_APPEND_HISTORY, INC_APPEND_HISTORY_TIME or SHARE_HISTORY).  Popping a
# pushed list normally saves it, which rewrites $HISTFILE through
# $HISTFILE.new and a rename; with several shells sharing $HISTFILE that
# races ("can't rename ...history.new to $HISTFILE") and aborts the command
# line.  So lists are popped with SAVEHIST=0, and the original list below
# the pushed one keeps SAVEHIST=0 so that zsh saves only once on exit.
#
# The functions set locally only the options they need, including
# no_err_exit and no_err_return, so that a failing test inside a hook never
# exits the shell.

autoload -Uz add-zsh-hook
# Timestamps in $HISTFILE, as in the per-directory files
setopt extended_history
zmodload -F zsh/datetime +p:EPOCHSECONDS 2>/dev/null
zmodload -F zsh/parameter +p:commands 2>/dev/null

# Where per-directory history files live
: ${ZSH_PRIORITIZE_CWD_HISTORY_DIR:="$HOME/.zsh_prioritize_cwd_history"}
# Max physical lines kept per directory
: ${ZSH_PRIORITIZE_CWD_HISTORY_MAX:=2000}

# 1 while a list pushed by this plugin is on the history stack (kept when
# the plugin is sourced again)
typeset -gi _zsh_pcwdh_pushed=${_zsh_pcwdh_pushed:-0}
# 1 when the history list must be rebuilt for the current directory
typeset -gi _zsh_pcwdh_stale=1
# Per-directory file of the current directory
typeset -g _zsh_pcwdh_file=

_zsh_prioritize_cwd_history_md5() {
	local out
	if (( $+commands[md5sum] )); then
		out=$(print -rn -- "$1" | command md5sum) || return 1
	elif (( $+commands[md5] )); then
		out=$(print -rn -- "$1" | command md5 -q) || return 1
	else
		print -u2 "zsh-prioritize-cwd-history: md5sum or md5 required"
		return 1
	fi
	print -r -- "${out%% *}"
}

# Create the private directory of the per-directory files.
_zsh_prioritize_cwd_history_mkdir() {
	[[ -d $ZSH_PRIORITIZE_CWD_HISTORY_DIR ]] ||
		command mkdir -p -m 700 -- "$ZSH_PRIORITIZE_CWD_HISTORY_DIR" 2>/dev/null
}

# Path of the per-directory history file of the current directory
_zsh_prioritize_cwd_history_file_for_cwd() {
	local md5
	md5=$(_zsh_prioritize_cwd_history_md5 "${PWD:A}") || return 1
	print -r -- "${ZSH_PRIORITIZE_CWD_HISTORY_DIR}/cwdhist-${md5}"
}

# Amortised trim: only when the file exceeds twice the maximum.  Lines
# before the first entry header are the tail of a cut multiline command.
_zsh_prioritize_cwd_history_trim() {
	local file=$1 tmp="$1.trim.$$"
	local -i lines
	[[ -f $file ]] || return 0
	lines=$(command wc -l < "$file" 2>/dev/null) || return 0
	(( lines > ZSH_PRIORITIZE_CWD_HISTORY_MAX * 2 )) || return 0
	{
		command tail -n "$ZSH_PRIORITIZE_CWD_HISTORY_MAX" -- "$file" |
			command sed -n '/^: [0-9]*:[0-9]*;/,$p' >| "$tmp" &&
			command mv -f -- "$tmp" "$file"
	} 2>/dev/null || command rm -f -- "$tmp"
	return 0
}

# Rebuild the history list: $HISTFILE first, then the current directory.
_zsh_prioritize_cwd_history_reload() {
	setopt local_options no_ksh_arrays no_sh_word_split unset no_err_exit no_err_return
	local histfile=$HISTFILE file n
	local pending=$ZSH_PRIORITIZE_CWD_HISTORY_DIR/.pending.$$
	local -i hs=$HISTSIZE shs=$SAVEHIST
	local -a unsaved
	_zsh_pcwdh_stale=0
	[[ -n $histfile ]] || return 0

	{
		if (( _zsh_pcwdh_pushed )); then
			# Commands zsh has not yet written to $HISTFILE (SHARE_HISTORY
			# skips a write when another shell holds the lock).  `fc -AI`
			# saves them to a private file and marks them as saved; they
			# are added to the new list below so that zsh writes them.
			if _zsh_prioritize_cwd_history_mkdir; then
				command rm -f -- "$pending"
				fc -AI "$pending"
				if [[ -s $pending ]]; then
					fc -p "$pending"
					for n in ${(onk)history}; do
						unsaved+=("$history[$n]")
					done
					SAVEHIST=0
					fc -P
				fi
				command rm -f -- "$pending" "$pending.new"
			fi
			# Pop without saving.
			SAVEHIST=0
			fc -P
			_zsh_pcwdh_pushed=0
		else
			# The original list stays below without saving.
			SAVEHIST=0
		fi
		fc -p "$histfile" "$hs" "$shs"
		_zsh_pcwdh_pushed=1

		file=$(_zsh_prioritize_cwd_history_file_for_cwd) || file=
		_zsh_pcwdh_file=$file
		if [[ -n $file && -s $file ]]; then
			_zsh_prioritize_cwd_history_trim "$file"
			fc -R "$file"
		fi
		for n in "${unsaved[@]}"; do
			print -sr -- "$n"
		done
	} always {
		# On a failed history read: never stay on the private list, never
		# leave the active list unable to save, and never abort the
		# command line.
		if [[ $HISTFILE == $pending ]]; then
			SAVEHIST=0
			fc -P
		fi
		(( SAVEHIST == 0 )) && SAVEHIST=$shs
		TRY_BLOCK_ERROR=0
	}
	return 0
}

_zsh_prioritize_cwd_history_precmd() {
	# zsh writes each command to $HISTFILE only with one of these options;
	# without them, commands would be lost when the list is replaced.
	if [[ ! -o inc_append_history && ! -o inc_append_history_time && ! -o share_history ]]; then
		setopt inc_append_history_time
	fi
	(( _zsh_pcwdh_stale )) && _zsh_prioritize_cwd_history_reload
	return 0
}

# Rebuild before the next prompt; at once if a widget changed directory,
# since no prompt follows then.
_zsh_prioritize_cwd_history_cwd_changed() {
	_zsh_pcwdh_stale=1
	(( ${+WIDGET} )) && _zsh_prioritize_cwd_history_reload
	return 0
}

# Append the command to the per-directory file.  Always returns 0 so that
# zsh's own history saving is never blocked.
_zsh_prioritize_cwd_history_addhistory() {
	setopt local_options no_ksh_arrays no_sh_word_split unset extended_glob no_err_exit no_err_return
	local cmd=${1%$'\n'} file=$_zsh_pcwdh_file line sep=$'\\\n'
	local -a lines
	[[ -n $HISTFILE && -n $cmd ]] || return 0
	# Honour what zsh itself keeps out of $HISTFILE.
	[[ -o hist_ignore_space && $cmd == ' '* ]] && return 0
	[[ -n $HISTORY_IGNORE && $cmd == ${~HISTORY_IGNORE} ]] && return 0

	if (( _zsh_pcwdh_stale )) || [[ -z $file ]]; then
		file=$(_zsh_prioritize_cwd_history_file_for_cwd) || return 0
	fi
	_zsh_prioritize_cwd_history_mkdir || return 0

	# History file format: newlines escaped by a backslash; a line ending
	# in backslashes gets a trailing space so it does not join the next.
	for line in "${(@ps:\n:)cmd}"; do
		[[ $line == *\\(\ )# ]] && line+=' '
		lines+=("$line")
	done
	print -r -- ": ${EPOCHSECONDS:-0}:0;${(pj:$sep:)lines}" >>| "$file" 2>/dev/null
	return 0
}

add-zsh-hook precmd _zsh_prioritize_cwd_history_precmd
add-zsh-hook chpwd _zsh_prioritize_cwd_history_cwd_changed
add-zsh-hook zshaddhistory _zsh_prioritize_cwd_history_addhistory
