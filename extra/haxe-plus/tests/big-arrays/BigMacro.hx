import haxe.macro.Context;
import haxe.macro.Expr;

class BigMacro {
	public static macro function info():Expr {
		var exprs = [for (i in 0...400) macro $v{i}];
		var arr = macro [$a{exprs}];
		var t = Context.typeExpr(arr);
		var n = switch (t.expr) {
			case TArrayDecl(el): el.length;
			case _: -1;
		}
		var block = [for (i in 0...350) macro var x = $v{i}];
		var tb = Context.typeExpr(macro {$b{block}; 0;});
		var nb = switch (tb.expr) {
			case TBlock(el): el.length;
			case _: -1;
		}
		var fields = [for (i in 0...300) ({name: "f" + i, pos: Context.currentPos(), kind: FVar(macro :Int, macro $v{i})}:Field)];
		var td:TypeDefinition = {pack: [], name: "Wide", pos: Context.currentPos(), kind: TDClass(), fields: fields};
		Context.defineType(td);
		var c = switch (Context.getType("Wide")) {
			case TInst(c, _): c.get();
			case _: null;
		}
		var names = [for (f in c.fields.get()) f.name];
		var s = Std.string(names).length;
		var types = Context.getModule("Main").length;
		return macro $v{n + " " + nb + " " + c.fields.get().length + " " + s + " " + names[299] + " " + types};
	}
}
