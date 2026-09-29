class Item {
	public var n:Int;
	public function new(n) this.n = n;
	public function toString() {
		Main.log.push("ts" + n);
		return "I" + n;
	}
}

class Main {
	public static var log:Array<String> = [];

	static function main() {
		var a = [for (i in 0...1000) "s" + i];
		var calls = [];
		var m = a.map(function(x) { calls.push(x); return x + "!"; });
		trace(m.length + " " + m[0] + " " + m[999] + " " + calls.length + " " + calls[0] + " " + calls[999]);
		var f = a.filter(function(x) return x.length % 2 == 0);
		trace(f.length + " " + f[0] + " " + f[f.length - 1]);
		var none = a.filter(function(x) return false);
		trace(none.length);
		var all = a.filter(function(x) return true);
		trace(all.length + " " + all[999]);
		var b = a.copy();
		var sp = b.splice(10, 500);
		trace(sp.length + " " + sp[0] + " " + sp[499] + " " + b.length + " " + b[10]);
		var b2 = a.copy();
		var sp2 = b2.splice(-300, 1000);
		trace(sp2.length + " " + sp2[0] + " " + b2.length);
		var j = a.join(",");
		trace(j.length + " " + haxe.crypto.Md5.encode(j));
		var s = j.split(",");
		trace(s.length + " " + s[0] + " " + s[999] + " " + (s.join(",") == j));
		var v = haxe.ds.Vector.fromArrayCopy(a);
		var vm = v.map(function(x) return x.toUpperCase());
		trace(vm.length + " " + vm[0] + " " + vm[999]);
		trace(v.join("|").length);
		trace(Std.string(a).length);
		trace(Std.string([for (i in 0...300) i]).substr(0, 50));
		var order = [];
		var m2 = [for (i in 0...600) i].map(function(x) { order.push(x); return x * 2; });
		var ok = true;
		for (i in 0...600) if (order[i] != i || m2[i] != i * 2) ok = false;
		trace(ok);
		var src = [for (i in 0...700) i];
		var seen = 0;
		var f2 = src.filter(function(x) { seen++; if (x == 5) src.push(9999); return x % 3 == 0; });
		trace(f2.length + " " + seen + " " + src.length + " " + f2[f2.length - 1]);
		var src2 = [for (i in 0...700) i];
		var m3 = src2.map(function(x) { if (x == 1) src2[500] = -1; return x; });
		trace(m3[500] + " " + m3.length + " " + src2[500]);
		var items = [for (i in 0...400) new Item(i)];
		var js = items.join(";");
		trace(js.length + " " + log.length + " " + log[0] + " " + log[399]);
		log = [];
		var st = Std.string(items);
		trace(st.length + " " + log.length + " " + log[0] + " " + log[399]);
		try {
			[for (i in 0...700) i].map(function(x) { if (x == 400) throw "boom" + x; return x; });
		} catch (e:String) trace(e);
		try {
			[for (i in 0...700) i].filter(function(x) { if (x == 450) throw "fboom" + x; return true; });
		} catch (e:String) trace(e);
		var lit:Array<Dynamic> = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, "x" + 270];
		trace(lit.length + " " + lit[269] + " " + lit[270]);
		trace(sys.FileSystem.readDirectory(".").length > 0);
		trace(BigMacro.info());
	}
}
