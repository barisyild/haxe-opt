#!/usr/bin/env bash
# Runs Haxe's own eval test suites (tests/unit, misc, sys, threads, nullsafety) with a haxe binary,
# the way every haxe-plus change is verified (HAXE-PLUS.md, "Verification"):
#   off      HAXE_EVAL_JIT=0: the run-time changes alone
#   strict   HAXE_EVAL_JIT_STRICT=1: every class native (threshold 0), and a unit that fails to
#            compile or load is fatal. Run it first after a build, while the cache is cold, so
#            that every unit is compiled; run it again for the warm cache.
#   default  the JIT's defaults (J2): these suites are light projects, so their functions run
#            closure-compiled behind the counting wrapper
#
#   test-suites.sh <haxe binary> <log dir> [mode...]      (default: off strict default)
#
# Needs utest in the haxelib repository HAXELIB_PATH points to (verified with utest a94f881, as a
# dev library), and neko for haxelib. HAXE_STD_PATH defaults to this tree's std/. HAXE_PLUS_TESTS
# runs a copy of tests/ elsewhere instead: haxelib prefers a local .haxelib repository in any parent
# directory to HAXELIB_PATH.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BIN="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
LOGDIR="$2"
shift 2
MODES="${*:-off strict default}"
export PATH="$(dirname "$BIN"):$PATH"
export HAXE_STD_PATH="${HAXE_STD_PATH:-$ROOT/std}"
TESTS="${HAXE_PLUS_TESTS:-$ROOT/tests}"
mkdir -p "$LOGDIR"
LOGDIR="$(cd "$LOGDIR" && pwd)"
failed=0

run() {
	local mode=$1 name=$2 dir=$3; shift 3
	local log="$LOGDIR/$mode/$name.log" start=$(date +%s)
	mkdir -p "$LOGDIR/$mode"
	( cd "$TESTS/$dir" && case $mode in
		off) HAXE_EVAL_JIT=0 "$@" ;;
		strict) HAXE_EVAL_JIT_STRICT=1 "$@" ;;
		*) "$@" ;;
	esac ) > "$log" 2>&1
	local code=$? verdict=""
	case $name in
		unit|sys|threads) grep -q "ALL TESTS OK" "$log" && verdict="ALL TESTS OK" || { verdict="NOT OK"; failed=1; } ;;
		misc) verdict="$(grep -E '^Done running' "$log" | tail -1)" ;;
	esac
	[ $code -eq 0 ] || failed=1
	echo "$mode $name: exit=$code ${verdict} ($(( $(date +%s) - start ))s)"
}

# The sys tests run with EXISTS=1, as RunCi does. File names with invalid Unicode cannot exist on
# APFS, and compile-fs.hxml says to comment its define out there: done for the run only.
FS="$TESTS/sys/compile-fs.hxml"
restore() { [ -f "$FS.haxe-plus" ] && mv -f "$FS.haxe-plus" "$FS"; }
trap restore EXIT
if [ "$(uname)" = Darwin ]; then
	cp "$FS" "$FS.haxe-plus"
	perl -pi -e 's/^-D TEST_INVALID_UNICODE_FS/# -D TEST_INVALID_UNICODE_FS/' "$FS"
fi

for mode in $MODES; do
	run $mode unit unit "$BIN" compile-macro.hxml
	run $mode misc misc "$BIN" compile.hxml
	run $mode sys sys env EXISTS=1 "$BIN" compile-macro.hxml
	run $mode threads threads "$BIN" build.hxml --interp
	run $mode nullsafety nullsafety "$BIN" test.hxml
done
exit $failed
