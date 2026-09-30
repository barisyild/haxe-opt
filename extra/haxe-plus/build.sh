#!/usr/bin/env bash
# Builds ./haxe in this tree and turns the eval JIT on for it (eval-jit.conf next to it, cache in
# ./jit-cache). Run it in the environment of an OCaml 5.3 switch with haxe.opam's dependencies
# installed (HAXE-PLUS.md, "Building").
#
# The JIT of ./haxe compiles against _build/default, which the next build changes: for a binary
# that other work relies on while this tree is rebuilt, use install.sh instead.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
make -C "$ROOT" haxe "-j$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
"$ROOT/extra/haxe-plus/jit-conf.sh" "$ROOT" "$ROOT/_build/default"
"$ROOT/haxe" -version
