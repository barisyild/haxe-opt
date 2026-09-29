// Not a differential test: checks that the GC settings haxe-plus builds in are in effect when
// OCAMLRUNPARAM and CAMLRUNPARAM are not set (change G1 in HAXE-PLUS.md).
class Main {
	static function main() {
		var c = eval.vm.Gc.get();
		Sys.println('minor_heap_size=${c.minor_heap_size} space_overhead=${c.space_overhead}');
	}
}
