#!/usr/bin/env bash
# Installs the haxe binary built in this tree (./haxe) into <dest dir>, with the eval JIT on.
#
#   install.sh <dest dir> [cache directory]
#
# The JIT compiles against the .cmi/.cmx files the binary was built from, so they are copied too,
# into <dest>/jit-objs with _build/default's layout: rebuilding this tree later must not change
# what the installed binary compiles against. The binary is copied under a temporary name and
# renamed over the old one, so compilations running from <dest> are not disturbed.
#
# The standard library is not copied: haxe-plus does not change it, so the release's std/ next to
# the binary (or HAXE_STD_PATH) is the one to use. Run in the environment that built the binary
# (jit-conf.sh records its ocamlopt).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
mkdir -p "$1"
DEST="$(cd "$1" && pwd)"
CACHE="${2:-$DEST/jit-cache}"
B="$ROOT/_build/default"
cp "$ROOT/haxe" "$DEST/haxe.new"
rm -rf "$DEST/jit-objs.new"
( cd "$B" && find . -type d \( -name byte -o -name native \) -path "*objs*" ) | while IFS= read -r d; do
	mkdir -p "$DEST/jit-objs.new/$d"
	find "$B/$d" -maxdepth 1 \( -name '*.cmi' -o -name '*.cmx' \) -exec cp {} "$DEST/jit-objs.new/$d/" \;
done
rm -rf "$DEST/jit-objs.old"
if [ -d "$DEST/jit-objs" ]; then mv "$DEST/jit-objs" "$DEST/jit-objs.old"; fi
mv "$DEST/jit-objs.new" "$DEST/jit-objs"
mv -f "$DEST/haxe.new" "$DEST/haxe"
rm -rf "$DEST/jit-objs.old"
"$HERE/jit-conf.sh" "$DEST" "$DEST/jit-objs" "$CACHE"
echo "installed $("$DEST/haxe" -version) in $DEST"
