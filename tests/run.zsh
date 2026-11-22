#!/usr/bin/env zsh
# Tests for zsh-prioritize-cwd-history.
#
# Run: zsh tests/run.zsh
#
# Each test starts real interactive shells (zsh -i reading commands from
# stdin), so hooks, history saving and locking behave as at a prompt.
# PLUGIN=<path> tests another copy of the plugin.

emulate -L zsh
setopt extended_glob

typeset -gi pass=0 fail=0
typeset -g PLUGIN=${PLUGIN:-${0:A:h:h}/zsh-prioritize-cwd-history.zsh}
typeset -g ROOT=$(command mktemp -d "${TMPDIR:-/tmp}/zsh-pcwdh-test.XXXXXXXXXX")
typeset -g T out f errs
trap "[[ -n \${KEEP:-} ]] || command rm -rf -- \$ROOT" EXIT
zmodload -F zsh/stat b:zstat

ok()  { (( ++pass )); print -r -- "  ok   $1"; }
nok() { (( ++fail )); print -r -- "  FAIL $1"; }
# <condition>; check <description>
check() {
	if (( $? == 0 )); then ok $1; else nok $1; return 1; fi
}
has() { [[ $1 == *"$2"* ]]; }

# setup <name>: fresh test directory $T with dirs a, b and a seeded $HISTFILE.
# User config goes in $T/pre.zsh (before the plugin) and $T/post.zsh (after).
setup() {
	T=$ROOT/$1
	command mkdir -p $T/a $T/b $T/zd
	: > $T/pre.zsh; : > $T/post.zsh
	print -rl -- ': 1:0;global-1' ': 2:0;global-2' > $T/hist
	cat > $T/zd/.zshrc <<-RC
		HISTFILE=$T/hist HISTSIZE=1000 SAVEHIST=1000
		PS1= PS2= RPS1=
		unsetopt prompt_sp prompt_cr
		ZSH_PRIORITIZE_CWD_HISTORY_DIR=$T/cwd
		source $T/pre.zsh
		source ${(q)PLUGIN}
		source $T/post.zsh
	RC
}

# session: run stdin as an interactive session; stderr goes to $T/err.
session() {
	( cd $T && ZDOTDIR=$T/zd HOME=$T zsh -d -i 2>$T/err )
}

# Per-directory history file of directory $1.
cwdfile() {
	local h
	if (( $+commands[md5sum] )); then
		h=$(print -rn -- ${1:A} | command md5sum)
	else
		h=$(print -rn -- ${1:A} | command md5 -q)
	fi
	print -r -- $T/cwd/cwdhist-${h%% *}
}

print "Prioritization"
setup order
out=$(session <<EOF
cd $T/a
print a-1
print a-2
cd $T/b
print b-1
cd $T/a
fc -ln -4 -1
EOF
)
[[ $out == *$'print a-1\nprint a-2\ncd '$T/b ]]
check "the directory's commands come last (most recent)"
out=$(session <<EOF
cd $T/b
fc -ln -2 -1
EOF
)
[[ $out == $'print b-1\ncd '$T/a ]]
check "a new shell prioritizes the directory's commands"
has "$(session <<<'fc -ln 1')" global-2
check "global history stays reachable"
has "$(<$(cwdfile $T/a))" ';print a-2'
check "per-directory history has its own file"

print "Regression: user options such as KSH_ARRAYS broke the plugin"
setup options
command mkdir -p "$T/a b"
print 'setopt ksh_arrays no_unset sh_word_split' > $T/pre.zsh
out=$(session <<EOF
cd "$T/a b"
print spaced
cd $T/b
cd "$T/a b"
fc -ln -2 -1
EOF
)
[[ $out == *$'\nprint spaced\ncd '$T/b && ! -s $T/err ]]
check "the directory's commands come last, without errors" ||
	print -rl -- "       "${(f)"$(<$T/err)"}

print "Regression: cd rewrote the shared \$HISTFILE"
# Popping the pushed list saved it, so every cd rewrote $HISTFILE through
# $HISTFILE.new and a rename; shells sharing $HISTFILE then failed with
# "can't rename ...hist.new to $HISTFILE".
setup rewrite
print 'setopt share_history' > $T/pre.zsh
out=$(session <<EOF
zmodload -F zsh/stat b:zstat
print inode=\$(zstat +inode \$HISTFILE)
cd $T/a
cd $T/b
print inode=\$(zstat +inode \$HISTFILE)
EOF
)
inodes=(${(M)${(f)out}:#inode=*})
[[ ${#inodes} -eq 2 && $inodes[1] == $inodes[2] ]]
check "cd leaves \$HISTFILE in place"
has "$(<$T/hist)" "cd $T/b"
check "commands still reach \$HISTFILE"

print "Commands zsh could not yet write survive a directory change"
# SHARE_HISTORY skips writing a command while another shell holds the lock.
setup pending
print 'setopt share_history' > $T/pre.zsh
session >/dev/null <<EOF
ln -s held \$HISTFILE.LOCK
print pending-cmd
rm \$HISTFILE.LOCK; cd $T/a
print after
EOF
has "$(<$T/hist)" ';print pending-cmd'
check "the skipped command reaches \$HISTFILE"

print "Regression: concurrent shells sharing \$HISTFILE"
setup race
print 'setopt share_history hist_fcntl_lock' > $T/pre.zsh
print 'SAVEHIST=100000 HISTSIZE=100000' > $T/post.zsh
for i in {1..60}; do print -rl -- "cd $T/a" "print a$i" "cd $T/b"; done > $T/cmds
pids=()
for i in {1..6}; do
	# Staggered exits: zsh's own save on exit races with HIST_FCNTL_LOCK.
	{ cat $T/cmds; print "sleep $(( i * 0.3 ))" } > $T/cmds$i
	( cd $T && ZDOTDIR=$T/zd HOME=$T zsh -d -i < $T/cmds$i >/dev/null 2>$T/err$i ) &
	pids+=($!)
done
wait $pids
errs=$(cat $T/err<->)
[[ $errs != *(rename|failed to write|locking failed)* ]]
check "no history write errors" ||
	print -rl -- "       "${${(f)errs}[1,3]}
[[ $(command grep -c 'print a[0-9]' $T/hist) -eq 360 ]]
check "no history lines lost" ||
	print -r -- "       $(command grep -c 'print a[0-9]' $T/hist) of 360"

print "Regression: a failed history read aborted the command line"
setup abort
command mkdir -p $T/cwd
print ': 3:0;old' > $(cwdfile $T/a)
# A lock file dated in the future makes zsh fail to lock the file.
command ln -s stale $(cwdfile $T/a).LOCK
command touch -h -d '+1 hour' $(cwdfile $T/a).LOCK
out=$(session <<EOF
cd $T/a && print continued
_zsh_prioritize_cwd_history_reload; print still-running
print alive
EOF
)
has "$out" continued
check "cd && cmd runs cmd"
has "$out" still-running
check "the rest of the command line runs"
has "$out" alive
check "the shell survives"

print "Regression: commands kept out of \$HISTFILE leaked into per-directory files"
setup private
print -r -- "setopt hist_ignore_space; HISTORY_IGNORE='print hidden*'" > $T/pre.zsh
session >/dev/null <<EOF
cd $T/a
 print secret
print hidden-too
print visible
EOF
f=$(<$(cwdfile $T/a))
[[ $f != *secret* ]]
check "HIST_IGNORE_SPACE commands are not recorded"
[[ $f != *hidden-too* ]]
check "HISTORY_IGNORE commands are not recorded"
has "$f" visible
check "other commands are recorded"

print "Regression: HISTFILE set after sourcing the plugin disabled it"
setup late
print 'unset HISTFILE' > $T/pre.zsh
print "HISTFILE=$T/hist" > $T/post.zsh
session >/dev/null <<EOF
cd $T/a
print late-cmd
EOF
has "$(cat $(cwdfile $T/a) 2>/dev/null)" late-cmd
check "commands are recorded"

print "Regression: the plugin turned on INC_APPEND_HISTORY_TIME next to SHARE_HISTORY"
setup opts
print 'setopt share_history' > $T/post.zsh
out=$(session <<<'[[ -o inc_append_history_time ]] && print on || print off')
[[ $out == off ]]
check "INC_APPEND_HISTORY_TIME stays off"
setup opts-none
out=$(session <<<'[[ -o inc_append_history_time ]] && print on || print off')
[[ $out == on ]]
check "INC_APPEND_HISTORY_TIME is set without an incremental option"

print "Regression: a command ending in a backslash swallowed the next one"
setup backslash
session >/dev/null <<'EOF'
print -r -- end\\
print next
EOF
out=$(session <<EOF
fc -p
fc -R $(cwdfile $T)
fc -ln 1
EOF
)
has "$out" $'\nprint -r -- end\\\\\nprint next\n'
check "both commands are separate entries" ||
	print -r -- "       got: ${(q)out}"

print "Regression: per-directory history was readable by others"
[[ $(zstat +mode -o $T/cwd) == *700 ]]
check "the history directory is private"

print "Regression: the plugin's hooks exited a shell with ERR_EXIT"
setup errexit
print 'setopt err_exit' > $T/post.zsh
out=$(session <<EOF
cd $T/a
print alive-a
cd $T/b; print alive-b
EOF
)
has "$out" alive-a && has "$out" alive-b
check "cd keeps the shell running"

print "Regression: trimming left the tail of a multiline command as an entry"
setup trim
print 'ZSH_PRIORITIZE_CWD_HISTORY_MAX=2' > $T/post.zsh
command mkdir -p -m 700 $T/cwd
print -rl -- ': 1:0;old-1' ': 2:0;old-2' ': 3:0;print multi\' 'fragment\' 'end' > $(cwdfile $T/a)
out=$(session <<EOF
cd $T/a
fc -ln 1
EOF
)
[[ $out != *fragment* ]]
check "no fragment entry after a trim" ||
	print -r -- "       got: ${(q)out}"

print
print "$pass passed, $fail failed"
(( fail == 0 ))
