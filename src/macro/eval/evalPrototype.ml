(*
	The Haxe Compiler
	Copyright (C) 2005-2019  Haxe Foundation

	This program is free software; you can redistribute it and/or
	modify it under the terms of the GNU General Public License
	as published by the Free Software Foundation; either version 2
	of the License, or (at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program; if not, write to the Free Software
	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *)

open Globals
open Type
open EvalValue
open EvalContext
open EvalEncode
open EvalHash
open EvalJit
open EvalJitContext
open EvalExceptions
open EvalMisc

(* JITs expression [e] and executes the result immediately. *)
let eval_expr ctx kind e =
	catch_exceptions ctx (fun () ->
		let jit,f = jit_expr ctx e in
		let num_captures = Hashtbl.length jit.captures in
		let info = create_env_info true e.epos.pfile (ctx.file_keys#get e.epos.pfile) kind jit.capture_infos jit.max_num_locals num_captures in
		let env = push_environment ctx info in
		Std.finally (fun _ -> pop_environment ctx env) f env
	) e.Type.epos

(* Creates constructor function for class [c], if it has a constructor. *)
let create_constructor ctx c =
	match c.cl_constructor with
	| Some {cf_expr = Some {eexpr = TFunction tf; epos = pos}} when not (has_class_flag c CExtern) ->
		let key = path_hash c.cl_path in
		let v = lazy (vfunction (EvalJitNative.jit_method ctx c key key_new tf false pos)) in
		ctx.constructors <- IntMap.add key v ctx.constructors;
	| _ ->
		()

(*
	PrototypeBuilder manages the intermediate state of prototypes. Due to mutual dependencies,
	prototypes have to be created in multiple steps similar to how types have to be loaded.

	The procedure is as follows:

	1. Create an instance of [prototype_context] using [create].
	2. Add fields to it and call [finalize].
	3. Invoke the function returned by [finalize] to initialize fields.
*)
module PrototypeBuilder = struct
	type prototype_context = {
		ctx : context;
		(* The hashed path of the prototype. *)
		key : int;
		(* The parent prototype, if exists. *)
		parent : vprototype option;
		(* The kind of the prototype. *)
		kind : vprototype_kind;
		(* The fields of the prototype. A field here is a pair of its hashed name and its (lazyfied) value. *)
		fields : (int * value Lazy.t) DynArray.t;
		(* The instance fields of the prototype. See above. *)
		instance_fields : (int * value Lazy.t) DynArray.t;
		(* The metadata expression, if exists. *)
		meta : texpr option;
		(* Whether or not the prototype is static. *)
		is_static : bool;
	}

	(* Creates a new prototype context using the provided information. *)
	let create ctx key parent kind meta =
		let is_static = match kind with PClass _ | PEnum _ -> true | PInstance | PObject -> false in
		{
			ctx = ctx;
			key = key;
			parent = parent;
			kind = kind;
			fields = DynArray.create ();
			instance_fields = DynArray.create ();
			meta = meta;
			is_static = is_static;
		}

	(* Adds a prototype (static) field. *)
	let add_proto_field pctx name v =
		DynArray.add pctx.fields (name,v)

	(* Adds an instance (non-static) field. *)
	let add_instance_field pctx name v =
		DynArray.add pctx.instance_fields (name,v)

	(* Forces the lazy field values and assigns them to the prototype. *)
	let initialize_fields pctx proto =
		DynArray.iteri (fun i (_,v) -> proto.pfields.(i) <- Lazy.force v) pctx.fields

	(* Processes the field information and returns an initialization function. *)
	let finalize pctx =
		let ctx = pctx.ctx in
		(* Add builtins (from EvalStdLib). *)
		let builtins = try IntMap.find pctx.key (if pctx.is_static then ctx.builtins.static_builtins else ctx.builtins.instance_builtins) with Not_found -> [] in
		List.iter (fun (s,v) ->
			try
				let i = DynArray.index_of (fun (name',_) -> name' = s) pctx.fields in
				DynArray.set pctx.fields i (s,(lazy v))
			with Not_found ->
				add_proto_field pctx s (lazy v)
		) builtins;
		(* Add metadata field *)
		begin match pctx.meta with
			| None -> ()
			| Some e -> DynArray.add pctx.fields (key___meta__,lazy (match eval_expr ctx (EKMethod(pctx.key,key___meta__)) e with Some e -> e | None -> vnull))
		end;
		(* Create the mapping from hashed name to field offset for prototype fields. *)
		let _,pnames = DynArray.fold_left (fun (i,acc) (name,_) -> i + 1,IntMap.add name i acc) (0,IntMap.empty) pctx.fields in
		let pinstance_names,pinstance_fields,f = if not pctx.is_static then begin
			(* Combines parent instance fields with current instance fields. *)
			let names,fields = match pctx.parent with
				| Some proto -> proto.pinstance_names,proto.pinstance_fields
				| None -> IntMap.empty,[||]
			in
			let offset = Array.length fields in
			let a = Array.make (offset + DynArray.length pctx.instance_fields) vnull in
			Array.blit fields 0 a 0 (offset);
			(* Create the mapping from hashed name to field offset for instance fields. *)
			let names,_ = DynArray.fold_left (fun (fields,count) (name,v) ->
				IntMap.add name count fields,count + 1
			) (names,offset) pctx.instance_fields in
			names,a,(fun proto ->
				Array.iteri (fun i v -> a.(i) <- v) fields;
				DynArray.iteri (fun i (_,v) -> a.(i + offset) <- Lazy.force v) pctx.instance_fields;
				initialize_fields pctx proto;
			)
		end else
			IntMap.empty,[||],(fun proto ->
				initialize_fields pctx proto;
			)
		in
		(* Create the prototype. *)
		let proto = {
			ppath = pctx.key;
			pfields = Array.make (DynArray.length pctx.fields) vnull;
			pnames = pnames;
			pinstance_fields = pinstance_fields;
			pinstance_names = pinstance_names;
			pparent = pctx.parent;
			pkind = pctx.kind;
			pvalue = vnull;
		} in
		proto.pvalue <- vprototype proto;
		(* Register the prototype. *)
		if pctx.is_static then
			ctx.static_prototypes#add proto
		else begin
			ctx.instance_prototypes <- IntMap.add pctx.key proto ctx.instance_prototypes;
			if pctx.key = key_String then ctx.string_prototype <- proto
			else if pctx.key = key_Array then ctx.array_prototype <- proto
			else if pctx.key = key_eval_Vector then ctx.vector_prototype <- proto
		end;
		proto,f
end

let is_removable_field cf =
	has_class_field_flag cf CfExtern || has_class_field_flag cf CfGeneric

let is_persistent cf =
	Meta.has Meta.Persistent cf.cf_meta

let create_static_prototype ctx mt =
	let path = (t_infos mt).mt_path in
	let key = path_hash path in
	let com = ctx.curapi.MacroApi.get_com() in
	let meta = Texpr.build_metadata com.Common.basic mt in
	let o = match mt with
	| TClassDecl c ->
		let pparent = match c.cl_super with
			| None -> None
			| Some(csup,_) -> Some (get_static_prototype ctx (path_hash csup.cl_path) c.cl_pos)
		in
		let rec collect_interfaces acc (c,_) =
			let acc = List.fold_left (fun acc c -> collect_interfaces acc c) acc c.cl_implements in
			path_hash c.cl_path :: acc
		in
		let interfaces = collect_interfaces [] (c,[]) in
		let pctx = PrototypeBuilder.create ctx key pparent (PClass interfaces) meta in
		let fields = List.filter (fun cf -> not (is_removable_field cf)) c.cl_ordered_statics in
		let delays = DynArray.create() in
		if not (has_class_flag c CExtern) then List.iter (fun cf -> match cf.cf_kind,cf.cf_expr with
			| Method _,Some {eexpr = TFunction tf; epos = pos} ->
				let name = hash cf.cf_name in
				PrototypeBuilder.add_proto_field pctx name (lazy (vstatic_function (EvalJitNative.jit_method ctx c key name tf true pos)));
			| Var _,Some e ->
				let name = hash cf.cf_name in
				PrototypeBuilder.add_proto_field pctx name (lazy vnull);
				let i = DynArray.length pctx.PrototypeBuilder.fields - 1 in
				let persistent = is_persistent cf in
				DynArray.add delays (persistent,(fun proto ->
					proto.pfields.(i) <- (match eval_expr ctx (EKMethod(key,name)) e with Some e -> e | None -> vnull)
				))
			| _,None when is_physical_field cf ->
				PrototypeBuilder.add_proto_field pctx (hash cf.cf_name) (lazy vnull);
			|  _ ->
				()
		) fields;
		begin match c.cl_init with
			| None -> ()
			| Some e -> DynArray.add delays (false,(fun _ -> ignore(eval_expr ctx (EKMethod(key,key___init__)) e)))
		end;
		PrototypeBuilder.finalize pctx,(DynArray.to_list delays)
	| TEnumDecl en ->
		let names = List.map (fun name ->
			let ef = PMap.find name en.e_constrs in
			let args = match follow ef.ef_type with
				| TFun(args,_) ->
					List.map (fun (n,_,_) -> hash n) args
				| _ ->
					[]
			in
			name,args
		) en.e_names in
		let pctx = PrototypeBuilder.create ctx key None (PEnum names) meta in
		let enum_field_value ef = match follow ef.ef_type with
			| TFun(args,_) ->
				let f = (fun vl -> encode_enum_value key ef.ef_index (Array.of_list vl) (Some ef.ef_pos)) in
				vstatic_function f
			| _ -> encode_enum_value key ef.ef_index [||] (Some ef.ef_pos)
		in
		PMap.iter (fun name ef -> PrototypeBuilder.add_proto_field pctx (hash name ) (lazy (enum_field_value ef))) en.e_constrs;
		PrototypeBuilder.finalize pctx,[];
	| TAbstractDecl a ->
		let pctx = PrototypeBuilder.create ctx key None (PClass []) meta in
		PrototypeBuilder.finalize pctx,[];
	| _ ->
		die "" __LOC__
	in
	let rec loop v name path = match path with
		| [] ->
			set_field v (hash name) (vprototype (fst (fst o)))
		| s :: sl ->
			let key = hash s in
			let v2 = EvalField.field v key in
			let v2 = match v2 with
				| VNull -> encode_obj []
				| _ -> v2
			in
			set_field v key v2;
			loop v2 name sl;
	in
	if ctx.debug.support_debugger then
		loop ctx.toplevel (snd path) (fst path);
	o

let create_instance_prototype ctx c =
	let pparent = match c.cl_super with
		| None -> None
		| Some(c,_) -> Some (get_instance_prototype ctx (path_hash c.cl_path) c.cl_pos)
	in
	let key = path_hash c.cl_path in
	let pctx = PrototypeBuilder.create ctx key pparent PInstance None in
	let fields = List.filter (fun cf -> not (is_removable_field cf)) c.cl_ordered_fields in
	if (has_class_flag c CExtern) && c.cl_path <> ([],"String") then
		()
	else List.iter (fun cf -> match cf.cf_kind,cf.cf_expr with
		| Method meth,Some {eexpr = TFunction tf; epos = pos} ->
			let name = hash cf.cf_name in
			let v = lazy (vfunction (EvalJitNative.jit_method ctx c key name tf false pos)) in
			if meth = MethDynamic then PrototypeBuilder.add_instance_field pctx name v;
			PrototypeBuilder.add_proto_field pctx name v
		| Var _,_ when is_physical_field cf ->
			let name = hash cf.cf_name in
			PrototypeBuilder.add_instance_field pctx name (lazy vnull);
		| Method meth,None when has_class_field_flag cf CfAbstract ->
			let name = hash cf.cf_name in
			let v = lazy vnull in
			PrototypeBuilder.add_proto_field pctx name v
		| _ ->
			()
	) fields;
	PrototypeBuilder.finalize pctx

(* get_object_prototype runs for every object the macro API encodes, and sorting the fields,
   formatting the prototype's name, hashing it and finding the prototype was a large part of
   macro-heavy compilations. Objects are built from few shapes (the field hashes in the order they
   come in), so each shape remembers what does not change:
   - the order that sorts its fields, found by sorting (hash, position) pairs the way the fields
     are sorted, so it is List.sort's order even for equal hashes;
   - the prototype's name, with the field names as rev_hash returned them: used only while
     rev_hash still returns those very strings, so the name is the one that would be built, and
     registered again as hashing it would;
   - the prototype, for one context, one name and the very map of prototypes it was found in: any
     change to them means looking again.
   Cached parts are immutable values replaced in one write, so eval threads cannot see half an
   update. *)
type object_shape = {
	os_keys : int array;
	os_order : int array;
	mutable os_name : (string list * string * int * int) option; (* names, name, hash, EvalHash.collisions *)
	mutable os_proto : (int * vprototype IntMap.t * int * vprototype) option;
}

let object_shapes : object_shape list array = Array.make 4096 []

let rec shape_hash h l = match l with
	| [] -> h land 4095
	| (k,_) :: l -> shape_hash (h * 31 + k) l

let shape_matches keys l =
	let n = Array.length keys in
	let rec loop i l = match l with
		| [] -> i = n
		| (k,_) :: l -> i < n && Array.unsafe_get keys i = k && loop (i + 1) l
	in
	loop 0 l

let rec find_shape shapes l = match shapes with
	| [] -> None
	| sh :: shapes -> if shape_matches sh.os_keys l then Some sh else find_shape shapes l

let object_shape l =
	let h = shape_hash 7 l in
	let bucket = Array.unsafe_get object_shapes h in
	match find_shape bucket l with
	| Some sh ->
		sh
	| None ->
		let keys = Array.of_list (List.map fst l) in
		let indexed = List.mapi (fun i (k,_) -> (k,i)) l in
		let sorted = List.sort (fun (i1,_) (i2,_) -> if i1 = i2 then 0 else if i1 < i2 then -1 else 1) indexed in
		let sh = {
			os_keys = keys;
			os_order = Array.of_list (List.map snd sorted);
			os_name = None;
			os_proto = None;
		} in
		Array.unsafe_set object_shapes h (sh :: (match bucket with a :: b :: c :: d :: e :: f :: g :: _ -> [a;b;c;d;e;f;g] | _ -> bucket));
		sh

let object_prototype_name sh l =
	let build () =
		let names = List.map (fun (i,_) -> rev_hash i) l in
		let sfields = String.concat "," (List.map (fun s -> Printf.sprintf ":%s" s) names) in
		let sname = Printf.sprintf "eval.object.Object[%s]" sfields in
		let name = hash sname in
		sh.os_name <- Some (names,sname,name,!EvalHash.collisions);
		name
	in
	match sh.os_name with
	| Some (_,_,name,stamp) when stamp = !EvalHash.collisions ->
		(* No name displaced another since: rev_hash returns the same strings and the prototype's
		   name is still registered. *)
		name
	| Some (names,sname,name,_) when List.for_all2 (fun (i,_) s -> rev_hash i == s) l names ->
		EvalHash.register name sname;
		sh.os_name <- Some (names,sname,name,!EvalHash.collisions);
		name
	| _ ->
		build ()

let get_object_prototype ctx l =
	let sh = object_shape l in
	let l =
		let a = Array.of_list l in
		let order = sh.os_order in
		let rec build j acc = if j < 0 then acc else build (j - 1) (Array.unsafe_get a (Array.unsafe_get order j) :: acc) in
		build (Array.length order - 1) []
	in
	let name = object_prototype_name sh l in
	let proto = match sh.os_proto with
		| Some (id,map,name',proto) when id = ctx.ctx_id && name' = name && map == ctx.instance_prototypes ->
			proto
		| _ ->
			let proto = try
				IntMap.find name ctx.instance_prototypes
			with Not_found ->
				let pctx = PrototypeBuilder.create ctx name None PObject None in
				List.iter (fun (name,_) -> PrototypeBuilder.add_instance_field pctx name (lazy vnull)) l;
				let proto = fst (PrototypeBuilder.finalize pctx) in
				ctx.instance_prototypes <- IntMap.add name proto ctx.instance_prototypes;
				proto
			in
			sh.os_proto <- Some (ctx.ctx_id,ctx.instance_prototypes,name,proto);
			proto
	in
	proto,l

let add_types ctx types ready =
	let t = Timer.timer [(if ctx.is_macro then "macro" else "interp");"add_types"] in
	let new_types = List.filter (fun mt ->
		let inf = Type.t_infos mt in
		let key = path_hash inf.mt_path in
		try
			let inf' = t_infos (IntMap.find key ctx.type_cache) in
			if inf'.mt_module.m_id <> inf.mt_module.m_id then raise Not_found;
			false
		with Not_found ->
			ctx.instance_prototypes <- IntMap.remove key ctx.instance_prototypes;
			ctx.static_prototypes#remove key;
			ctx.constructors <- IntMap.remove key ctx.constructors;
			ready mt;
			ctx.type_cache <- IntMap.add key mt ctx.type_cache;
			if ctx.debug.support_debugger then begin
				let file_key = hash (Path.UniqueKey.lazy_path inf.mt_module.m_extra.m_file) in
				if not (Hashtbl.mem ctx.debug.breakpoints file_key) then begin
					Hashtbl.add ctx.debug.breakpoints file_key (Hashtbl.create 0)
				end
			end;
			true
	) types in
	(* 1. Create prototypes and register them. *)
	let fl_instance = DynArray.create () in
	let fl_static = DynArray.create () in
	List.iter (fun mt ->
		match mt with
		| TClassDecl c ->
			let rec loop p f =
				match p with
				| Some (p,_) when PMap.mem f.cf_name p.cl_fields || loop p.cl_super f ->
					Hashtbl.add ctx.overrides (p.cl_path,f.cf_name) true;
					true
				| _ ->
					false
			in
			List.iter (fun f -> if has_class_field_flag f CfOverride then ignore(loop c.cl_super f)) c.cl_ordered_fields;
			create_constructor ctx c;
			DynArray.add fl_instance (create_instance_prototype ctx c);
			DynArray.add fl_static (create_static_prototype ctx mt);
		| TEnumDecl en ->
			DynArray.add fl_static (create_static_prototype ctx mt);
		| TAbstractDecl a ->
			DynArray.add fl_static (create_static_prototype ctx mt);
			(* Create a fake instance prototype for coreType abstracts in case something inspects them (#8778). *)
			if Meta.has Meta.CoreType a.a_meta then
				DynArray.add fl_instance (create_instance_prototype ctx {null_class with cl_path = a.a_path})
		| _ ->
			()
	) new_types;
	(* Natively compile what can be, now that the prototypes exist and before any function is. *)
	EvalJitNative.prepare ctx new_types;
	(* 2. Create instance fields. *)
	DynArray.iter (fun (proto,f) -> ignore(f proto)) fl_instance;
	(* 3. Create static fields. *)
	let fl_static_init = DynArray.create () in
	DynArray.iter (fun ((proto,f),delays) ->
		f proto;
		match delays with
		| [] -> ()
		| _ ->
			DynArray.add fl_static_init (proto,delays);
			let non_persistent_delays = ExtList.List.filter_map (fun (persistent,f) -> if not persistent then Some f else None) delays in
			ctx.static_prototypes#add_init proto non_persistent_delays;
	) fl_static;
	(* 4. Initialize static fields. *)
	DynArray.iter (fun (proto,delays) -> List.iter (fun (_,f) -> f proto) delays) fl_static_init;
	t()