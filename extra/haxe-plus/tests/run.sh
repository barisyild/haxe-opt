#!/usr/bin/env bash
# Differential tests. Each directory holds a program (Main.hx) and the output the base release's
# own semantics give for it (expected.txt); the program must give exactly that output with the JIT
# off, with every class native (strict: threshold 0, and a unit that fails to compile or load is
# fatal), and with the JIT's defaults (tiers: classes that are not hot run closure-compiled, counted).
# gc-settings is the exception: it checks haxe-plus's own GC defaults (G1), which the release does
# not have.
#
#   run.sh <haxe binary>
#
# HAXE_STD_PATH defaults to this tree's std/. The GC settings are the binary's own: OCAMLRUNPARAM
# and CAMLRUNPARAM are cleared.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BIN="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
export HAXE_STD_PATH="${HAXE_STD_PATH:-$ROOT/std}"
unset OCAMLRUNPARAM CAMLRUNPARAM
failed=0
for t in "$HERE"/*/; do
	name="$(basename "$t")"
	for mode in off strict tiers; do
		out="$(mktemp)"
		( cd "$t" && case $mode in
			off) HAXE_EVAL_JIT=0 "$BIN" --main Main --interp ;;
			strict) HAXE_EVAL_JIT_STRICT=1 "$BIN" --main Main --interp ;;
			*) "$BIN" --main Main --interp ;;
		esac ) > "$out" 2>&1
		if cmp -s "$out" "$t/expected.txt"; then
			echo "ok   $name ($mode)"
		else
			echo "FAIL $name ($mode)"
			diff "$t/expected.txt" "$out" | head -20
			failed=1
		fi
		rm -f "$out"
	done
done
exit $failed
