class Base {
	public var x:Int;
	public function new(x:Int) { this.x = x; }
	public function describe():String return "Base(" + x + ")";
	public function add(n:Int):Int { x += n; return x; }
}
class Derived extends Base {
	var name:String;
	public function new(x:Int, name:String) { super(x * 2); this.name = name; }
	override public function describe():String return "Derived:" + name + ":" + super.describe();
}
enum Shape { Circle(r:Float); Rect(w:Int, h:Int); Empty; }
class Main {
	static var counter = 0;
	static function fib(n:Int):Int return n < 2 ? n : fib(n - 1) + fib(n - 2);
	static function area(s:Shape):Float {
		return switch (s) {
			case Circle(r): 3.0 * r * r;
			case Rect(w, h): w * h;
			case Empty: 0;
		}
	}
	static function classify(i:Int):String {
		return switch (i) { case 0: "zero"; case 1 | 2 | 3: "small"; case 100: "hundred"; default: "other"; }
	}
	static function word(s:String):Int {
		return switch (s) { case "a": 1; case "bb" | "cc": 2; default: -1; }
	}
	static function makeCounter():Void->Int {
		var c = 0;
		return function() { c++; return c; };
	}
	static function loops():Int {
		var sum = 0;
		for (i in 0...10) { if (i == 3) continue; if (i == 8) break; sum += i; }
		var j = 0;
		do { j++; if (j == 2) continue; sum += j; } while (j < 5);
		var k = 10;
		while (k > 0) { k -= 3; sum ^= k; }
		return sum;
	}
	static function tryIt(v:Int):String {
		try {
			if (v == 0) throw "zero";
			if (v == 1) throw 42;
			return "ok" + v;
		} catch (e:String) {
			return "caught string " + e;
		} catch (e:Int) {
			return "caught int " + e;
		}
	}
	static function defaults(a:Int, ?b:Int = 5, ?c:String = "x"):String return a + ":" + b + ":" + c;
	static function main() {
		trace(fib(20));
		var d = new Derived(5, "d");
		trace(d.describe());
		trace(d.add(3));
		var b:Base = d;
		trace(b.describe());
		trace(area(Circle(2)), area(Rect(3, 4)), area(Empty));
		trace([for (i in [0, 1, 2, 3, 50, 100]) classify(i)]);
		trace([word("a"), word("bb"), word("cc"), word("zz")]);
		var c1 = makeCounter();
		c1(); c1();
		trace(c1());
		trace(loops());
		trace(tryIt(0), tryIt(1), tryIt(2));
		trace(defaults(1), defaults(1, 2), defaults(1, 2, "y"));
		var o = {a: 1, b: "two", c: [1, 2, 3]};
		o.a += 10;
		o.c[1] *= 7;
		trace(o.a, o.b, o.c);
		var arr = [5, 3, 9, 1];
		arr.sort((a, b) -> a - b);
		trace(arr, arr.length);
		var s = new StringBuf();
		for (i in 0...5) s.add(i);
		trace(s.toString());
		var m = new Map<String, Int>();
		m["k"] = 3; m["k"] += 4;
		trace(m["k"]);
		counter += 5; counter++; ++counter;
		trace(counter);
		var fs = [for (i in 0...3) () -> i * 10];
		trace([for (f in fs) f()]);
		var x = 7;
		var inc = function(n) { x += n; return x; };
		trace(inc(1), inc(2), x);
		trace(Std.parseInt("123") + 1, 7 / 2, 7 % 3, -5 >> 1, -5 >>> 28, ~3, 1 << 33);
		trace(Type.enumIndex(Rect(1,2)), Std.string(Circle(1.5)));
		var n:Null<Int> = null;
		trace(n == null, n != null);
		try { var z:Dynamic = null; z.foo(); } catch (e:Dynamic) { trace("null call: " + e); }
		trace(haxe.CallStack.toString(haxe.CallStack.callStack()).split("\n").length > 0);
	}
}
