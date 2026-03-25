#!/usr/bin/env zsh
# Integration tests for zsh-prioritize-cwd-history
#
# Run: zsh tests/test-prioritize-cwd-history.zsh

emulate -L zsh
setopt EXTENDED_HISTORY

typeset -gi _T_PASS=0 _T_FAIL=0

_t_assert() {
	local actual=$1 expected=$2 msg=$3
	if [[ $actual == $expected ]]; then
		(( _T_PASS++ ))
		print "  ✓ $msg"
	else
		(( _T_FAIL++ ))
		print "  ✗ $msg"
		print "    expected: $(printf '%q' "$expected")"
		print "    actual:   $(printf '%q' "$actual")"
	fi
}

_t_assert_contains() {
	local haystack=$1 needle=$2 msg=$3
	if [[ $haystack == *"$needle"* ]]; then
		(( _T_PASS++ ))
		print "  ✓ $msg"
	else
		(( _T_FAIL++ ))
		print "  ✗ $msg"
		print "    expected to contain: $needle"
		print "    in: $haystack"
	fi
}

_t_assert_true() {
	local val=$1 msg=$2
	if (( val )); then
		(( _T_PASS++ ))
		print "  ✓ $msg"
	else
		(( _T_FAIL++ ))
		print "  ✗ $msg (falsy)"
	fi
}

# --- Setup ---
PLUGIN_DIR=${0:A:h:h}
TEST_ROOT=$(command mktemp -d "${TMPDIR:-/tmp}/zsh-pcwdh-test.XXXXXXXXXX")

_ORIG_HISTFILE=$HISTFILE
_ORIG_HISTSIZE=$HISTSIZE
_ORIG_SAVEHIST=$SAVEHIST
_ORIG_PWD=$PWD

_t_cleanup() {
	cd "$_ORIG_PWD" 2>/dev/null
	HISTFILE=$_ORIG_HISTFILE
	HISTSIZE=$_ORIG_HISTSIZE
	SAVEHIST=$_ORIG_SAVEHIST
	command rm -rf "$TEST_ROOT"
}
trap '_t_cleanup' EXIT INT TERM

export HISTFILE="$TEST_ROOT/histfile"
export HISTSIZE=10000
export SAVEHIST=10000
export ZSH_PRIORITIZE_CWD_HISTORY_DIR="$TEST_ROOT/cwd_hist"
export ZSH_PRIORITIZE_CWD_HISTORY_MAX=100

command mkdir -p "$TEST_ROOT/dir-a" "$TEST_ROOT/dir-b" "$TEST_ROOT/dir-c"

# Seed global history with distinguishable entries
{
	print -r -- ": 1000000001:0;global-cmd-1"
	print -r -- ": 1000000002:0;global-cmd-2"
	print -r -- ": 1000000003:0;global-cmd-3"
} > "$HISTFILE"

# Source the plugin
autoload -Uz add-zsh-hook
source "$PLUGIN_DIR/zsh-prioritize-cwd-history.zsh"

# --- Helpers ---

# Simulate running a command (triggers addhistory hook + appends to HISTFILE)
_t_run_cmd() {
	local cmd=$1
	_zsh_prioritize_cwd_history_addhistory "${cmd}"$'\n'
	local escaped=${cmd//$'\n'/$'\\\n'}
	print -r -- ": ${EPOCHSECONDS}:0;${escaped}" >> "$HISTFILE"
	print -s -- "$cmd"
}

# Return the most recent history entry (stripped of whitespace)
_t_last_hist() {
	# fc -l -n can return multiple lines in non-interactive mode; take last
	fc -l -n 1 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//'
}

# Return last N history entries (most-recent last in output)
_t_recent_hist() {
	local -i n=${1:-5}
	fc -l -n 1 2>/dev/null | tail -$n | sed 's/^[[:space:]]*//'
}

# ============================================================
print "\n=== Test 1: Initial load — no CWD history ==="
# ============================================================
cd "$TEST_ROOT/dir-c"
_zsh_prioritize_cwd_history_initialize

hist=$(_t_last_hist)
_t_assert "$hist" "global-cmd-3" "Most recent entry is last global cmd"

# ============================================================
print "\n=== Test 2: CWD commands are prioritized ==="
# ============================================================
cd "$TEST_ROOT/dir-a"
_zsh_prioritize_cwd_history_cwd_changed

_t_run_cmd "dir-a-cmd-1"
_t_run_cmd "dir-a-cmd-2"

_zsh_prioritize_cwd_history_cwd_changed

hist=$(_t_last_hist)
_t_assert "$hist" "dir-a-cmd-2" "dir-a-cmd-2 is most recent in dir-a"

# ============================================================
print "\n=== Test 3: cd to dir-b — dir-b commands prioritized ==="
# ============================================================
cd "$TEST_ROOT/dir-b"
_zsh_prioritize_cwd_history_cwd_changed

_t_run_cmd "dir-b-cmd-1"
_zsh_prioritize_cwd_history_cwd_changed

hist=$(_t_last_hist)
_t_assert "$hist" "dir-b-cmd-1" "dir-b-cmd-1 is most recent in dir-b"

# ============================================================
print "\n=== Test 4: cd back to dir-a — dir-a commands first ==="
# ============================================================
cd "$TEST_ROOT/dir-a"
_zsh_prioritize_cwd_history_cwd_changed

hist=$(_t_last_hist)
_t_assert "$hist" "dir-a-cmd-2" "After cd back, dir-a-cmd-2 is top"

all=$(_t_recent_hist 10)
_t_assert_contains "$all" "dir-a-cmd-1" "dir-a-cmd-1 in history"
_t_assert_contains "$all" "dir-a-cmd-2" "dir-a-cmd-2 in history"
_t_assert_contains "$all" "global-cmd-3" "global-cmd-3 still visible"

# ============================================================
print "\n=== Test 5: New terminal simulation (reset + re-init) ==="
# ============================================================
_zsh_pcwdh_pushed=0
cd "$TEST_ROOT/dir-a"
_zsh_prioritize_cwd_history_cwd_changed

hist=$(_t_last_hist)
_t_assert "$hist" "dir-a-cmd-2" "New terminal: dir-a commands still prioritized"

# ============================================================
print "\n=== Test 6: Empty directory — no crash ==="
# ============================================================
cd "$TEST_ROOT/dir-c"
_zsh_prioritize_cwd_history_cwd_changed

hist=$(_t_last_hist)
_t_assert_true $(( ${#hist} > 0 )) "History non-empty in virgin directory"

# ============================================================
print "\n=== Test 7: Rapid cd back and forth ==="
# ============================================================
for _i in 1 2 3 4 5; do
	cd "$TEST_ROOT/dir-a"
	_zsh_prioritize_cwd_history_cwd_changed
	cd "$TEST_ROOT/dir-b"
	_zsh_prioritize_cwd_history_cwd_changed
done

cd "$TEST_ROOT/dir-a"
_zsh_prioritize_cwd_history_cwd_changed

hist=$(_t_last_hist)
_t_assert "$hist" "dir-a-cmd-2" "Rapid cd: dir-a history intact"

cd "$TEST_ROOT/dir-b"
_zsh_prioritize_cwd_history_cwd_changed

hist=$(_t_last_hist)
_t_assert "$hist" "dir-b-cmd-1" "Rapid cd: dir-b history intact"

# ============================================================
print "\n=== Test 8: Multiline command ==="
# ============================================================
cd "$TEST_ROOT/dir-a"
_zsh_prioritize_cwd_history_cwd_changed

_t_run_cmd $'for i in 1 2 3; do\n  echo $i\ndone'
_zsh_prioritize_cwd_history_cwd_changed

hist=$(_t_last_hist)
_t_assert_contains "$hist" "for i in 1 2 3" "Multiline command preserved"

# ============================================================
print "\n=== Test 9: Per-CWD history file created ==="
# ============================================================
local cwd_file
cwd_file=$(_zsh_prioritize_cwd_history_file_for_cwd)
if [[ -f "$cwd_file" ]]; then
	_t_assert "exists" "exists" "Per-CWD file exists"
else
	_t_assert "missing" "exists" "Per-CWD file exists"
fi

# ============================================================
print "\n=== Test 10: Trim large per-CWD file ==="
# ============================================================
cd "$TEST_ROOT/dir-a"
cwd_file=$(_zsh_prioritize_cwd_history_file_for_cwd)

local -i max_lines=${ZSH_PRIORITIZE_CWD_HISTORY_MAX:-100}
for (( _i = 1; _i <= max_lines * 2 + 50; _i++ )); do
	print -r -- ": ${EPOCHSECONDS}:0;filler-cmd-${_i}" >> "$cwd_file"
done

local -i lines_before
lines_before=$(command wc -l < "$cwd_file")

_zsh_prioritize_cwd_history_cwd_changed

local -i lines_after
lines_after=$(command wc -l < "$cwd_file")

_t_assert_true $(( lines_after <= max_lines + 10 )) \
	"Trim: ${lines_before} → ${lines_after} lines (max ${max_lines})"

# ============================================================
print "\n=== Test 11: addhistory always returns 0 ==="
# ============================================================
(
	ZSH_PRIORITIZE_CWD_HISTORY_DIR="/nonexistent/readonly/path"
	_zsh_prioritize_cwd_history_addhistory "test-cmd"$'\n'
) 2>/dev/null
_t_assert "$?" "0" "addhistory returns 0 even on write failure"

# ============================================================
print "\n=== Test 12: md5 produces consistent hash ==="
# ============================================================
local h1 h2 h3
h1=$(_zsh_prioritize_cwd_history_md5 "/some/test/path")
h2=$(_zsh_prioritize_cwd_history_md5 "/some/test/path")
_t_assert "$h1" "$h2" "md5 is deterministic"

h3=$(_zsh_prioritize_cwd_history_md5 "/different/path")
if [[ "$h1" != "$h3" ]]; then
	_t_assert "different" "different" "md5 differs for different paths"
else
	_t_assert "same" "different" "md5 differs for different paths"
fi

# ============================================================
# Results
# ============================================================
print "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print "Results: ${_T_PASS} passed, ${_T_FAIL} failed"
print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
(( _T_FAIL == 0 )) && exit 0 || exit 1
