#!/usr/bin/env bash
# Differential tests. Each directory holds a program (Main.hx) and the output the base release's
# own semantics give for it (expected.txt); the program must give exactly that output with the JIT
# off and with the JIT on (strict: a unit that fails to compile or load is fatal). gc-settings is
# the exception: it checks haxe-plus's own GC defaults (G1), which the release does not have.
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
	for mode in off strict; do
		out="$(mktemp)"
		( cd "$t" && if [ $mode = off ]; then HAXE_EVAL_JIT=0 "$BIN" --main Main --interp; else HAXE_EVAL_JIT_STRICT=1 "$BIN" --main Main --interp; fi ) > "$out" 2>&1
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
