(*
	Native JIT for eval.

	The closure compiler (evalJit.ml) turns every typed expression into an OCaml closure and
	runs the tree of closures. This module compiles the same typed functions to machine code
	instead: each class becomes one OCaml compilation unit whose functions are the direct-style
	equivalent of what evalJit would build, ocamlopt compiles it to a .cmxs, and Dynlink loads
	it into the running compiler. The generated code calls the very run-time functions the
	closure compiler's emitters call, so values, prototypes, environments and exceptions are
	shared with the rest of eval unchanged; what goes away is the per-node indirect call, the
	locals array (locals become OCaml variables) and most boxing of intermediate booleans.

	Semantics are the closure compiler's, not the language's: every construct is generated to
	evaluate its operands, check its values and record positions in the order evalJit's emitter
	does, because that order is observable through exceptions and stack traces. Local functions
	are numbered in the order evalJit compiles them, which shows in stack traces too.

	Three rules keep compiled units reusable across compilations (they are cached on disk by the
	digest of their source):
	- The source text depends only on the structure of the typed AST: names, operators, integer
	  constants. Everything else a function needs at run time (positions, prototypes, field
	  indices, strings, call-site caches, environment infos) is resolved when the function is
	  linked and handed over in an array, in an order recorded while generating.
	- Variables are renamed in declaration order, never by their global ids.
	- Anything the generator does not handle, and any failure to generate, compile, load or link,
	  falls back to the closure compiler for that function. The fallback is exact: it is what
	  would have run anyway.

	Controlled by the environment:
	  HAXE_EVAL_JIT=0         disable
	  HAXE_EVAL_JIT_LOG=1     log units compiled/loaded and fallbacks to stderr
	  HAXE_EVAL_JIT_STRICT=1  treat compile/load failures as fatal (for testing the JIT itself)
	  HAXE_EVAL_JIT_STATS=1   print counters at exit
	  HAXE_EVAL_JIT_DUMP=dir  also write the source of every unit compiled to dir
	  HAXE_EVAL_JIT_MAX_FUNCTION=n  largest function compiled, in typed expressions
	and by eval-jit.conf next to the haxe executable (ocamlopt path, include directories, cache
	directory, parallel jobs). Without that file the JIT is off.
*)

open Globals
open Ast
open Type
open EvalValue
open EvalContext
open EvalHash

let jit_version = "evaljit-1"

(* Configuration *)

let getenv name = try Sys.getenv name with Not_found -> ""

let log_enabled = lazy (getenv "HAXE_EVAL_JIT_LOG" <> "")
let strict = lazy (getenv "HAXE_EVAL_JIT_STRICT" <> "")

(* Functions of more typed expressions than this stay with the closure compiler: ocamlopt's time
   grows faster than linearly with the size of a function, and the largest functions are mostly
   straight-line code run once. *)
let max_function_size = lazy (try int_of_string (getenv "HAXE_EVAL_JIT_MAX_FUNCTION") with _ -> 3000)

let log fmt = Printf.ksprintf (fun s -> if Lazy.force log_enabled then prerr_endline ("[eval-jit] " ^ s)) fmt

type config = {
	ocamlopt : string;
	includes : string list;
	flags : string list;
	cache_dir : string;
	jobs : int;
}

let config = lazy (
	match getenv "HAXE_EVAL_JIT" with
	| "0" | "off" | "false" | "no" ->
		None
	| _ ->
		try
			let exe = Unix.realpath Sys.executable_name in
			let conf_file = Filename.concat (Filename.dirname exe) "eval-jit.conf" in
			if not (Sys.file_exists conf_file) then raise Exit;
			let ch = open_in conf_file in
			let lines = ref [] in
			(try while true do lines := input_line ch :: !lines done with End_of_file -> ());
			close_in ch;
			let ocamlopt = ref "" and includes = ref [] and flags = ref [] and cache = ref "" and jobs = ref 8 in
			List.iter (fun line ->
				let line = String.trim line in
				if line <> "" && line.[0] <> '#' then begin match String.index_opt line '=' with
					| Some i ->
						let k = String.sub line 0 i and v = String.sub line (i + 1) (String.length line - i - 1) in
						begin match k with
							| "ocamlopt" -> ocamlopt := v
							| "include" -> includes := v :: !includes
							| "flag" -> flags := v :: !flags
							| "cache" -> cache := v
							| "jobs" -> jobs := int_of_string v
							| _ -> ()
						end
					| None -> ()
				end
			) (List.rev !lines);
			if !ocamlopt = "" || !cache = "" then raise Exit;
			(* A unit is compiled against this very executable's interfaces and inlining data, so the
			   cache is keyed by the executable. *)
			let st = Unix.stat exe in
			let build_id = Digest.to_hex (Digest.string (Printf.sprintf "%s|%s|%d|%f|%d" jit_version exe st.Unix.st_size st.Unix.st_mtime st.Unix.st_ino)) in
			(* Caches of other builds are dead weight once no process of theirs can still be running. *)
			(try Array.iter (fun d ->
				let dir = Filename.concat !cache d in
				if d <> build_id && String.length d = 32 && (Unix.stat dir).Unix.st_mtime < Unix.time() -. 3600. then
					ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)))
			) (Sys.readdir !cache) with _ -> ());
			Some {
				ocamlopt = !ocamlopt;
				includes = List.rev !includes;
				flags = List.rev !flags;
				cache_dir = Filename.concat !cache build_id;
				jobs = max 1 !jobs;
			}
		with _ ->
			None
)

(* Statistics *)

let stat_units_compiled = ref 0
let stat_units_cached = ref 0
let stat_units_failed = ref 0
let stat_functions_native = ref 0
let stat_functions_fallback = ref 0
let stat_functions_unsupported = ref 0
let stat_compile_time = ref 0.
let stat_generate_time = ref 0.
let stat_load_time = ref 0.

let () = at_exit (fun () ->
	if getenv "HAXE_EVAL_JIT_STATS" <> "" then
		Printf.eprintf "[eval-jit] units: %d compiled, %d cached, %d failed; functions: %d native, %d unsupported, %d fell back at link; generate %.3fs, compile %.3fs, load %.3fs\n%!"
			!stat_units_compiled !stat_units_cached !stat_units_failed !stat_functions_native !stat_functions_unsupported !stat_functions_fallback
			!stat_generate_time !stat_compile_time !stat_load_time
)

(* Link-time requirements. The generated code refers to them as jk<i>; the linker resolves them
   in order into an Obj.t array. *)

type req =
	| RCtx
	| RPos of pos
	| RSomePos of pos
	| RString of string
	| RFloat of string
	| RStaticProto of int * pos
	| RStaticProtoValue of int * pos
	| RInstanceProto of int * pos
	| RObjectProto of (int * unit) list
	| RProtoFieldIndex of int * int (* proto req, name *)
	| RInstanceFieldIndex of int * int * pos (* proto req, name *)
	| RLazyProtoField of int * int * pos (* proto req, name, call position *)
	| RCtorLazy of int * pos * pos (* type key, lookup position, call position *)
	| RSpecialCtor of int
	| REnvInfo of bool * string * env_kind
	| ROProto of int (* proto req *)
	| RCallCache
	| RFieldCache

let req_type = function
	| RCtx -> "context"
	| RPos _ -> "pos"
	| RSomePos _ -> "pos option"
	| RString _ | RFloat _ | RStaticProtoValue _ -> "value"
	| RStaticProto _ | RInstanceProto _ | RObjectProto _ -> "vprototype"
	| RProtoFieldIndex _ | RInstanceFieldIndex _ -> "int"
	| RLazyProtoField _ | RCtorLazy _ -> "vfunc Lazy.t"
	| RSpecialCtor _ -> "(value list -> value)"
	| REnvInfo _ -> "env_info"
	| ROProto _ -> "vobject_proto"
	| RCallCache -> "R.call_cache"
	| RFieldCache -> "R.field_cache"

(* Whether two occurrences of the same requirement may share one resolved value. Call-site
   caches must not: evalJit builds one per call site. Constants are kept apart too, as evalJit
   creates one value per occurrence. *)
let req_shareable = function
	| RLazyProtoField _ | RCtorLazy _ | RString _ | RFloat _ | REnvInfo _ | RSomePos _ | RCallCache | RFieldCache -> false
	| _ -> true

let resolve ctx (resolved : Obj.t array) r : Obj.t = match r with
	| RCtx -> Obj.repr ctx
	| RPos p -> Obj.repr p
	| RSomePos p -> Obj.repr (Some p)
	| RString s -> Obj.repr (EvalString.create_unknown s)
	| RFloat f -> Obj.repr (vfloat (float_of_string f))
	| RStaticProto(key,p) -> Obj.repr (get_static_prototype ctx key p)
	| RStaticProtoValue(key,p) -> Obj.repr (get_static_prototype_as_value ctx key p)
	| RInstanceProto(key,p) -> Obj.repr (get_instance_prototype ctx key p)
	| RObjectProto l -> Obj.repr (fst (ctx.get_object_prototype ctx l))
	| RProtoFieldIndex(pi,name) -> Obj.repr (get_proto_field_index (Obj.obj resolved.(pi)) name)
	| RInstanceFieldIndex(pi,name,p) -> Obj.repr (get_instance_field_index (Obj.obj resolved.(pi)) name p)
	| RLazyProtoField(pi,name,p) ->
		let proto : vprototype = Obj.obj resolved.(pi) in
		let i = get_proto_field_index proto name in
		Obj.repr (lazy (match proto.pfields.(i) with VFunction (f,_) -> f | v -> EvalEmitter.cannot_call v p))
	| RCtorLazy(key,plookup,pcall) ->
		let fnew = get_instance_constructor ctx key plookup in
		Obj.repr (lazy (match Lazy.force fnew with VFunction (f,_) -> f | v -> EvalEmitter.cannot_call v pcall))
	| RSpecialCtor key -> Obj.repr (get_special_instance_constructor_raise ctx key)
	| REnvInfo(static,file,kind) -> Obj.repr (create_env_info static file (ctx.file_keys#get file) kind (IntHashtbl.create 0) 0 0)
	| ROProto pi -> Obj.repr (OProto (Obj.obj resolved.(pi)))
	| RCallCache -> Obj.repr (EvalJitRt.new_call_cache ())
	| RFieldCache -> Obj.repr (EvalJitRt.new_field_cache ())

(* Generator *)

exception Unsupported of string

let unsupported s = raise (Unsupported s)

type mode =
	| MV (* an OCaml expression of type value *)
	| MC (* of type bool: whether the value would be VTrue *)
	| MS (* of type unit: the value is discarded *)

type vacc =
	| Imm of string
	| Mut of string

(* Per compiled function or local function. *)
type fn = {
	fn_written : (int,unit) Hashtbl.t;
	fn_closures : (texpr * int) list;
	mutable fn_has_nonfinal_return : bool;
	fn_this : string option;
}

(* Per method, shared by the local functions inside it. *)
type g = {
	ctx : context;
	mutable b : Buffer.t;
	mutable reqs : req list; (* reversed *)
	mutable num_reqs : int;
	shared : (req,int) Hashtbl.t;
	mutable tmp : int;
	mutable fn : fn;
	mutable nodes : int;
}

let out g s = Buffer.add_string g.b s

let fresh g prefix =
	g.tmp <- g.tmp + 1;
	prefix ^ string_of_int g.tmp

let req_index g r =
	let share = req_shareable r in
	match (if share then Hashtbl.find_opt g.shared r else None) with
	| Some i ->
		i
	| None ->
		let i = g.num_reqs in
		g.reqs <- r :: g.reqs;
		g.num_reqs <- g.num_reqs + 1;
		if share then Hashtbl.replace g.shared r i;
		i

let req g r = "jk" ^ string_of_int (req_index g r)

let pos g p = req g (RPos p)

let lit_int32 i = Printf.sprintf "(%ldl)" i

let ocaml_string s = Printf.sprintf "%S" s

let unit_of_mode = function
	| MV -> "VNull"
	| MC -> "false"
	| MS -> "()"

let is_int t = match follow t with
	| TAbstract({a_path=[],"Int"},_) -> true
	| _ -> false

let is_string t = match follow t with
	| TInst({cl_path=[],"String"},_) -> true
	| _ -> false

let is_vector t = match follow t with
	| TInst({cl_path=(["eval"],"Vector")},_) -> true
	| _ -> false

(* Haxe 5's TSwitch is a record; the generator works on the (subject, (patterns, body) list,
   default) triple that 4.3's was. evalJit does not look at switch_exhaustive either. *)
let switch_parts sw =
	sw.switch_subject,List.map (fun c -> c.case_patterns,c.case_expr) sw.switch_cases,sw.switch_default

let is_const_int_pattern (el,_) =
	List.for_all (fun e -> match e.eexpr with
		| TConst (TInt _) -> true
		| _ -> false
	) el

let is_const_string_pattern (el,_) =
	List.for_all (fun e -> match e.eexpr with
		| TConst (TString _) -> true
		| _ -> false
	) el

let is_proper_method cf = match cf.cf_kind with
	| Method MethDynamic -> false
	| Method _ -> true
	| Var _ -> false

let rope_path t = match follow t with
	| TInst({cl_path=path},_) | TEnum({e_path=path},_) | TAbstract({a_path=path},_) -> s_type_path path
	| TDynamic _ -> "Dynamic"
	| TFun _ | TAnon _ | TMono _ | TType _ | TLazy _ -> unsupported "rope_path"

(* Variables written by a function's own body (not by the local functions inside it). *)
let collect_written e =
	let h = Hashtbl.create 0 in
	let rec loop e = match e.eexpr with
		| TFunction _ ->
			()
		| TBinop((OpAssign | OpAssignOp _),{eexpr = TLocal v},_) ->
			Hashtbl.replace h v.v_id ();
			Type.iter loop e
		| TUnop((Increment | Decrement),_,e1) ->
			begin match (Texpr.skip e1).eexpr with
				| TLocal v -> Hashtbl.replace h v.v_id ()
				| _ -> ()
			end;
			Type.iter loop e
		| _ ->
			Type.iter loop e
	in
	loop e;
	h

(* Numbers the local functions directly inside a function body in the order evalJit compiles
   them. That is source order except for calls on a field, where evalJit compiles the arguments
   before the object, and a few sub-expressions evalJit never compiles. *)
let number_closures e =
	let n = ref 0 in
	let acc = ref [] in
	let rec loop e = match e.eexpr with
		| TFunction _ ->
			incr n;
			acc := (e,!n) :: !acc
		| TCall({eexpr = TField({eexpr = TConst TSuper},FInstance _)},el) ->
			List.iter loop el
		| TCall({eexpr = TField(ef,fa)},el) ->
			List.iter loop el;
			begin match fa with
				| FStatic({cl_path=[],"StringTools"},{cf_name=("fastCodeAt" | "unsafeCodeAt")}) -> ()
				| FEnum _ -> ()
				| FStatic(_,cf) when is_proper_method cf -> ()
				| _ -> loop ef
			end
		| TNew({cl_path=[],"Array"},_,_) ->
			()
		| TNew({cl_path=["eval"],"Vector"},_,[{eexpr = TConst (TInt _)}]) ->
			()
		| TUnop(Increment,_,e1) when (match Texpr.skip e1 with {eexpr = TLocal v} -> not (has_var_flag v VCaptured) | _ -> false) ->
			()
		| TField(_,(FStatic _ | FEnum _ | FInstance(_,_,{cf_kind = Method (MethNormal | MethInline)}))) ->
			(* The object of a static field read is not compiled. *)
			begin match e.eexpr with
				| TField(e1,FInstance({cl_path=([],"Array")},_,{cf_name="length"}))
				| TField(e1,FInstance({cl_path=(["eval"],"Vector")},_,{cf_name="length"}))
				| TField(e1,FInstance({cl_path=(["haxe";"io"],"Bytes")},_,{cf_name="length"})) -> loop e1
				| _ -> ()
			end
		| _ ->
			Type.iter loop e
	in
	loop e;
	!acc

(* Variables a local function uses but does not declare, in order of first use. *)
let free_variables tf =
	let declared = Hashtbl.create 0 in
	let used = DynArray.create () in
	let seen = Hashtbl.create 0 in
	List.iter (fun (v,_) -> Hashtbl.replace declared v.v_id ()) tf.tf_args;
	let rec loop e = match e.eexpr with
		| TVar(v,_) ->
			Hashtbl.replace declared v.v_id ();
			Type.iter loop e
		| TTry(_,catches) ->
			List.iter (fun (v,_) -> Hashtbl.replace declared v.v_id ()) catches;
			Type.iter loop e
		| TFunction tf ->
			List.iter (fun (v,_) -> Hashtbl.replace declared v.v_id ()) tf.tf_args;
			loop tf.tf_expr
		| TLocal v ->
			if not (Hashtbl.mem seen v.v_id) then begin
				Hashtbl.replace seen v.v_id ();
				DynArray.add used v
			end
		| _ ->
			Type.iter loop e
	in
	loop tf.tf_expr;
	List.filter (fun v -> not (Hashtbl.mem declared v.v_id)) (DynArray.to_list used)

let var_read env v = match IntMap.find_opt v.v_id env with
	| Some (Imm s) -> s
	| Some (Mut s) -> "(!" ^ s ^ ")"
	| None -> unsupported ("unbound variable " ^ v.v_name)

let var_ref env v = match IntMap.find_opt v.v_id env with
	| Some (Mut s) -> s
	| Some (Imm _) -> unsupported ("write to a variable not known as written: " ^ v.v_name)
	| None -> unsupported ("unbound variable " ^ v.v_name)

let this_name g = match g.fn.fn_this with
	| Some s -> s
	| None -> unsupported "this outside of a method"

(* Code for an expression that can be duplicated or moved freely: evaluating it has no effect
   and cannot fail, so it need not be bound in evaluation order. *)
let rec atom g env e = match e.eexpr with
	| TConst (TInt i) -> Some ("(VInt32 " ^ lit_int32 i ^ ")")
	| TConst (TBool true) -> Some "VTrue"
	| TConst (TBool false) -> Some "VFalse"
	| TConst TNull -> Some "VNull"
	| TConst (TString s) -> Some (req g (RString s))
	| TConst (TFloat f) -> Some (req g (RFloat f))
	| TConst TThis -> Some (this_name g)
	| TLocal v ->
		begin match IntMap.find_opt v.v_id env with
			| Some (Imm s) -> Some s
			| Some (Mut _) -> None
			| None -> unsupported ("unbound variable " ^ v.v_name)
		end
	| TParenthesis e1 | TMeta(_,e1) | TCast(e1,None) -> atom g env e1
	| _ -> None

let finish_value g mode f = match mode with
	| MV -> f ()
	| MC -> out g "(match "; f (); out g " with VTrue -> true | _ -> false)"
	| MS -> out g "ignore ("; f (); out g ")"

let finish_bool g mode f = match mode with
	| MV -> out g "(if "; f (); out g " then VTrue else VFalse)"
	| MC -> f ()
	| MS -> out g "ignore ("; f (); out g ")"

let finish_unit g mode f = match mode with
	| MV -> out g "("; f (); out g "; VNull)"
	| MC -> out g "("; f (); out g "; false)"
	| MS -> f ()

let check_stack_depth g = out g "E.check_stack_depth jenv; "

let set_leave g p =
	let k = pos g p in
	out g ("jenv.env_leave_pmin <- " ^ k ^ ".pmin; jenv.env_leave_pmax <- " ^ k ^ ".pmax; ")

let ocaml_list sl = "[" ^ (String.concat "; " sl) ^ "]"

(* The OCaml code applying a binary operator to two bound operands. The integer fast paths
   return exactly what EvalMisc's operators return for two VInt32. *)
let rec binop_fun g op p =
	let p = pos g p in
	let int_fast ocaml_op generic = fun s1 s2 ->
		Printf.sprintf "(match %s, %s with VInt32 jx_p, VInt32 jx_q -> VInt32 (%s) | _ -> %s %s %s %s)" s1 s2 ocaml_op generic p s1 s2
	in
	let shift ocaml_fn generic = fun s1 s2 ->
		Printf.sprintf "(match %s, %s with VInt32 jx_p, VInt32 jx_q -> VInt32 (%s jx_p (Int32.to_int (Int32.logand jx_q 31l))) | _ -> %s %s %s %s)" s1 s2 ocaml_fn generic p s1 s2
	in
	match op with
	| OpAdd -> int_fast "Int32.add jx_p jx_q" "M.op_add"
	| OpSub -> int_fast "Int32.sub jx_p jx_q" "M.op_sub"
	| OpMult -> int_fast "Int32.mul jx_p jx_q" "M.op_mult"
	| OpAnd -> int_fast "Int32.logand jx_p jx_q" "M.op_and"
	| OpOr -> int_fast "Int32.logor jx_p jx_q" "M.op_or"
	| OpXor -> int_fast "Int32.logxor jx_p jx_q" "M.op_xor"
	| OpShl -> shift "Int32.shift_left" "M.op_shl"
	| OpShr -> shift "Int32.shift_right" "M.op_shr"
	| OpUShr -> shift "Int32.shift_right_logical" "M.op_ushr"
	| OpDiv -> (fun s1 s2 -> Printf.sprintf "(M.op_div %s %s %s)" p s1 s2)
	| OpMod -> (fun s1 s2 -> Printf.sprintf "(M.op_mod %s %s %s)" p s1 s2)
	| OpEq | OpNotEq | OpGt | OpGte | OpLt | OpLte ->
		(fun s1 s2 -> Printf.sprintf "(if %s then VTrue else VFalse)" (comparison op s1 s2))
	| OpAssign | OpBoolAnd | OpBoolOr | OpAssignOp _ | OpInterval | OpArrow | OpIn | OpNullCoal ->
		unsupported "binop function"

(* A comparison of two bound operands, as an OCaml bool. *)
and comparison op s1 s2 =
	let int_cmp o generic =
		(* A typed comparison of int32 compiles inline; Int32.compare would be a C call. *)
		Printf.sprintf "(match %s, %s with VInt32 jx_p, VInt32 jx_q -> (jx_p : int32) %s jx_q | _ -> %s)" s1 s2 o generic
	in
	match op with
	| OpEq -> int_cmp "=" (Printf.sprintf "equals %s %s" s1 s2)
	| OpNotEq -> int_cmp "<>" (Printf.sprintf "not (equals %s %s)" s1 s2)
	| OpGt -> int_cmp ">" (Printf.sprintf "M.compare %s %s = CSup" s1 s2)
	| OpGte -> int_cmp ">=" (Printf.sprintf "(match M.compare %s %s with CSup | CEq -> true | _ -> false)" s1 s2)
	| OpLt -> int_cmp "<" (Printf.sprintf "M.compare %s %s = CInf" s1 s2)
	| OpLte -> int_cmp "<=" (Printf.sprintf "(match M.compare %s %s with CInf | CEq -> true | _ -> false)" s1 s2)
	| _ -> Globals.die "" __LOC__

(* What evalJit compiles an expression as: parentheses, metadata and casts to nothing are skipped. *)
let rec skip_wrappers e = match e.eexpr with
	| TParenthesis e1 | TMeta(_,e1) | TCast(e1,None) -> skip_wrappers e1
	| _ -> e

(* The array of an Array.length read. *)
let array_length_of e = match (skip_wrappers e).eexpr with
	| TField(ea,FInstance({cl_path=([],"Array")},_,{cf_name="length"})) -> Some ea
	| _ -> None

(* Binds the value of [e] to a fresh name, in evaluation order, and continues with [k]. *)
let rec bind g env e k =
	match atom g env e with
	| Some s -> k s
	| None ->
		let t = fresh g "jt" in
		out g ("(let " ^ t ^ " = ");
		gen g env MV false e;
		out g " in ";
		k t;
		out g ")"

and bind_list g env el k = match el with
	| [] -> k []
	| e :: el -> bind g env e (fun s -> bind_list g env el (fun sl -> k (s :: sl)))

(* emit_null_check *)
and null_checked g env e k =
	let p = pos g e.epos in
	let t = fresh g "jt" in
	out g ("(let " ^ t ^ " = (match ");
	gen g env MV false e;
	out g (" with VNull -> M.throw_string \"Null Access\" " ^ p ^ " | jx_v -> jx_v) in ");
	k t;
	out g ")"

(* The closure compiler compiles some sub-expressions it never evaluates; compiling them can
   still fail (and so fail the whole function), so do the same here and drop the code. *)
and check_compilable g env e =
	let saved = g.b in
	g.b <- Buffer.create 256;
	Std.finally (fun () -> g.b <- saved) (fun () -> gen g env MV false e) ()

(* [gen g env mode ret e] writes the code of [e] in [mode]. [ret] is evalJit's return flag: the
   expression is in tail position of its function, where a return is just its value. *)
and gen g env mode ret e =
	g.nodes <- g.nodes + 1;
	if ret && mode <> MV then Globals.die "" __LOC__;
	let value f = finish_value g mode f in
	let boolean f = finish_bool g mode f in
	let unit f = finish_unit g mode f in
	match e.eexpr with
	(* objects and values *)
	| TVar _ ->
		(* A declaration outside of a block: nothing can see it past this point. *)
		gen_block g env mode ret [e]
	| TConst TSuper ->
		unsupported "super outside of a call"
	| TConst _ ->
		begin match atom g env e with
			| Some s -> value (fun () -> out g s)
			| None -> Globals.die "" __LOC__
		end
	| TObjectDecl fl ->
		let hl = List.map (fun ((s,_,_),e) -> hash s,e) fl in
		let pi = req_index g (RObjectProto (List.map (fun (s,_) -> s,()) hl)) in
		let fields = List.map (fun (s,e') -> req g (RInstanceFieldIndex(pi,s,e.epos)),e') hl in
		let oproto = req g (ROProto pi) in
		value (fun () ->
			let a = fresh g "jt" in
			out g ("(let " ^ a ^ " = Array.make " ^ string_of_int (List.length fields) ^ " VNull in ");
			List.iter (fun (i,e) ->
				out g (a ^ ".(" ^ i ^ ") <- ");
				gen g env MV false e;
				out g "; "
			) fields;
			out g ("VObject { ofields = " ^ a ^ "; oproto = " ^ oproto ^ " })")
		)
	| TArrayDecl el when List.length el > 8 ->
		(* emit_array_declaration evaluates the elements in order into a new array. With many
		   elements, fill a preallocated array instead of binding them all first: that would keep
		   one live value per element, and ocamlopt cannot address stack frames past 32KB. *)
		value (fun () ->
			let a = fresh g "jt" in
			out g ("(let " ^ a ^ " = Array.make " ^ string_of_int (List.length el) ^ " VNull in ");
			List.iteri (fun i e ->
				out g (a ^ ".(" ^ string_of_int i ^ ") <- ");
				gen g env MV false e;
				out g "; "
			) el;
			out g ("VArray (A.create " ^ a ^ "))")
		)
	| TArrayDecl el ->
		value (fun () ->
			bind_list g env el (fun sl ->
				out g ("(VArray (A.create [|" ^ (String.concat "; " sl) ^ "|]))")
			)
		)
	| TTypeExpr mt ->
		let key = path_hash (t_infos mt).mt_path in
		let v = req g (RStaticProtoValue(key,e.epos)) in
		value (fun () -> out g v)
	| TFunction tf ->
		value (fun () -> gen_closure g env e tf)
	(* branching *)
	| TIf(e1,e2,eo) ->
		out g "(if ";
		gen g env MC false e1;
		out g " then ";
		gen g env mode ret e2;
		out g " else ";
		begin match eo with
			| None -> out g (unit_of_mode mode)
			| Some e3 -> gen g env mode ret e3
		end;
		out g ")"
	| TSwitch sw when (let e1,cases,_ = switch_parts sw in is_int e1.etype && List.for_all is_const_int_pattern cases) ->
		let e1,cases,def = switch_parts sw in
		(* emit_int_switch_array / emit_int_switch_map. evalJit adds the cases to a map in order, so
		   a constant listed by several cases selects the last of them. *)
		let last = Hashtbl.create 0 in
		List.iteri (fun ci (el,_) ->
			List.iter (fun e -> match e.eexpr with
				| TConst (TInt i32) -> Hashtbl.replace last (Int32.to_int i32) ci
				| _ -> Globals.die "" __LOC__
			) el
		) cases;
		let by_case = Hashtbl.create 0 in
		Hashtbl.iter (fun i ci -> Hashtbl.replace by_case ci (i :: (try Hashtbl.find by_case ci with Not_found -> []))) last;
		let p = pos g e1.epos in
		let k = fresh g "jt" in
		let arms () =
			List.iteri (fun ci _ ->
				match (try Hashtbl.find by_case ci with Not_found -> []) with
				| [] -> ()
				| il ->
					let il = List.sort compare il in
					out g ((String.concat " | " (List.map (fun i -> "(" ^ string_of_int i ^ ")") il)) ^ " -> " ^ string_of_int ci ^ " | ")
			) cases
		in
		begin match (skip_wrappers e1).eexpr with
		| TEnumIndex e0 ->
			(* A switch on an enum's index (how matching on an enum compiles): emit_enum_index boxes the
			   index and the switch unboxes it; dispatch on it directly. A non-enum fails as
			   as_enum_value fails. *)
			let p0 = pos g e0.epos in
			out g ("(let " ^ k ^ " = (match ");
			gen g env MV false e0;
			out g " with VEnumValue jx_ev -> (match jx_ev.eindex with ";
			arms ();
			out g ("_ -> -1) | jx_v -> E.unexpected_value_p jx_v \"enum value\" " ^ p0 ^ ") in (match " ^ k ^ " with ");
			ignore p
		| _ ->
			out g ("(let " ^ k ^ " = (match ");
			gen g env MV false e1;
			out g " with VInt32 jx_i -> (match Int32.to_int jx_i with ";
			arms ();
			out g ("_ -> -1) | VNull -> -1 | jx_v -> E.unexpected_value_p jx_v \"int\" " ^ p ^ ") in (match " ^ k ^ " with ");
		end;
		List.iteri (fun ci (_,body) ->
			if Hashtbl.mem by_case ci then begin
				out g (string_of_int ci ^ " -> ");
				gen g env mode ret body;
				out g " | "
			end else
				(* A case every constant of which a later case took: never selected, but compiled. *)
				check_compilable_mode g env mode ret body
		) cases;
		out g "_ -> ";
		gen_default g env mode ret def;
		out g "))"
	| TSwitch sw when (let e1,cases,_ = switch_parts sw in is_string e1.etype && List.for_all is_const_string_pattern cases) ->
		let e1,cases,def = switch_parts sw in
		(* emit_switch compares with EvalValue.equals, pattern by pattern. For constant strings and a
		   VString that is a comparison of bytes, so match on those. Other values take the general
		   path. *)
		let t = fresh g "jt" in
		let k = fresh g "jt" in
		out g ("(let " ^ t ^ " = ");
		gen g env MV false e1;
		out g (" in let " ^ k ^ " = (match " ^ t ^ " with VString jx_s -> (match jx_s.sstring with ");
		List.iteri (fun ci (el,_) ->
			List.iter (fun e -> match e.eexpr with
				| TConst (TString s) -> out g (ocaml_string s ^ " -> " ^ string_of_int ci ^ " | ")
				| _ -> Globals.die "" __LOC__
			) el
		) cases;
		out g "_ -> -1) | _ -> ";
		List.iteri (fun ci (el,_) ->
			let conds = List.map (fun e -> match e.eexpr with
				| TConst (TString s) -> "equals " ^ t ^ " " ^ req g (RString s)
				| _ -> Globals.die "" __LOC__
			) el in
			out g ("if " ^ (match conds with [] -> "false" | _ -> String.concat " || " conds) ^ " then " ^ string_of_int ci ^ " else ")
		) cases;
		out g ("-1) in (match " ^ k ^ " with ");
		List.iteri (fun ci (_,body) ->
			out g (string_of_int ci ^ " -> ");
			gen g env mode ret body;
			out g " | "
		) cases;
		out g "_ -> ";
		gen_default g env mode ret def;
		out g "))"
	| TSwitch sw ->
		let e1,cases,def = switch_parts sw in
		(* emit_switch *)
		let t = fresh g "jt" in
		out g ("(let " ^ t ^ " = ");
		gen g env MV false e1;
		out g " in ";
		List.iter (fun (el,body) ->
			out g "if ";
			begin match el with
				| [] -> out g "false"
				| _ ->
					List.iteri (fun i ep ->
						if i > 0 then out g " || ";
						out g ("(equals " ^ t ^ " ");
						gen g env MV false ep;
						out g ")"
					) el
			end;
			out g " then ";
			gen g env mode ret body;
			out g " else "
		) cases;
		gen_default g env mode ret def;
		out g ")"
	| TWhile({eexpr = TParenthesis e1},e2,flag) ->
		gen g env mode ret {e with eexpr = TWhile(e1,e2,flag)}
	| TWhile(e1,e2,flag) ->
		let rec has_continue e = match e.eexpr with
			| TContinue -> true
			| TWhile _ | TFunction _ -> false
			| _ -> check_expr has_continue e
		in
		unit (fun () ->
			begin match flag with
			| NormalWhile ->
				out g "(try while ";
				gen g env MC false e1;
				out g " do ";
				if has_continue e2 then begin
					out g "(try ";
					gen g env MS false e2;
					out g " with X.Continue -> ())"
				end else
					gen g env MS false e2;
				out g " done with X.Break -> ())"
			| DoWhile ->
				(* emit_do_while_break_continue: the body runs once before the condition is tested. *)
				out g "(try let jx_first = ref true in while (if !jx_first then (jx_first := false; true) else ";
				gen g env MC false e1;
				out g ") do (try ";
				gen g env MS false e2;
				out g " with X.Continue -> ()) done with X.Break -> ())"
			end
		)
	| TTry(e1,catches) ->
		(* emit_try *)
		let keys = List.map (fun (v,_) -> hash (rope_path v.v_type)) catches in
		value (fun () ->
			out g "(R.try_catch jenv (fun () -> ";
			gen g env MV ret e1;
			out g ") [|";
			List.iteri (fun i ((v,body),key) ->
				if i > 0 then out g "; ";
				out g ("(" ^ string_of_int key ^ ", (fun jx_exc -> ");
				let env = declare g env v "jx_exc" in
				gen g env MV ret body;
				out g "))"
			) (List.combine catches keys);
			out g "|])"
		)
	(* control flow *)
	| TBlock el ->
		gen_block g env mode ret el
	| TReturn None ->
		if ret then
			value (fun () -> out g "VNull")
		else begin
			g.fn.fn_has_nonfinal_return <- true;
			out g "(raise_notrace (X.Return VNull))"
		end
	| TReturn (Some e1) ->
		if ret then
			gen g env MV false e1
		else begin
			g.fn.fn_has_nonfinal_return <- true;
			out g "(raise_notrace (X.Return ";
			gen g env MV false e1;
			out g "))"
		end
	| TBreak ->
		out g "(raise_notrace X.Break)"
	| TContinue ->
		out g "(raise_notrace X.Continue)"
	| TThrow e1 ->
		let p = pos g e.epos in
		bind g env e1 (fun s -> out g ("(C.throw " ^ s ^ " " ^ p ^ ")"))
	| TCast(e1,Some mt) ->
		let key = hash (rope_path (type_of_module_type mt)) in
		let p = pos g e.epos in
		value (fun () ->
			bind g env e1 (fun s -> out g ("(R.safe_cast " ^ s ^ " " ^ string_of_int key ^ " " ^ p ^ ")"))
		)
	(* calls *)
	| TCall(e1,el) ->
		value (fun () -> gen_call g env e e1 el)
	| TNew({cl_path=[],"Array"},_,_) ->
		value (fun () -> out g "(VArray (A.create [||]))")
	| TNew({cl_path=["eval"],"Vector"},_,[e1]) ->
		let p = pos g e1.epos in
		value (fun () ->
			match e1.eexpr with
			| TConst (TInt i32) ->
				out g ("(R.new_vector_int (" ^ string_of_int (Int32.to_int i32) ^ ") " ^ p ^ ")")
			| _ ->
				bind g env e1 (fun s -> out g ("(R.new_vector_int (E.decode_int_p " ^ s ^ " " ^ p ^ ") " ^ p ^ ")"))
		)
	| TNew(c,_,el) ->
		let key = path_hash c.cl_path in
		value (fun () ->
			if IntHashtbl.mem (get_ctx()).builtins.constructor_builtins key then begin
				(* emit_special_instance *)
				let f = req g (RSpecialCtor key) in
				bind_list g env el (fun sl -> out g ("(" ^ f ^ " " ^ ocaml_list sl ^ ")"))
			end else begin
				(* emit_constructor_call *)
				let lz = req g (RCtorLazy(key,e.epos,e.epos)) in
				let proto = req g (RInstanceProto(key,e.epos)) in
				out g "(";
				check_stack_depth g;
				out g ("let jx_f = Lazy.force " ^ lz ^ " in let jx_o = N.create_instance_direct " ^ proto ^ " INormal in ");
				bind_list g env el (fun sl ->
					set_leave g e.epos;
					out g ("ignore (jx_f (jx_o :: " ^ ocaml_list sl ^ ")); jx_o")
				);
				out g ")"
			end
		)
	(* read *)
	| TLocal v ->
		let s = var_read env v in
		value (fun () -> out g s)
	| TField(e1,fa) ->
		value (fun () -> gen_field_read g env e1 fa)
	| TArray(e1,e2) ->
		(* emit_array_read / emit_vector_read *)
		let p1 = pos g e1.epos and p2 = pos g e2.epos in
		let vector = is_vector e1.etype in
		value (fun () ->
			bind g env e1 (fun s1 ->
				out g ("(let jx_a = " ^ (if vector then "E.as_vector " else "E.as_array ") ^ p1 ^ " " ^ s1 ^ " in ");
				bind g env e2 (fun s2 ->
					out g ("let jx_i = E.as_int " ^ p2 ^ " " ^ s2 ^ " in if jx_i < 0 then VNull else " ^ (if vector then "Array.unsafe_get jx_a jx_i" else "A.get jx_a jx_i"))
				);
				out g ")"
			)
		)
	| TEnumParameter(e1,_,i) ->
		value (fun () ->
			bind g env e1 (fun s ->
				out g ("(match " ^ s ^ " with VEnumValue jx_ev -> jx_ev.eargs.(" ^ string_of_int i ^ ") | jx_v -> X.unexpected_value jx_v \"enum value\")")
			)
		)
	| TEnumIndex e1 ->
		let p = pos g e1.epos in
		value (fun () ->
			bind g env e1 (fun s ->
				out g ("(vint (E.as_enum_value " ^ p ^ " " ^ s ^ ").eindex)")
			)
		)
	(* ops *)
	| TBinop(OpEq,e1,{eexpr = TConst TNull}) | TBinop(OpEq,{eexpr = TConst TNull},e1) ->
		boolean (fun () ->
			bind g env e1 (fun s -> out g ("(match " ^ s ^ " with VNull -> true | _ -> false)"))
		)
	| TBinop(OpNotEq,e1,{eexpr = TConst TNull}) | TBinop(OpNotEq,{eexpr = TConst TNull},e1) ->
		boolean (fun () ->
			bind g env e1 (fun s -> out g ("(match " ^ s ^ " with VNull -> false | _ -> true)"))
		)
	| TBinop(op,e1,e2) ->
		begin match op with
		| OpAssign ->
			gen_assign g env mode e1 e2
		| OpAssignOp op ->
			gen_assign_op g env mode (binop_fun g op e.epos) e1 e2 true
		| OpBoolAnd ->
			(* emit_bool_and: the value is the right operand's, not a boolean. *)
			begin match mode with
			| MC ->
				out g "(";
				gen g env MC false e1;
				out g " && ";
				gen g env MC false e2;
				out g ")"
			| MV ->
				out g "(if ";
				gen g env MC false e1;
				out g " then ";
				gen g env MV false e2;
				out g " else VFalse)"
			| MS ->
				out g "(if ";
				gen g env MC false e1;
				out g " then ";
				gen g env MS false e2;
				out g ")"
			end
		| OpBoolOr ->
			begin match mode with
			| MC ->
				out g "(";
				gen g env MC false e1;
				out g " || ";
				gen g env MC false e2;
				out g ")"
			| MV ->
				out g "(if ";
				gen g env MC false e1;
				out g " then VTrue else ";
				gen g env MV false e2;
				out g ")"
			| MS ->
				out g "(if ";
				gen g env MC false e1;
				out g " then () else ";
				gen g env MS false e2;
				out g ")"
			end
		| OpEq | OpNotEq | OpGt | OpGte | OpLt | OpLte ->
			(* With an array's length on one side (a loop's condition, typically) the length is compared
			   as an int instead of being boxed first; other values take the general comparison with
			   the boxed length, so the result is emit_op_*'s. *)
			let int_op = match op with
				| OpEq -> "=" | OpNotEq -> "<>" | OpGt -> ">" | OpGte -> ">=" | OpLt -> "<" | OpLte -> "<="
				| _ -> Globals.die "" __LOC__
			in
			let length_code ea k =
				let p = pos g ea.epos in
				bind g env ea (fun sa ->
					out g ("(let jx_n = (E.as_array " ^ p ^ " " ^ sa ^ ").alength in ");
					k "jx_n";
					out g ")"
				)
			in
			begin match array_length_of e2,array_length_of e1 with
			| Some ea,_ ->
				boolean (fun () ->
					bind g env e1 (fun s1 ->
						length_code ea (fun n ->
							out g (Printf.sprintf "(match %s with VInt32 jx_p -> Int32.to_int jx_p %s %s | _ -> %s)" s1 int_op n (comparison op s1 ("(vint " ^ n ^ ")")))
						)
					)
				)
			| None,Some ea ->
				boolean (fun () ->
					length_code ea (fun n ->
						bind g env e2 (fun s2 ->
							out g (Printf.sprintf "(match %s with VInt32 jx_q -> %s %s Int32.to_int jx_q | _ -> %s)" s2 n int_op (comparison op ("(vint " ^ n ^ ")") s2))
						)
					)
				)
			| None,None ->
				boolean (fun () ->
					bind g env e1 (fun s1 ->
						bind g env e2 (fun s2 -> out g (comparison op s1 s2))
					)
				)
			end
		| OpAdd | OpMult | OpDiv | OpSub | OpAnd | OpOr | OpXor | OpShl | OpShr | OpUShr | OpMod ->
			let f = binop_fun g op e.epos in
			value (fun () ->
				bind g env e1 (fun s1 ->
					bind g env e2 (fun s2 -> out g (f s1 s2))
				)
			)
		| OpInterval | OpArrow | OpIn | OpNullCoal ->
			unsupported "binop"
		end
	| TUnop(op,flag,e1) ->
		gen_unop g env mode op flag e1 e.epos
	(* rewrites/skips *)
	| TParenthesis e1 | TMeta(_,e1) | TCast(e1,None) ->
		gen g env mode ret e1
	| TIdent "$__mk_pos__" ->
		(* emit_mk_pos: a new value of the identifier's own position every time. *)
		let p = pos g e.epos in
		value (fun () -> out g ("(N.encode_pos " ^ p ^ ")"))
	| TIdent s ->
		unsupported ("identifier " ^ s)

and check_compilable_mode g env mode ret e =
	let saved = g.b in
	g.b <- Buffer.create 256;
	Std.finally (fun () -> g.b <- saved) (fun () -> gen g env mode ret e) ()

and gen_default g env mode ret def = match def with
	| None -> out g (unit_of_mode mode)
	| Some e -> gen g env mode ret e

(* A block: a declaration scopes over the rest of it. *)
and gen_block g env mode ret el =
	(* evalJit declares a variable in the innermost scope, and only blocks, cases, catches and
	   functions open one: a declaration under metadata or parentheses is still the block's. *)
	let rec declaration e = match e.eexpr with
		| TVar(v,eo) -> Some (v,eo)
		| TMeta(_,e1) | TParenthesis e1 | TCast(e1,None) -> declaration e1
		| _ -> None
	in
	let rec loop env el = match el with
		| [] ->
			out g (unit_of_mode mode)
		| e :: el ->
			match declaration e,el with
			| Some (v,eo),[] ->
				gen_var g env v eo (fun _ -> out g (unit_of_mode mode))
			| Some (v,eo),_ ->
				gen_var g env v eo (fun env -> loop env el)
			| None,[] ->
				gen g env mode ret e
			| None,_ ->
				gen g env MS false e;
				out g "; ";
				loop env el
	in
	out g "(";
	loop env el;
	out g ")"

and gen_var g env v eo k =
	let name = fresh g "jv" in
	let mut = Hashtbl.mem g.fn.fn_written v.v_id in
	out g ("let " ^ name ^ " = ");
	if mut then out g "ref (";
	begin match eo with
		| None -> out g "VNull"
		| Some e -> gen g env MV false e
	end;
	if mut then out g ")";
	out g " in ";
	k (IntMap.add v.v_id (if mut then Mut name else Imm name) env)

(* Declares [v] with the value of the OCaml variable [s]. *)
and declare g env v s =
	let name = fresh g "jv" in
	if Hashtbl.mem g.fn.fn_written v.v_id then begin
		out g ("let " ^ name ^ " = ref " ^ s ^ " in ");
		IntMap.add v.v_id (Mut name) env
	end else begin
		out g ("let " ^ name ^ " = " ^ s ^ " in ");
		IntMap.add v.v_id (Imm name) env
	end

and gen_unop g env mode op flag e1 p =
	let value f = finish_value g mode f in
	match op with
	| Not ->
		begin match mode with
		| MC ->
			out g "(match ";
			gen g env MV false e1;
			out g " with VNull | VFalse -> true | _ -> false)"
		| _ ->
			value (fun () ->
				out g "(match ";
				gen g env MV false e1;
				out g " with VNull | VFalse -> VTrue | _ -> VFalse)"
			)
		end
	| Neg ->
		let p = pos g p in
		value (fun () ->
			out g "(match ";
			gen g env MV false e1;
			out g (" with VFloat jx_f -> VFloat (-. jx_f) | VInt32 jx_i -> VInt32 (Int32.neg jx_i) | _ -> M.throw_string \"Invalid operation\" " ^ p ^ ")")
		)
	| NegBits ->
		(* emit_op_sub with -1 as the left operand *)
		let f = binop_fun g OpSub p in
		value (fun () ->
			out g "(let jx_t = ";
			gen g env MV false e1;
			out g (" in " ^ f "(VInt32 (-1l))" "jx_t" ^ ")")
		)
	| Increment ->
		begin match Texpr.skip e1 with
		| {eexpr = TLocal v} when not (has_var_flag v VCaptured) ->
			(* emit_local_incr_prefix / emit_local_incr_postfix *)
			let r = var_ref env v in
			let p = pos g e1.epos in
			value (fun () ->
				if flag = Prefix then
					out g ("(let jx_v = E.do_incr !" ^ r ^ " " ^ p ^ " in " ^ r ^ " := jx_v; jx_v)")
				else
					out g ("(let jx_v0 = !" ^ r ^ " in let jx_v = E.do_incr jx_v0 " ^ p ^ " in " ^ r ^ " := jx_v; jx_v0)")
			)
		| _ ->
			gen_assign_op g env mode (binop_fun g OpAdd p) e1 (mk (TConst (TInt Int32.one)) t_dynamic null_pos) (flag = Prefix)
		end
	| Decrement ->
		gen_assign_op g env mode (binop_fun g OpSub p) e1 (mk (TConst (TInt Int32.one)) t_dynamic null_pos) (flag = Prefix)
	| Spread ->
		begin match flag with
		| Postfix -> unsupported "postfix spread"
		| Prefix -> gen g env mode false e1
		end

and gen_assign g env mode e1 e2 =
	let value f = finish_value g mode f in
	match e1.eexpr with
	| TLocal v ->
		(* emit_local_write / emit_capture_write *)
		let r = var_ref env v in
		begin match mode with
		| MS ->
			out g ("(" ^ r ^ " := ");
			gen g env MV false e2;
			out g ")"
		| _ ->
			value (fun () ->
				bind g env e2 (fun s -> out g ("(" ^ r ^ " := " ^ s ^ "; " ^ s ^ ")"))
			)
		end
	| TField(ef,fa) ->
		let name = hash (field_name fa) in
		begin match fa with
			| FInstance({cl_path=(["haxe";"io"],"Bytes")},_,{cf_name="length"}) ->
				(* emit_bytes_length_write *)
				value (fun () ->
					bind g env ef (fun s1 ->
						bind g env e2 (fun s2 -> out g ("(M.set_bytes_length_field " ^ s1 ^ " " ^ s2 ^ "; " ^ s2 ^ ")"))
					)
				)
			| FStatic({cl_path=path},_) | FEnum({e_path=path},_) ->
				(* emit_proto_field_write: the type expression is compiled but not evaluated. *)
				check_compilable g env ef;
				let pi = req_index g (RStaticProto(path_hash path,ef.epos)) in
				let i = req g (RProtoFieldIndex(pi,name)) in
				value (fun () ->
					bind g env e2 (fun s -> out g ("(jk" ^ string_of_int pi ^ ".pfields.(" ^ i ^ ") <- " ^ s ^ "; " ^ s ^ ")"))
				)
			| FInstance(c,_,_) when not (has_class_flag c CInterface) ->
				(* emit_instance_field_write: the value is evaluated only for an instance. *)
				let pi = req_index g (RInstanceProto(path_hash c.cl_path,ef.epos)) in
				let i = req g (RInstanceFieldIndex(pi,name,ef.epos)) in
				let p = pos g ef.epos in
				value (fun () ->
					bind g env ef (fun s1 ->
						out g ("(match " ^ s1 ^ " with VInstance jx_vi -> ");
						bind g env e2 (fun s2 -> out g ("(jx_vi.ifields.(" ^ i ^ ") <- " ^ s2 ^ "; " ^ s2 ^ ")"));
						out g (" | jx_v -> E.unexpected_value_p jx_v \"instance\" " ^ p ^ ")")
					)
				)
			| FAnon _ when (match follow ef.etype with TAnon _ -> true | _ -> false) ->
				(* emit_anon_field_write *)
				let an = match follow ef.etype with TAnon an -> an | _ -> Globals.die "" __LOC__ in
				let l = PMap.foldi (fun k _ acc -> (hash k,()) :: acc) an.a_fields [] in
				let pi = req_index g (RObjectProto l) in
				let i = req g (RInstanceFieldIndex(pi,name,ef.epos)) in
				let p = pos g ef.epos in
				value (fun () ->
					bind g env ef (fun s1 ->
						bind g env e2 (fun s2 ->
							out g (Printf.sprintf "(R.anon_field_write %s %s jk%d %s %d %s)" s1 p pi i name s2)
						)
					)
				)
			| _ ->
				(* emit_field_write *)
				let p = pos g e1.epos in
				value (fun () ->
					bind g env ef (fun s1 ->
						bind g env e2 (fun s2 ->
							out g (Printf.sprintf "(R.field_write %s %s %d %s)" s1 p name s2)
						)
					)
				)
		end
	| TArray(ea1,ea2) ->
		(* emit_array_write / emit_vector_write *)
		let p1 = pos g ea1.epos and p2 = pos g ea2.epos in
		let vector = is_vector ea1.etype in
		value (fun () ->
			bind g env ea1 (fun s1 ->
				out g ("(let jx_a = " ^ (if vector then "E.as_vector " else "E.as_array ") ^ p1 ^ " " ^ s1 ^ " in ");
				bind g env ea2 (fun s2 ->
					out g ("let jx_i = E.as_int " ^ p2 ^ " " ^ s2 ^ " in ");
					bind g env e2 (fun s3 ->
						let neg = if vector then "Negative vector index: %i" else "Negative array index: %i" in
						out g ("(if jx_i < 0 then M.throw_string (Printf.sprintf " ^ ocaml_string neg ^ " jx_i) " ^ p2 ^ "); ");
						out g ((if vector then "Array.unsafe_set jx_a jx_i " else "A.set jx_a jx_i ") ^ s3 ^ "; " ^ s3)
					)
				);
				out g ")"
			)
		)
	| _ ->
		unsupported "assignment target"

(* Compound assignment, increment and decrement. [fop] builds the code applying the operator to
   the old value and the right operand. *)
and gen_assign_op g env mode fop e1 e2 prefix =
	let value f = finish_value g mode f in
	let result old nw = if prefix then nw else old in
	match e1.eexpr with
	| TLocal v ->
		(* emit_local_read_write / emit_capture_read_write *)
		let r = var_ref env v in
		value (fun () ->
			out g ("(let jx_old = !" ^ r ^ " in ");
			bind g env e2 (fun s2 ->
				out g ("let jx_v = " ^ fop "jx_old" s2 ^ " in " ^ r ^ " := jx_v; " ^ result "jx_old" "jx_v")
			);
			out g ")"
		)
	| TField(ef,fa) ->
		let name = hash (field_name fa) in
		begin match fa with
			| FStatic({cl_path=path},_) ->
				(* emit_proto_field_read_write *)
				check_compilable g env ef;
				let pi = req_index g (RStaticProto(path_hash path,ef.epos)) in
				let i = req g (RProtoFieldIndex(pi,name)) in
				let proto = "jk" ^ string_of_int pi in
				value (fun () ->
					out g ("(let jx_old = " ^ proto ^ ".pfields.(" ^ i ^ ") in ");
					bind g env e2 (fun s2 ->
						out g ("let jx_v = " ^ fop "jx_old" s2 ^ " in " ^ proto ^ ".pfields.(" ^ i ^ ") <- jx_v; " ^ result "jx_old" "jx_v")
					);
					out g ")"
				)
			| FInstance(c,_,_) when not (has_class_flag c CInterface) ->
				(* emit_instance_field_read_write *)
				let pi = req_index g (RInstanceProto(path_hash c.cl_path,ef.epos)) in
				let i = req g (RInstanceFieldIndex(pi,name,ef.epos)) in
				let p = pos g ef.epos in
				value (fun () ->
					bind g env ef (fun s1 ->
						out g ("(match " ^ s1 ^ " with VInstance jx_vi -> (let jx_old = jx_vi.ifields.(" ^ i ^ ") in ");
						bind g env e2 (fun s2 ->
							out g ("let jx_v = " ^ fop "jx_old" s2 ^ " in jx_vi.ifields.(" ^ i ^ ") <- jx_v; " ^ result "jx_old" "jx_v")
						);
						out g (") | jx_v -> E.unexpected_value_p jx_v \"instance\" " ^ p ^ ")")
					)
				)
			| _ ->
				(* emit_field_read_write *)
				let p = pos g e1.epos in
				value (fun () ->
					bind g env ef (fun s1 ->
						out g ("(R.field_read_write " ^ s1 ^ " " ^ p ^ " " ^ string_of_int name ^ " (fun () -> ");
						gen g env MV false e2;
						out g (") (fun jx_x jx_y -> " ^ fop "jx_x" "jx_y" ^ ") " ^ (if prefix then "true" else "false") ^ ")")
					)
				)
		end
	| TArray(ea1,ea2) ->
		(* emit_array_read_write / emit_vector_read_write *)
		let p1 = pos g ea1.epos and p2 = pos g ea2.epos in
		let vector = is_vector ea1.etype in
		value (fun () ->
			bind g env ea1 (fun s1 ->
				out g ("(let jx_a = " ^ (if vector then "E.as_vector " else "E.as_array ") ^ p1 ^ " " ^ s1 ^ " in ");
				bind g env ea2 (fun s2 ->
					let neg = if vector then "Negative vector index: %i" else "Negative array index: %i" in
					out g ("let jx_i = E.as_int " ^ p2 ^ " " ^ s2 ^ " in ");
					out g ("(if jx_i < 0 then M.throw_string (Printf.sprintf " ^ ocaml_string neg ^ " jx_i) " ^ p2 ^ "); ");
					out g ("let jx_old = " ^ (if vector then "Array.unsafe_get jx_a jx_i" else "A.get jx_a jx_i") ^ " in ");
					bind g env e2 (fun s3 ->
						out g ("let jx_v = " ^ fop "jx_old" s3 ^ " in " ^ (if vector then "Array.unsafe_set jx_a jx_i jx_v; " else "A.set jx_a jx_i jx_v; ") ^ result "jx_old" "jx_v")
					)
				);
				out g ")"
			)
		)
	| _ ->
		unsupported "compound assignment target"

and gen_field_read g env e1 fa =
	let name = hash (field_name fa) in
	match fa with
	| FInstance({cl_path=([],"Array")},_,{cf_name="length"}) ->
		let p = pos g e1.epos in
		bind g env e1 (fun s -> out g ("(vint (E.as_array " ^ p ^ " " ^ s ^ ").alength)"))
	| FInstance({cl_path=(["eval"],"Vector")},_,{cf_name="length"}) ->
		let p = pos g e1.epos in
		bind g env e1 (fun s -> out g ("(vint (Array.length (E.as_vector " ^ p ^ " " ^ s ^ ")))"))
	| FInstance({cl_path=(["haxe";"io"],"Bytes")},_,{cf_name="length"}) ->
		let p = pos g e1.epos in
		bind g env e1 (fun s -> out g ("(vint (Bytes.length (E.as_bytes " ^ p ^ " " ^ s ^ ")))"))
	| FStatic({cl_path=path},_) | FEnum({e_path=path},_)
	| FInstance({cl_path=path},_,{cf_kind = Method (MethNormal | MethInline)}) ->
		(* emit_proto_field_read; the object is not compiled. *)
		let pi = req_index g (RStaticProto(path_hash path,e1.epos)) in
		let i = req g (RProtoFieldIndex(pi,name)) in
		out g ("jk" ^ string_of_int pi ^ ".pfields.(" ^ i ^ ")")
	| FInstance(c,_,_) when not (has_class_flag c CInterface) ->
		let pi = req_index g (RInstanceProto(path_hash c.cl_path,e1.epos)) in
		let i = req g (RInstanceFieldIndex(pi,name,e1.epos)) in
		begin match e1.eexpr with
			| TConst TThis ->
				(* emit_this_field_read *)
				out g ("(match " ^ this_name g ^ " with VInstance jx_vi -> jx_vi.ifields.(" ^ i ^ ") | jx_v -> X.unexpected_value jx_v \"instance\")")
			| _ ->
				(* emit_instance_field_read *)
				let p = pos g e1.epos in
				bind g env e1 (fun s ->
					out g ("(match " ^ s ^ " with VInstance jx_vi -> jx_vi.ifields.(" ^ i ^ ") | VString jx_s -> vint jx_s.slength | VNull -> M.throw_string \"field access on null\" " ^ p ^ " | jx_v -> E.unexpected_value_p jx_v \"instance\" " ^ p ^ ")")
				)
		end
	| FAnon _ when (match follow e1.etype with TAnon _ -> true | _ -> false) ->
		(* emit_anon_field_read *)
		let an = match follow e1.etype with TAnon an -> an | _ -> Globals.die "" __LOC__ in
		let l = PMap.foldi (fun k _ acc -> (hash k,()) :: acc) an.a_fields [] in
		let pi = req_index g (RObjectProto l) in
		let i = req g (RInstanceFieldIndex(pi,name,e1.epos)) in
		let p = pos g e1.epos in
		bind g env e1 (fun s ->
			let cache = req g RFieldCache in
			out g (Printf.sprintf "(R.anon_field_read_cached %s %s jk%d %s %d %s)" cache s pi i name p)
		)
	| FClosure _ | FDynamic _ ->
		(* emit_field_closure *)
		let cache = req g RFieldCache in
		bind g env e1 (fun s -> out g ("(R.dynamic_field_cached " ^ cache ^ " " ^ s ^ " " ^ string_of_int name ^ ")"))
	| _ ->
		(* emit_field_read *)
		let p = pos g e1.epos in
		bind g env e1 (fun s ->
			let cache = req g RFieldCache in
			out g ("(match " ^ s ^ " with VNull -> M.throw_string \"field access on null\" " ^ p ^ " | jx_v -> R.field_cached " ^ cache ^ " jx_v " ^ string_of_int name ^ ")")
		)

and gen_call g env e e1 el =
	let ctx = g.ctx in
	match e1.eexpr with
	| TField({eexpr = TConst TSuper},FInstance(c,_,cf)) ->
		(* emit_super_field_call *)
		let this = this_name g in
		let pi = req_index g (RInstanceProto(path_hash c.cl_path,e1.epos)) in
		let i = req g (RProtoFieldIndex(pi,hash cf.cf_name)) in
		out g "(";
		check_stack_depth g;
		out g ("let jx_vf = jk" ^ string_of_int pi ^ ".pfields.(" ^ i ^ ") in ");
		bind_list g env el (fun sl -> out g ("P.call_value_on " ^ this ^ " jx_vf " ^ ocaml_list sl));
		out g ")"
	| TField(ef,fa) ->
		let name = hash (field_name fa) in
		let is_final c cf =
			has_class_flag c CFinal || (has_class_field_flag cf CfFinal) ||
			(not ctx.is_macro && not (Hashtbl.mem ctx.overrides (c.cl_path,cf.cf_name)))
		in
		(* emit_proto_field_call, on [ef] if given *)
		let proto_field_call lz ef =
			out g "(";
			check_stack_depth g;
			out g ("let jx_f = Lazy.force " ^ lz ^ " in ");
			let finish sl =
				set_leave g e.epos;
				out g ("jx_f " ^ ocaml_list sl)
			in
			begin match ef with
				| None -> bind_list g env el finish
				| Some ef -> null_checked g env ef (fun so -> bind_list g env el (fun sl -> finish (so :: sl)))
			end;
			out g ")"
		in
		let instance_call c =
			let pi = req_index g (RInstanceProto(path_hash c.cl_path,ef.epos)) in
			let lz = req g (RLazyProtoField(pi,name,e.epos)) in
			proto_field_call lz (Some ef)
		in
		let default () =
			(* emit_method_call *)
			let p = pos g e.epos in
			out g "(";
			check_stack_depth g;
			null_checked g env ef (fun so ->
				let cache = req g RCallCache in
				out g ("let jx_vf = R.method_field_cached " ^ cache ^ " " ^ so ^ " " ^ string_of_int name ^ " " ^ p ^ " in ");
				bind_list g env el (fun sl ->
					set_leave g e.epos;
					out g ("P.call_value_on " ^ so ^ " jx_vf " ^ ocaml_list sl)
				)
			);
			out g ")"
		in
		begin match fa with
			| FStatic({cl_path=[],"StringTools"},{cf_name="fastCodeAt"}) ->
				let p = pos g e.epos in
				begin match el with
					| [a;b] -> bind g env a (fun s1 -> bind g env b (fun s2 -> out g ("(R.string_cca " ^ s1 ^ " " ^ s2 ^ " " ^ p ^ ")")))
					| _ -> unsupported "fastCodeAt arity"
				end
			| FStatic({cl_path=[],"StringTools"},{cf_name="unsafeCodeAt"}) ->
				let p = pos g e.epos in
				begin match el with
					| [a;b] -> bind g env a (fun s1 -> bind g env b (fun s2 -> out g ("(R.string_cca_unsafe " ^ s1 ^ " " ^ s2 ^ " " ^ p ^ ")")))
					| _ -> unsupported "unsafeCodeAt arity"
				end
			| FEnum({e_path=path},ef) ->
				(* emit_enum_construction *)
				let key = path_hash path in
				let sp = req g (RSomePos e.epos) in
				bind_list g env el (fun sl ->
					out g ("(N.encode_enum_value " ^ string_of_int key ^ " " ^ string_of_int ef.ef_index ^ " [|" ^ (String.concat "; " sl) ^ "|] " ^ sp ^ ")")
				)
			| FStatic({cl_path=path},cf) when is_proper_method cf ->
				let pi = req_index g (RStaticProto(path_hash path,ef.epos)) in
				let lz = req g (RLazyProtoField(pi,name,e.epos)) in
				proto_field_call lz None
			| FInstance(c,_,cf) when is_proper_method cf ->
				if not (is_final c cf) then
					default()
				else if not (has_class_flag c CInterface) then
					instance_call c
				else if not ctx.is_macro && c.cl_implements = [] && c.cl_super = None then begin match c.cl_descendants with
					| [c'] when not (has_class_flag c' CInterface) && is_final c' cf ->
						instance_call c'
					| _ ->
						default()
				end else
					default()
			| _ ->
				(* emit_field_call: the leave position is recorded before the arguments. *)
				out g "(";
				check_stack_depth g;
				null_checked g env ef (fun so ->
					let cache = req g RFieldCache in
					out g ("let jx_vf = R.field_cached " ^ cache ^ " " ^ so ^ " " ^ string_of_int name ^ " in ");
					set_leave g e.epos;
					bind_list g env el (fun sl ->
						out g ("P.call_value_on " ^ so ^ " jx_vf " ^ ocaml_list sl)
					)
				);
				out g ")"
		end
	| TConst TSuper ->
		begin match follow e1.etype with
		| TInst(c,_) ->
			let this = this_name g in
			let key = path_hash c.cl_path in
			if IntHashtbl.mem (get_ctx()).builtins.constructor_builtins key then begin
				(* emit_special_super_call *)
				let f = req g (RSpecialCtor key) in
				out g "(";
				check_stack_depth g;
				bind_list g env el (fun sl -> out g ("R.special_super_call " ^ f ^ " " ^ ocaml_list sl ^ " " ^ this));
				out g ")"
			end else begin
				(* emit_super_call *)
				let lz = req g (RCtorLazy(key,e1.epos,e.epos)) in
				out g "(";
				check_stack_depth g;
				out g ("let jx_f = Lazy.force " ^ lz ^ " in ");
				bind_list g env el (fun sl ->
					set_leave g e.epos;
					out g ("ignore (jx_f (" ^ this ^ " :: " ^ ocaml_list sl ^ ")); " ^ this)
				);
				out g ")"
			end
		| _ -> unsupported "super call"
		end
	| _ ->
		(* emit_call; $__mk_pos__ as the callee is an identifier like any other now *)
		out g "(";
		check_stack_depth g;
		bind g env e1 (fun sf ->
			set_leave g e.epos;
			bind_list g env el (fun sl ->
				out g ("M.call_value " ^ sf ^ " " ^ ocaml_list sl)
			)
		);
		out g ")"

(* A local function value: emit_closure. *)
and gen_closure g env e tf =
	let number = try List.assq e g.fn.fn_closures with Not_found -> unsupported "local function not numbered" in
	let eci = req g (REnvInfo(false,tf.tf_expr.epos.pfile,EKLocalFunction number)) in
	(* A local function sees the values its captured variables had when it was created. *)
	let free = free_variables tf in
	let snapshots = ref 0 in
	let inner_env = List.fold_left (fun acc v ->
		match IntMap.find_opt v.v_id env with
		| Some (Imm s) ->
			IntMap.add v.v_id (Imm s) acc
		| Some (Mut s) ->
			let name = fresh g "js" in
			out g ("(let " ^ name ^ " = !" ^ s ^ " in ");
			incr snapshots;
			IntMap.add v.v_id (Imm name) acc
		| None ->
			unsupported ("captured variable not in scope: " ^ v.v_name)
	) IntMap.empty free in
	out g "(VFunction ((fun jvl -> ";
	gen_function_body g inner_env None free eci tf;
	out g "), true))";
	for _ = 1 to !snapshots do out g ")" done

(* The body of a function value with argument list [jvl]: environment, arguments, default
   values, body, result. As EvalEmitter.create_function(_noret) and create_closure: the
   environment is pushed, then arguments and body run under Std.finally, which pops it whether
   they return or raise. [captured] are the variables of an enclosing function this one
   captures. *)
and gen_function_body g env this captured eci tf =
	let ctx = g.ctx in
	let outer = g.fn in
	(* Add conditionals for default values, as evalJit does. *)
	let e = List.fold_left (fun e (v,cto) -> match cto with
		| None -> e
		| Some ct -> concat (Texpr.set_default (ctx.curapi.MacroApi.get_com()).Common.basic v ct e.epos) e
	) tf.tf_expr tf.tf_args in
	let fn = {
		fn_written = collect_written e;
		fn_closures = number_closures e;
		fn_has_nonfinal_return = false;
		fn_this = this;
	} in
	g.fn <- fn;
	Std.finally (fun () -> g.fn <- outer) (fun () ->
		(* Captured variables this function writes start from the captured value on every call. *)
		let env = List.fold_left (fun env v ->
			if Hashtbl.mem fn.fn_written v.v_id then begin
				let name = fresh g "jw" in
				let cur = match IntMap.find v.v_id env with Imm s -> s | Mut s -> "!" ^ s in
				out g ("let " ^ name ^ " = ref " ^ cur ^ " in ");
				IntMap.add v.v_id (Mut name) env
			end else
				env
		) env captured in
		let ctxname = req g RCtx in
		out g ("let jenv = R.push_env " ^ ctxname ^ " " ^ eci ^ " in (match (");
		begin match this with
			| Some s -> out g ("let " ^ s ^ " = (match jvl with jx_v :: _ -> jx_v | [] -> VNull) in let jvl = (match jvl with _ :: jx_rest -> jx_rest | [] -> []) in ")
			| None -> ()
		end;
		let env = List.fold_left (fun env (v,_) ->
			let name = fresh g "jv" in
			let arg = "(match jvl with jx_v :: _ -> jx_v | [] -> VNull)" in
			let env = if Hashtbl.mem fn.fn_written v.v_id then begin
				out g ("let " ^ name ^ " = ref " ^ arg ^ " in ");
				IntMap.add v.v_id (Mut name) env
			end else begin
				out g ("let " ^ name ^ " = " ^ arg ^ " in ");
				IntMap.add v.v_id (Imm name) env
			end in
			out g "let jvl = (match jvl with _ :: jx_rest -> jx_rest | [] -> []) in ";
			env
		) env tf.tf_args in
		out g "(match jvl with [] -> () | _ -> R.too_many_arguments jvl); ";
		(* Whether the body needs a return handler is known only once it is generated. *)
		let saved = g.b in
		g.b <- Buffer.create 1024;
		let body = Std.finally (fun () -> g.b <- saved) (fun () -> gen g env MV true e; Buffer.contents g.b) () in
		if fn.fn_has_nonfinal_return then
			out g ("(try " ^ body ^ " with X.Return jx_v -> jx_v)")
		else
			out g body;
		out g (") with jx_r -> R.pop_env " ^ ctxname ^ " jenv; jx_r | exception jx_e -> R.pop_env " ^ ctxname ^ " jenv; raise jx_e)")
	) ()

(* A method: the text of its link function and its requirements. *)
let gen_method ctx index key_type key_field tf static =
	let g = {
		ctx = ctx;
		b = Buffer.create 4096;
		reqs = [];
		num_reqs = 0;
		shared = Hashtbl.create 0;
		tmp = 0;
		nodes = 0;
		fn = {
			fn_written = Hashtbl.create 0;
			fn_closures = [];
			fn_has_nonfinal_return = false;
			fn_this = None;
		};
	} in
	let eci = req g (REnvInfo(static,tf.tf_expr.epos.pfile,EKMethod(key_type,key_field))) in
	gen_function_body g IntMap.empty (if static then None else Some "jthis") [] eci tf;
	if getenv "HAXE_EVAL_JIT_SIZES" <> "" && g.nodes > 1000 then
		prerr_endline (Printf.sprintf "[eval-jit] size: %s.%s: %d expressions, %d bytes" (rev_hash key_type) (rev_hash key_field) g.nodes (Buffer.length g.b));
	if g.nodes > Lazy.force max_function_size then unsupported (Printf.sprintf "too large (%d expressions, %d bytes)" g.nodes (Buffer.length g.b));
	let body = Buffer.contents g.b in
	let reqs = Array.of_list (List.rev g.reqs) in
	let b = Buffer.create (String.length body + 64 * Array.length reqs + 128) in
	Buffer.add_string b (Printf.sprintf "let jfun%d (jl : Obj.t array) : vfunc =\n" index);
	Array.iteri (fun i r ->
		Buffer.add_string b (Printf.sprintf "\tlet jk%d : %s = Obj.obj (Array.unsafe_get jl %d) in\n" i (req_type r) i)
	) reqs;
	Buffer.add_string b "\t(fun jvl -> ";
	Buffer.add_string b body;
	Buffer.add_string b ")\n\n";
	Buffer.contents b,reqs

(* Units: one per class *)

type unit_state =
	| UReady (* compiled and loaded: its link functions are registered *)
	| UFailed

type class_unit = {
	u_class : tclass;
	u_key : string; (* digest of the source *)
	u_source : string;
	u_methods : (bool * int,int * req array) Hashtbl.t; (* (static, name) -> index, requirements *)
	mutable u_state : unit_state option;
}

let header = "[@@@ocaml.warning \"-a\"]\nopen Globals\nopen EvalValue\nopen EvalContext\nmodule E = EvalEmitter\nmodule M = EvalMisc\nmodule R = EvalJitRt\nmodule F = EvalField\nmodule P = EvalPrinting\nmodule X = EvalExceptions\nmodule A = EvalArray\nmodule N = EvalEncode\nmodule C = EvalContext\n\n"

(* The methods of a class, exactly as EvalPrototype turns them into functions. *)
let class_methods c =
	let l = ref [] in
	let is_removable_field cf = has_class_field_flag cf CfExtern || has_class_field_flag cf CfGeneric in
	if not (has_class_flag c CExtern) then begin
		begin match c.cl_constructor with
			| Some {cf_expr = Some {eexpr = TFunction tf}} -> l := (false,key_new,tf) :: !l
			| _ -> ()
		end;
		List.iter (fun cf -> match cf.cf_kind,cf.cf_expr with
			| Method _,Some {eexpr = TFunction tf} when not (is_removable_field cf) -> l := (false,hash cf.cf_name,tf) :: !l
			| _ -> ()
		) c.cl_ordered_fields;
		List.iter (fun cf -> match cf.cf_kind,cf.cf_expr with
			| Method _,Some {eexpr = TFunction tf} when not (is_removable_field cf) -> l := (true,hash cf.cf_name,tf) :: !l
			| _ -> ()
		) c.cl_ordered_statics
	end;
	List.rev !l

let generate_unit ctx c =
	let t0 = Unix.gettimeofday () in
	let key_type = path_hash c.cl_path in
	let b = Buffer.create 65536 in
	let methods = Hashtbl.create 0 in
	let index = ref 0 in
	List.iter (fun (static,name,tf) ->
		try
			let text,reqs = gen_method ctx !index key_type name tf static in
			Buffer.add_string b text;
			Hashtbl.replace methods (static,name) (!index,reqs);
			incr index
		with
		| Unsupported s ->
			incr stat_functions_unsupported;
			log "unsupported: %s.%s: %s" (s_type_path c.cl_path) (rev_hash name) s
		| exc ->
			incr stat_functions_unsupported;
			log "cannot generate %s.%s: %s" (s_type_path c.cl_path) (rev_hash name) (Printexc.to_string exc)
	) (class_methods c);
	stat_generate_time := !stat_generate_time +. (Unix.gettimeofday () -. t0);
	if !index = 0 then
		None
	else begin
		let body = Buffer.contents b in
		let key = Digest.to_hex (Digest.string (jit_version ^ "\n" ^ body)) in
		let fl = String.concat "; " (List.init !index (fun i -> "jfun" ^ string_of_int i)) in
		let source = header ^ body ^ Printf.sprintf "let () = R.register %S [| %s |]\n" key fl in
		Some {
			u_class = c;
			u_key = key;
			u_source = source;
			u_methods = methods;
			u_state = None;
		}
	end

(* Compilation and loading

   The first load of any new shared object costs macOS about 165ms, whatever its size, so units
   compiled together are linked into one bundle. An index file per unit names its bundle.
   Bundles are loaded privately: a unit compiled by two processes at once may end up in two
   bundles, and privately loaded modules may share a name. *)

let bundles_dir cfg = Filename.concat cfg.cache_dir "bundles"
let index_file cfg key = Filename.concat (Filename.concat cfg.cache_dir "units") key
let failed_file cfg key = Filename.concat (Filename.concat cfg.cache_dir "units") (key ^ ".failed")

let rec mkdir_p dir =
	if not (Sys.file_exists dir) then begin
		mkdir_p (Filename.dirname dir);
		try Unix.mkdir dir 0o755 with Unix.Unix_error(Unix.EEXIST,_,_) -> ()
	end

let temp_counter = ref 0

let remove_dir dir =
	(try Array.iter (fun f -> try Sys.remove (Filename.concat dir f) with _ -> ()) (Sys.readdir dir) with _ -> ());
	(try Unix.rmdir dir with _ -> ())

let write_file path s =
	let ch = open_out_bin path in
	output_string ch s;
	close_out ch

(* Written under a temporary name and renamed, so readers never see half a file. *)
let write_file_atomic path s =
	incr temp_counter;
	let tmp = Printf.sprintf "%s.%d.%d.tmp" path (Unix.getpid()) !temp_counter in
	write_file tmp s;
	Sys.rename tmp path

let read_file path =
	try
		let ch = open_in_bin path in
		let s = really_input_string ch (in_channel_length ch) in
		close_in ch;
		s
	with _ -> ""

(* Runs [jobs] processes at a time; [f] gets each exit status. Only our own children are waited
   for: eval code may have processes of its own. *)
let run_processes jobs (cmds : (string array * string * (Unix.process_status -> unit)) list) =
	let pending = Queue.create () in
	List.iter (fun c -> Queue.add c pending) cmds;
	let running = Hashtbl.create 0 in
	let devnull = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
	Std.finally (fun () -> Unix.close devnull) (fun () ->
		while not (Queue.is_empty pending) || Hashtbl.length running > 0 do
			while not (Queue.is_empty pending) && Hashtbl.length running < jobs do
				let (args,log_file,f) = Queue.pop pending in
				let fd = Unix.openfile log_file [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o644 in
				let pid = Std.finally (fun () -> Unix.close fd) (fun () -> Unix.create_process args.(0) args devnull fd fd) () in
				Hashtbl.replace running pid f
			done;
			let finished = Hashtbl.fold (fun pid f acc ->
				match Unix.waitpid [Unix.WNOHANG] pid with
				| 0,_ -> acc
				| _,status -> (pid,f,status) :: acc
			) running [] in
			match finished with
			| [] -> Unix.sleepf 0.002
			| l -> List.iter (fun (pid,f,status) -> Hashtbl.remove running pid; f status) l
		done
	) ()

(* Temporary directories of compilations that were interrupted. *)
let prune_temporaries = lazy (fun cfg ->
	try Array.iter (fun d ->
		let dir = Filename.concat cfg.cache_dir d in
		if String.length d > 4 && String.sub d 0 4 = "tmp-" && (Unix.stat dir).Unix.st_mtime < Unix.time() -. 3600. then
			ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)))
	) (Sys.readdir cfg.cache_dir) with _ -> ()
)

let mark_failed cfg key units msg =
	List.iter (fun u -> u.u_state <- Some UFailed) units;
	incr stat_units_failed;
	(try write_file_atomic (failed_file cfg key) msg with _ -> ());
	let u = List.hd units in
	log "compilation of %s (%s) failed:\n%s" (s_type_path u.u_class.cl_path) key msg;
	if Lazy.force strict then begin
		(try write_file (Filename.concat cfg.cache_dir ("jit_" ^ key ^ ".ml")) u.u_source with _ -> ());
		failwith (Printf.sprintf "eval-jit: compilation of %s failed, see %s" (s_type_path u.u_class.cl_path) (failed_file cfg key))
	end

(* Compiles units into one new bundle and indexes them. Units with the same source share it. *)
let compile_units cfg units =
	if units <> [] then begin
		let t0 = Unix.gettimeofday () in
		let by_key = Hashtbl.create 0 in
		let keys = ref [] in
		List.iter (fun u ->
			match Hashtbl.find_opt by_key u.u_key with
			| Some l -> Hashtbl.replace by_key u.u_key (u :: l)
			| None -> Hashtbl.replace by_key u.u_key [u]; keys := u.u_key :: !keys
		) units;
		let keys = List.rev !keys in
		mkdir_p (bundles_dir cfg);
		(Lazy.force prune_temporaries) cfg;
		mkdir_p (Filename.dirname (index_file cfg "x"));
		incr temp_counter;
		let tmp = Filename.concat cfg.cache_dir (Printf.sprintf "tmp-%d-%d" (Unix.getpid()) !temp_counter) in
		mkdir_p tmp;
		let base key = Filename.concat tmp ("jit_" ^ key) in
		let compiled = ref [] in
		Std.finally (fun () ->
			remove_dir tmp;
			stat_compile_time := !stat_compile_time +. (Unix.gettimeofday () -. t0)
		) (fun () ->
			let includes = List.concat (List.map (fun d -> ["-I"; d]) cfg.includes) in
			run_processes cfg.jobs (List.map (fun key ->
				let us = Hashtbl.find by_key key in
				write_file (base key ^ ".ml") (List.hd us).u_source;
				begin match getenv "HAXE_EVAL_JIT_DUMP" with
					| "" -> ()
					| dir -> (try mkdir_p dir; write_file (Filename.concat dir (Printf.sprintf "%s.%s.ml" (s_type_path (List.hd us).u_class.cl_path) key)) (List.hd us).u_source with _ -> ())
				end;
				let args = Array.of_list ([cfg.ocamlopt; "-c"; "-w"; "-a"] @ includes @ cfg.flags @ [base key ^ ".ml"]) in
				args,base key ^ ".log",(fun status ->
					match status with
					| Unix.WEXITED 0 when Sys.file_exists (base key ^ ".cmx") ->
						compiled := key :: !compiled
					| Unix.WEXITED _ ->
						mark_failed cfg key us (read_file (base key ^ ".log"))
					| Unix.WSIGNALED _ | Unix.WSTOPPED _ ->
						(* Not the source's fault: fall back now, try again next time. *)
						List.iter (fun u -> u.u_state <- Some UFailed) us
				)
			) keys);
			let compiled = List.filter (fun k -> List.mem k !compiled) keys in
			if compiled <> [] then begin
				let name = Printf.sprintf "b_%s.cmxs" (Digest.to_hex (Digest.string (Printf.sprintf "%s|%d|%f" (String.concat "," compiled) (Unix.getpid()) (Unix.gettimeofday())))) in
				let out = Filename.concat tmp name in
				let args = Array.of_list ([cfg.ocamlopt; "-shared"; "-o"; out] @ (List.map (fun k -> base k ^ ".cmx") compiled)) in
				run_processes 1 [args,Filename.concat tmp "link.log",(fun status ->
					match status with
					| Unix.WEXITED 0 when Sys.file_exists out ->
						Sys.rename out (Filename.concat (bundles_dir cfg) name);
						List.iter (fun key ->
							write_file_atomic (index_file cfg key) name;
							incr stat_units_compiled;
							log "compiled %s (%s)" (s_type_path (List.hd (Hashtbl.find by_key key)).u_class.cl_path) key
						) compiled
					| _ ->
						let msg = read_file (Filename.concat tmp "link.log") in
						List.iter (fun key -> mark_failed cfg key (Hashtbl.find by_key key) ("link: " ^ msg)) compiled
				)]
			end
		) ()
	end

let loaded_bundles : (string,bool) Hashtbl.t = Hashtbl.create 0

let load_unit cfg u =
	if Hashtbl.mem EvalJitRt.units u.u_key then
		u.u_state <- Some UReady
	else begin
		let name = String.trim (read_file (index_file cfg u.u_key)) in
		let file = Filename.concat (bundles_dir cfg) name in
		if name = "" then
			u.u_state <- Some UFailed
		else if Hashtbl.mem loaded_bundles name then
			u.u_state <- Some (if Hashtbl.mem EvalJitRt.units u.u_key then UReady else UFailed)
		else begin
			let t0 = Unix.gettimeofday () in
			try
				Hashtbl.replace loaded_bundles name true;
				Dynlink.loadfile_private file;
				stat_load_time := !stat_load_time +. (Unix.gettimeofday () -. t0);
				u.u_state <- Some (if Hashtbl.mem EvalJitRt.units u.u_key then UReady else UFailed)
			with exc ->
				stat_load_time := !stat_load_time +. (Unix.gettimeofday () -. t0);
				let msg = match exc with Dynlink.Error err -> Dynlink.error_message err | exc -> Printexc.to_string exc in
				log "cannot load %s: %s" file msg;
				u.u_state <- Some UFailed;
				(* Most likely compiled against another build of the compiler: rebuilt next time. *)
				(try Sys.remove (index_file cfg u.u_key) with _ -> ());
				if Lazy.force strict then failwith ("eval-jit: cannot load " ^ file ^ ": " ^ msg)
		end
	end

(* Units per context and class. The generated code depends on the context (macro or interp). *)
let units_by_class : (int * path,class_unit option) Hashtbl.t = Hashtbl.create 0

let enabled ctx = match Lazy.force config with
	| None -> None
	| Some cfg ->
		if ctx.debug.support_debugger || ctx.debug.debug_socket <> None then None
		else Some cfg

(* Generates, compiles as needed and loads the units of classes [cl]. *)
let prepare_classes ctx cfg cl =
	let fresh = ExtList.List.filter_map (fun c ->
		match Hashtbl.find_opt units_by_class (ctx.ctx_id,c.cl_path) with
		| Some (Some u) when u.u_class == c -> None
		| _ ->
			let u = generate_unit ctx c in
			Hashtbl.replace units_by_class (ctx.ctx_id,c.cl_path) u;
			u
	) cl in
	let missing = List.filter (fun u ->
		if Hashtbl.mem EvalJitRt.units u.u_key || Sys.file_exists (index_file cfg u.u_key) then begin
			if not (Hashtbl.mem EvalJitRt.units u.u_key) then incr stat_units_cached;
			false
		end else if Sys.file_exists (failed_file cfg u.u_key) then begin
			u.u_state <- Some UFailed;
			false
		end else
			true
	) fresh in
	compile_units cfg missing;
	List.iter (fun u -> if u.u_state = None then load_unit cfg u) fresh

(* Called by EvalPrototype.add_types once the prototypes of [types] exist and before their
   fields are initialized. *)
let prepare ctx types =
	match enabled ctx with
	| None -> ()
	| Some cfg ->
		let cl = ExtList.List.filter_map (fun mt -> match mt with
			| TClassDecl c when not (has_class_flag c CExtern) -> Some c
			| _ -> None
		) types in
		prepare_classes ctx cfg cl

(* Creates the function of a method: natively compiled if possible, by evalJit otherwise. *)
let jit_method ctx c key_type key_field tf static pos =
	let fallback () = EvalJit.jit_tfunction ctx key_type key_field tf static pos in
	match enabled ctx with
	| None ->
		fallback ()
	| Some cfg ->
		let u = match Hashtbl.find_opt units_by_class (ctx.ctx_id,c.cl_path) with
			| Some (Some u) when u.u_class == c -> Some u
			| Some None -> None
			| _ ->
				(try prepare_classes ctx cfg [c] with exc -> if Lazy.force strict then raise exc);
				(match Hashtbl.find_opt units_by_class (ctx.ctx_id,c.cl_path) with Some (Some u) when u.u_class == c -> Some u | _ -> None)
		in
		match u with
		| Some ({u_state = Some UReady} as u) ->
			begin match Hashtbl.find_opt u.u_methods (static,key_field) with
			| None ->
				fallback ()
			| Some (index,reqs) ->
				let linked = try
					let fl = Hashtbl.find EvalJitRt.units u.u_key in
					let resolved = Array.make (Array.length reqs) (Obj.repr 0) in
					Array.iteri (fun i r -> resolved.(i) <- resolve ctx resolved r) reqs;
					Some (fl.(index) resolved)
				with exc ->
					log "cannot link %s.%s: %s" (s_type_path c.cl_path) (rev_hash key_field) (Printexc.to_string exc);
					None
				in
				match linked with
				| Some f ->
					incr stat_functions_native;
					f
				| None ->
					incr stat_functions_fallback;
					fallback ()
			end
		| _ ->
			fallback ()
