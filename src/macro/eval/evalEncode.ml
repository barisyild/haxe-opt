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
open EvalValue
open EvalExceptions
open EvalContext
open EvalHash
open EvalString

(* Functions *)

let vifun0 f = vfunction (fun vl -> match vl with
	| [] -> f vnull
	| [v0] -> f v0
	| _ -> invalid_call_arg_number 1 (List.length  vl
))

let vifun1 f = vfunction (fun vl -> match vl with
	| [] -> f vnull vnull
	| [v0] -> f v0 vnull
	| [v0;v1] -> f v0 v1
	| _ -> invalid_call_arg_number 2 (List.length  vl
))

let vifun2 f = vfunction (fun vl -> match vl with
	| [] -> f vnull vnull vnull
	| [v0] -> f v0 vnull vnull
	| [v0;v1] -> f v0 v1 vnull
	| [v0;v1;v2] -> f v0 v1 v2
	| _ -> invalid_call_arg_number 3 (List.length  vl
))

let vifun3 f = vfunction (fun vl -> match vl with
	| [] -> f vnull vnull vnull vnull
	| [v0] -> f v0 vnull vnull vnull
	| [v0;v1] -> f v0 v1 vnull vnull
	| [v0;v1;v2] -> f v0 v1 v2 vnull
	| [v0;v1;v2;v3] -> f v0 v1 v2 v3
	| _ -> invalid_call_arg_number 4 (List.length  vl
))

let vifun4 f = vfunction (fun vl -> match vl with
	| [] -> f vnull vnull vnull vnull vnull
	| [v0] -> f v0 vnull vnull vnull vnull
	| [v0;v1] -> f v0 v1 vnull vnull vnull
	| [v0;v1;v2] -> f v0 v1 v2 vnull vnull
	| [v0;v1;v2;v3] -> f v0 v1 v2 v3 vnull
	| [v0;v1;v2;v3;v4] -> f v0 v1 v2 v3 v4
	| _ -> invalid_call_arg_number 4 (List.length  vl
))

let vfun0 f = vstatic_function (fun vl -> match vl with
	| [] -> f ()
	| _ -> invalid_call_arg_number 1 (List.length  vl
))

let vfun1 f = vstatic_function (fun vl -> match vl with
	| [] -> f vnull
	| [v0] -> f v0
	| _ -> invalid_call_arg_number 1 (List.length  vl
))

let vfun2 f = vstatic_function (fun vl -> match vl with
	| [] -> f vnull vnull
	| [v0] -> f v0 vnull
	| [v0;v1] -> f v0 v1
	| _ -> invalid_call_arg_number 2 (List.length  vl
))

let vfun3 f = vstatic_function (fun vl -> match vl with
	| [] -> f vnull vnull vnull
	| [v0] -> f v0 vnull vnull
	| [v0;v1] -> f v0 v1 vnull
	| [v0;v1;v2] -> f v0 v1 v2
	| _ -> invalid_call_arg_number 3 (List.length  vl
))

let vfun4 f = vstatic_function (fun vl -> match vl with
	| [] -> f vnull vnull vnull vnull
	| [v0] -> f v0 vnull vnull vnull
	| [v0;v1] -> f v0 v1 vnull vnull
	| [v0;v1;v2] -> f v0 v1 v2 vnull
	| [v0;v1;v2;v3] -> f v0 v1 v2 v3
	| _ -> invalid_call_arg_number 4 (List.length  vl
))

let vfun5 f = vstatic_function (fun vl -> match vl with
	| [] -> f vnull vnull vnull vnull vnull
	| [v0] -> f v0 vnull vnull vnull vnull
	| [v0;v1] -> f v0 v1 vnull vnull vnull
	| [v0;v1;v2] -> f v0 v1 v2 vnull vnull
	| [v0;v1;v2;v3] -> f v0 v1 v2 v3 vnull
	| [v0;v1;v2;v3;v4] -> f v0 v1 v2 v3 v4
	| _ -> invalid_call_arg_number 5 (List.length  vl
))

let vfun6 f = vstatic_function (fun vl -> match vl with
	| [] -> f vnull vnull vnull vnull vnull vnull
	| [v0] -> f v0 vnull vnull vnull vnull vnull
	| [v0;v1] -> f v0 v1 vnull vnull vnull vnull
	| [v0;v1;v2] -> f v0 v1 v2 vnull vnull vnull
	| [v0;v1;v2;v3] -> f v0 v1 v2 v3 vnull vnull
	| [v0;v1;v2;v3;v4] -> f v0 v1 v2 v3 v4 vnull
	| [v0;v1;v2;v3;v4;v5] -> f v0 v1 v2 v3 v4 v5
	| _ -> invalid_call_arg_number 6 (List.length  vl
))

let vfun7 f = vstatic_function (fun vl -> match vl with
	| [] -> f vnull vnull vnull vnull vnull vnull vnull
	| [v0] -> f v0 vnull vnull vnull vnull vnull vnull
	| [v0;v1] -> f v0 v1 vnull vnull vnull vnull vnull
	| [v0;v1;v2] -> f v0 v1 v2 vnull vnull vnull vnull
	| [v0;v1;v2;v3] -> f v0 v1 v2 v3 vnull vnull vnull
	| [v0;v1;v2;v3;v4] -> f v0 v1 v2 v3 v4 vnull vnull
	| [v0;v1;v2;v3;v4;v5] -> f v0 v1 v2 v3 v4 v5 vnull
	| [v0;v1;v2;v3;v4;v5;v6] -> f v0 v1 v2 v3 v4 v5 v6
	| _ -> invalid_call_arg_number 7 (List.length  vl
))

(* Objects *)

let encode_obj l =
	let ctx = get_ctx() in
	let proto,sorted = ctx.get_object_prototype ctx l in
	vobject {
		ofields = Array.of_list (List.map snd sorted);
		oproto = OProto proto;
	}

(* The macro API encodes objects with fields named by constant strings, from few shapes, and
   hashing the names, sorting the fields and finding the prototype for each object was a large part
   of macro-heavy compilations. A shape, keyed by the name strings themselves (compared physically),
   remembers where each field goes and the prototype; it is used only in the context and for the
   very map of prototypes it was found in, and only while EvalHash.collisions says that no name has
   displaced another since: then hashing the names would change nothing, their hashes and the
   prototype's name are the same, and so is the prototype. The field order is found by sorting
   exactly as get_object_prototype sorts. Cached parts are immutable values replaced in one write. *)
type named_shape = {
	ns_names : string array;
	ns_slot : int array; (* position given -> index in ofields *)
	ns_order : int array; (* index in ofields -> position given *)
	mutable ns_proto : (int * vprototype IntMap.t * int * vobject_proto) option;
}

let named_shapes : named_shape list array = Array.make 4096 []

(* Hashes the first two names and the number of fields: reading every name's bytes cost more than
   it saved, a match compares all of them anyway, and the count separates shapes that share their
   first fields (the macro API's module types share nine). *)
let named_shape_hash l =
	let name h s =
		let n = String.length s in
		h * 31 + n * 7 + (if n > 0 then Char.code (String.unsafe_get s (n - 1)) else 0)
	in
	let rec count n l = match l with
		| [] -> n
		| _ :: l -> count (n + 1) l
	in
	let h = match l with
		| [] -> 0
		| [(s,_)] -> name 7 s
		| (s1,_) :: (s2,_) :: _ -> name (name 7 s1) s2
	in
	(h * 31 + count 0 l) land 4095

let named_shape_matches names l =
	let n = Array.length names in
	let rec loop i l = match l with
		| [] -> i = n
		| (s,_) :: l -> i < n && Array.unsafe_get names i == s && loop (i + 1) l
	in
	loop 0 l

let rec find_named_shape shapes l = match shapes with
	| [] -> None
	| sh :: shapes -> if named_shape_matches sh.ns_names l then Some sh else find_named_shape shapes l

(* A fresh array of [n] nulls. Array literals are allocated inline, without the C call Array.make
   is; they are never shared, arrays being mutable. *)
let make_fields n = match n with
	| 0 -> [||]
	| 1 -> [|vnull|]
	| 2 -> [|vnull;vnull|]
	| 3 -> [|vnull;vnull;vnull|]
	| 4 -> [|vnull;vnull;vnull;vnull|]
	| 5 -> [|vnull;vnull;vnull;vnull;vnull|]
	| 6 -> [|vnull;vnull;vnull;vnull;vnull;vnull|]
	| 7 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 8 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 9 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 10 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 11 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 12 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 13 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 14 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 15 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 16 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 17 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 18 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 19 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 20 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 21 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 22 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 23 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 24 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 25 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 26 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 27 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 28 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 29 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 30 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 31 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| 32 -> [|vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull;vnull|]
	| n -> Array.make n vnull

(* Loops are top-level functions taking all they use, so that calling them allocates no closure. *)
let rec list_length n l = match l with
	| [] -> n
	| _ :: l -> list_length (n + 1) l

let rec fill_values a i l = match l with
	| [] -> ()
	| v :: l -> Array.unsafe_set a i v; fill_values a (i + 1) l

(* Array.of_list. A small array is written as a literal of its values: allocated inline and
   initialized directly, where filling an array calls the write barrier (a C call) for every
   element. *)
let values_of_list l = match l with
	| [] -> [||]
	| [v0] -> [|v0|]
	| [v0;v1] -> [|v0;v1|]
	| [v0;v1;v2] -> [|v0;v1;v2|]
	| [v0;v1;v2;v3] -> [|v0;v1;v2;v3|]
	| [v0;v1;v2;v3;v4] -> [|v0;v1;v2;v3;v4|]
	| [v0;v1;v2;v3;v4;v5] -> [|v0;v1;v2;v3;v4;v5|]
	| [v0;v1;v2;v3;v4;v5;v6] -> [|v0;v1;v2;v3;v4;v5;v6|]
	| [v0;v1;v2;v3;v4;v5;v6;v7] -> [|v0;v1;v2;v3;v4;v5;v6;v7|]
	| [v0;v1;v2;v3;v4;v5;v6;v7;v8] -> [|v0;v1;v2;v3;v4;v5;v6;v7;v8|]
	| [v0;v1;v2;v3;v4;v5;v6;v7;v8;v9] -> [|v0;v1;v2;v3;v4;v5;v6;v7;v8;v9|]
	| [v0;v1;v2;v3;v4;v5;v6;v7;v8;v9;v10] -> [|v0;v1;v2;v3;v4;v5;v6;v7;v8;v9;v10|]
	| [v0;v1;v2;v3;v4;v5;v6;v7;v8;v9;v10;v11] -> [|v0;v1;v2;v3;v4;v5;v6;v7;v8;v9;v10;v11|]
	| [v0;v1;v2;v3;v4;v5;v6;v7;v8;v9;v10;v11;v12] -> [|v0;v1;v2;v3;v4;v5;v6;v7;v8;v9;v10;v11;v12|]
	| [v0;v1;v2;v3;v4;v5;v6;v7;v8;v9;v10;v11;v12;v13] -> [|v0;v1;v2;v3;v4;v5;v6;v7;v8;v9;v10;v11;v12;v13|]
	| [v0;v1;v2;v3;v4;v5;v6;v7;v8;v9;v10;v11;v12;v13;v14] -> [|v0;v1;v2;v3;v4;v5;v6;v7;v8;v9;v10;v11;v12;v13;v14|]
	| [v0;v1;v2;v3;v4;v5;v6;v7;v8;v9;v10;v11;v12;v13;v14;v15] -> [|v0;v1;v2;v3;v4;v5;v6;v7;v8;v9;v10;v11;v12;v13;v14;v15|]
	| _ ->
		let n = list_length 0 l in
		(* Past 256 values Array.of_list would force a minor collection: see EvalArray.map_values *)
		if n > 32 && n <= EvalArray.max_young_wosize then
			Array.of_list l
		else begin
			let a = make_fields n in
			fill_values a 0 l;
			a
		end

let rec fill_named_fields names slot n a i l = match l with
	| [] -> i = n
	| (s,v) :: l ->
		i < n && Array.unsafe_get names i == s && begin
			Array.unsafe_set a (Array.unsafe_get slot i) v;
			fill_named_fields names slot n a (i + 1) l
		end

(* Fills a fresh ofields for shape [sh] from [l], checking the names on the way; false if they do
   not match. *)
let fill_named_shape sh a l =
	fill_named_fields sh.ns_names sh.ns_slot (Array.length sh.ns_names) a 0 l

let sel2 i v0 v1 = match i with 0 -> v0 | _ -> v1
let sel3 i v0 v1 v2 = match i with 0 -> v0 | 1 -> v1 | _ -> v2
let sel4 i v0 v1 v2 v3 = match i with 0 -> v0 | 1 -> v1 | 2 -> v2 | _ -> v3
let sel5 i v0 v1 v2 v3 v4 = match i with 0 -> v0 | 1 -> v1 | 2 -> v2 | 3 -> v3 | _ -> v4
let sel6 i v0 v1 v2 v3 v4 v5 = match i with 0 -> v0 | 1 -> v1 | 2 -> v2 | 3 -> v3 | 4 -> v4 | _ -> v5
let sel7 i v0 v1 v2 v3 v4 v5 v6 = match i with 0 -> v0 | 1 -> v1 | 2 -> v2 | 3 -> v3 | 4 -> v4 | 5 -> v5 | _ -> v6
let sel8 i v0 v1 v2 v3 v4 v5 v6 v7 = match i with 0 -> v0 | 1 -> v1 | 2 -> v2 | 3 -> v3 | 4 -> v4 | 5 -> v5 | 6 -> v6 | _ -> v7
let sel9 i v0 v1 v2 v3 v4 v5 v6 v7 v8 = match i with 0 -> v0 | 1 -> v1 | 2 -> v2 | 3 -> v3 | 4 -> v4 | 5 -> v5 | 6 -> v6 | 7 -> v7 | _ -> v8
let sel10 i v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 = match i with 0 -> v0 | 1 -> v1 | 2 -> v2 | 3 -> v3 | 4 -> v4 | 5 -> v5 | 6 -> v6 | 7 -> v7 | 8 -> v8 | _ -> v9
let sel11 i v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 = match i with 0 -> v0 | 1 -> v1 | 2 -> v2 | 3 -> v3 | 4 -> v4 | 5 -> v5 | 6 -> v6 | 7 -> v7 | 8 -> v8 | 9 -> v9 | _ -> v10
let sel12 i v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 = match i with 0 -> v0 | 1 -> v1 | 2 -> v2 | 3 -> v3 | 4 -> v4 | 5 -> v5 | 6 -> v6 | 7 -> v7 | 8 -> v8 | 9 -> v9 | 10 -> v10 | _ -> v11

(* The ofields of shape [sh] for [l], or [||] if [l]'s names are not the shape's: a small shape's
   fields come from a literal (see values_of_list), in sorted order by selecting through
   ns_order; larger ones fill a fresh array. *)
let named_shape_fields sh l =
	let names = sh.ns_names in
	let n = Array.length names in
	if n <= 12 then begin
		let order = sh.ns_order in
		match l with
		| [(s0,v0)] when n = 1 && Array.unsafe_get names 0 == s0 ->
			[|v0|]
		| [(s0,v0);(s1,v1)] when n = 2 && Array.unsafe_get names 0 == s0 && Array.unsafe_get names 1 == s1 ->
			[|sel2 (Array.unsafe_get order 0) v0 v1; sel2 (Array.unsafe_get order 1) v0 v1|]
		| [(s0,v0);(s1,v1);(s2,v2)] when n = 3 && Array.unsafe_get names 0 == s0 && Array.unsafe_get names 1 == s1 && Array.unsafe_get names 2 == s2 ->
			[|sel3 (Array.unsafe_get order 0) v0 v1 v2; sel3 (Array.unsafe_get order 1) v0 v1 v2; sel3 (Array.unsafe_get order 2) v0 v1 v2|]
		| [(s0,v0);(s1,v1);(s2,v2);(s3,v3)] when n = 4 && Array.unsafe_get names 0 == s0 && Array.unsafe_get names 1 == s1 && Array.unsafe_get names 2 == s2 && Array.unsafe_get names 3 == s3 ->
			[|sel4 (Array.unsafe_get order 0) v0 v1 v2 v3; sel4 (Array.unsafe_get order 1) v0 v1 v2 v3; sel4 (Array.unsafe_get order 2) v0 v1 v2 v3; sel4 (Array.unsafe_get order 3) v0 v1 v2 v3|]
		| [(s0,v0);(s1,v1);(s2,v2);(s3,v3);(s4,v4)] when n = 5 && Array.unsafe_get names 0 == s0 && Array.unsafe_get names 1 == s1 && Array.unsafe_get names 2 == s2 && Array.unsafe_get names 3 == s3 && Array.unsafe_get names 4 == s4 ->
			[|sel5 (Array.unsafe_get order 0) v0 v1 v2 v3 v4; sel5 (Array.unsafe_get order 1) v0 v1 v2 v3 v4; sel5 (Array.unsafe_get order 2) v0 v1 v2 v3 v4; sel5 (Array.unsafe_get order 3) v0 v1 v2 v3 v4; sel5 (Array.unsafe_get order 4) v0 v1 v2 v3 v4|]
		| [(s0,v0);(s1,v1);(s2,v2);(s3,v3);(s4,v4);(s5,v5)] when n = 6 && Array.unsafe_get names 0 == s0 && Array.unsafe_get names 1 == s1 && Array.unsafe_get names 2 == s2 && Array.unsafe_get names 3 == s3 && Array.unsafe_get names 4 == s4 && Array.unsafe_get names 5 == s5 ->
			[|sel6 (Array.unsafe_get order 0) v0 v1 v2 v3 v4 v5; sel6 (Array.unsafe_get order 1) v0 v1 v2 v3 v4 v5; sel6 (Array.unsafe_get order 2) v0 v1 v2 v3 v4 v5; sel6 (Array.unsafe_get order 3) v0 v1 v2 v3 v4 v5; sel6 (Array.unsafe_get order 4) v0 v1 v2 v3 v4 v5; sel6 (Array.unsafe_get order 5) v0 v1 v2 v3 v4 v5|]
		| [(s0,v0);(s1,v1);(s2,v2);(s3,v3);(s4,v4);(s5,v5);(s6,v6)] when n = 7 && Array.unsafe_get names 0 == s0 && Array.unsafe_get names 1 == s1 && Array.unsafe_get names 2 == s2 && Array.unsafe_get names 3 == s3 && Array.unsafe_get names 4 == s4 && Array.unsafe_get names 5 == s5 && Array.unsafe_get names 6 == s6 ->
			[|sel7 (Array.unsafe_get order 0) v0 v1 v2 v3 v4 v5 v6; sel7 (Array.unsafe_get order 1) v0 v1 v2 v3 v4 v5 v6; sel7 (Array.unsafe_get order 2) v0 v1 v2 v3 v4 v5 v6; sel7 (Array.unsafe_get order 3) v0 v1 v2 v3 v4 v5 v6; sel7 (Array.unsafe_get order 4) v0 v1 v2 v3 v4 v5 v6; sel7 (Array.unsafe_get order 5) v0 v1 v2 v3 v4 v5 v6; sel7 (Array.unsafe_get order 6) v0 v1 v2 v3 v4 v5 v6|]
		| [(s0,v0);(s1,v1);(s2,v2);(s3,v3);(s4,v4);(s5,v5);(s6,v6);(s7,v7)] when n = 8 && Array.unsafe_get names 0 == s0 && Array.unsafe_get names 1 == s1 && Array.unsafe_get names 2 == s2 && Array.unsafe_get names 3 == s3 && Array.unsafe_get names 4 == s4 && Array.unsafe_get names 5 == s5 && Array.unsafe_get names 6 == s6 && Array.unsafe_get names 7 == s7 ->
			[|sel8 (Array.unsafe_get order 0) v0 v1 v2 v3 v4 v5 v6 v7; sel8 (Array.unsafe_get order 1) v0 v1 v2 v3 v4 v5 v6 v7; sel8 (Array.unsafe_get order 2) v0 v1 v2 v3 v4 v5 v6 v7; sel8 (Array.unsafe_get order 3) v0 v1 v2 v3 v4 v5 v6 v7; sel8 (Array.unsafe_get order 4) v0 v1 v2 v3 v4 v5 v6 v7; sel8 (Array.unsafe_get order 5) v0 v1 v2 v3 v4 v5 v6 v7; sel8 (Array.unsafe_get order 6) v0 v1 v2 v3 v4 v5 v6 v7; sel8 (Array.unsafe_get order 7) v0 v1 v2 v3 v4 v5 v6 v7|]
		| [(s0,v0);(s1,v1);(s2,v2);(s3,v3);(s4,v4);(s5,v5);(s6,v6);(s7,v7);(s8,v8)] when n = 9 && Array.unsafe_get names 0 == s0 && Array.unsafe_get names 1 == s1 && Array.unsafe_get names 2 == s2 && Array.unsafe_get names 3 == s3 && Array.unsafe_get names 4 == s4 && Array.unsafe_get names 5 == s5 && Array.unsafe_get names 6 == s6 && Array.unsafe_get names 7 == s7 && Array.unsafe_get names 8 == s8 ->
			[|sel9 (Array.unsafe_get order 0) v0 v1 v2 v3 v4 v5 v6 v7 v8; sel9 (Array.unsafe_get order 1) v0 v1 v2 v3 v4 v5 v6 v7 v8; sel9 (Array.unsafe_get order 2) v0 v1 v2 v3 v4 v5 v6 v7 v8; sel9 (Array.unsafe_get order 3) v0 v1 v2 v3 v4 v5 v6 v7 v8; sel9 (Array.unsafe_get order 4) v0 v1 v2 v3 v4 v5 v6 v7 v8; sel9 (Array.unsafe_get order 5) v0 v1 v2 v3 v4 v5 v6 v7 v8; sel9 (Array.unsafe_get order 6) v0 v1 v2 v3 v4 v5 v6 v7 v8; sel9 (Array.unsafe_get order 7) v0 v1 v2 v3 v4 v5 v6 v7 v8; sel9 (Array.unsafe_get order 8) v0 v1 v2 v3 v4 v5 v6 v7 v8|]
		| [(s0,v0);(s1,v1);(s2,v2);(s3,v3);(s4,v4);(s5,v5);(s6,v6);(s7,v7);(s8,v8);(s9,v9)] when n = 10 && Array.unsafe_get names 0 == s0 && Array.unsafe_get names 1 == s1 && Array.unsafe_get names 2 == s2 && Array.unsafe_get names 3 == s3 && Array.unsafe_get names 4 == s4 && Array.unsafe_get names 5 == s5 && Array.unsafe_get names 6 == s6 && Array.unsafe_get names 7 == s7 && Array.unsafe_get names 8 == s8 && Array.unsafe_get names 9 == s9 ->
			[|sel10 (Array.unsafe_get order 0) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9; sel10 (Array.unsafe_get order 1) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9; sel10 (Array.unsafe_get order 2) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9; sel10 (Array.unsafe_get order 3) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9; sel10 (Array.unsafe_get order 4) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9; sel10 (Array.unsafe_get order 5) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9; sel10 (Array.unsafe_get order 6) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9; sel10 (Array.unsafe_get order 7) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9; sel10 (Array.unsafe_get order 8) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9; sel10 (Array.unsafe_get order 9) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9|]
		| [(s0,v0);(s1,v1);(s2,v2);(s3,v3);(s4,v4);(s5,v5);(s6,v6);(s7,v7);(s8,v8);(s9,v9);(s10,v10)] when n = 11 && Array.unsafe_get names 0 == s0 && Array.unsafe_get names 1 == s1 && Array.unsafe_get names 2 == s2 && Array.unsafe_get names 3 == s3 && Array.unsafe_get names 4 == s4 && Array.unsafe_get names 5 == s5 && Array.unsafe_get names 6 == s6 && Array.unsafe_get names 7 == s7 && Array.unsafe_get names 8 == s8 && Array.unsafe_get names 9 == s9 && Array.unsafe_get names 10 == s10 ->
			[|sel11 (Array.unsafe_get order 0) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10; sel11 (Array.unsafe_get order 1) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10; sel11 (Array.unsafe_get order 2) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10; sel11 (Array.unsafe_get order 3) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10; sel11 (Array.unsafe_get order 4) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10; sel11 (Array.unsafe_get order 5) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10; sel11 (Array.unsafe_get order 6) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10; sel11 (Array.unsafe_get order 7) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10; sel11 (Array.unsafe_get order 8) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10; sel11 (Array.unsafe_get order 9) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10; sel11 (Array.unsafe_get order 10) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10|]
		| [(s0,v0);(s1,v1);(s2,v2);(s3,v3);(s4,v4);(s5,v5);(s6,v6);(s7,v7);(s8,v8);(s9,v9);(s10,v10);(s11,v11)] when n = 12 && Array.unsafe_get names 0 == s0 && Array.unsafe_get names 1 == s1 && Array.unsafe_get names 2 == s2 && Array.unsafe_get names 3 == s3 && Array.unsafe_get names 4 == s4 && Array.unsafe_get names 5 == s5 && Array.unsafe_get names 6 == s6 && Array.unsafe_get names 7 == s7 && Array.unsafe_get names 8 == s8 && Array.unsafe_get names 9 == s9 && Array.unsafe_get names 10 == s10 && Array.unsafe_get names 11 == s11 ->
			[|sel12 (Array.unsafe_get order 0) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11; sel12 (Array.unsafe_get order 1) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11; sel12 (Array.unsafe_get order 2) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11; sel12 (Array.unsafe_get order 3) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11; sel12 (Array.unsafe_get order 4) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11; sel12 (Array.unsafe_get order 5) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11; sel12 (Array.unsafe_get order 6) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11; sel12 (Array.unsafe_get order 7) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11; sel12 (Array.unsafe_get order 8) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11; sel12 (Array.unsafe_get order 9) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11; sel12 (Array.unsafe_get order 10) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11; sel12 (Array.unsafe_get order 11) v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11|]
		| _ -> [||]
	end else begin
		let a = make_fields n in
		if fill_named_shape sh a l then a else [||]
	end

(* The shapes of a bucket whose prototype is current, tried in order; the one that fits moves to
   the front. VNull when none fits: an object is never null. *)
let rec try_named_shapes ctx h bucket l shapes = match shapes with
	| [] ->
		vnull
	| ({ns_proto = Some (id,map,stamp,oproto)} as sh) :: shapes when id = ctx.ctx_id && map == ctx.instance_prototypes && stamp = !collisions ->
		let a = named_shape_fields sh l in
		if Array.length a > 0 || Array.length sh.ns_names = 0 then begin
			(match bucket with
				| sh' :: _ when sh' == sh -> ()
				| _ -> Array.unsafe_set named_shapes h (sh :: List.filter (fun sh' -> sh' != sh) bucket));
			vobject {
				ofields = a;
				oproto = oproto;
			}
		end else
			try_named_shapes ctx h bucket l shapes
	| _ :: shapes ->
		try_named_shapes ctx h bucket l shapes

let encode_obj_s l =
	let ctx = get_ctx() in
	let h = named_shape_hash l in
	let bucket = Array.unsafe_get named_shapes h in
	match try_named_shapes ctx h bucket l bucket with
	| VObject _ as o ->
		o
	| _ ->
		let sh = find_named_shape bucket l in
		let hl = List.map (fun (s,v) -> (hash s),v) l in
		let o = encode_obj hl in
		begin match o with
			| VObject {oproto = OProto proto as oproto} ->
				let sh = match sh with
					| Some sh ->
						sh
					| None ->
						(* get_object_prototype's order: a stable sort on the hashes. *)
						let indexed = List.mapi (fun i (k,_) -> (k,i)) hl in
						let sorted = List.sort (fun (i1,_) (i2,_) -> if i1 = i2 then 0 else if i1 < i2 then -1 else 1) indexed in
						let slot = Array.make (List.length hl) 0 in
						List.iteri (fun j (_,i) -> slot.(i) <- j) sorted;
						let sh = {
							ns_names = Array.of_list (List.map fst l);
							ns_slot = slot;
							ns_order = Array.of_list (List.map snd sorted);
							ns_proto = None;
						} in
						(* Names built on the fly never match physically: keep buckets short. *)
						let bucket = Array.unsafe_get named_shapes h in
						Array.unsafe_set named_shapes h (sh :: (match bucket with a :: b :: c :: d :: e :: f :: g :: _ -> [a;b;c;d;e;f;g] | _ -> bucket));
						sh
				in
				sh.ns_proto <- Some (ctx.ctx_id,ctx.instance_prototypes,!collisions,oproto);
				ignore proto
			| _ ->
				()
		end;
		o

(* Enum values *)

let encode_enum_value path i vl pos =
	venum_value {
		eindex = i;
		eargs = vl;
		epath = path;
		enpos = pos;
	}

let encode_enum i pos index pl =
	let open MacroApi in
	let key = match i with
		| IExpr -> key_haxe_macro_ExprDef
		| IEFieldKind -> key_haxe_macro_EFieldKind
		| IBinop -> key_haxe_macro_Binop
		| IUnop -> key_haxe_macro_Unop
		| IConst -> key_haxe_macro_Constant
		| ITParam -> key_haxe_macro_TypeParam
		| ICType -> key_haxe_macro_ComplexType
		| IField -> key_haxe_macro_FieldType
		| IType -> key_haxe_macro_Type
		| IFieldKind -> key_haxe_macro_FieldKind
		| IMethodKind -> key_haxe_macro_MethodKind
		| IVarAccess -> key_haxe_macro_VarAccess
		| IAccess -> key_haxe_macro_Access
		| IClassKind -> key_haxe_macro_ClassKind
		| ITypedExpr -> key_haxe_macro_TypedExprDef
		| ITConstant -> key_haxe_macro_TConstant
		| IModuleType -> key_haxe_macro_ModuleType
		| IFieldAccess -> key_haxe_macro_FieldAccess
		| IAnonStatus -> key_haxe_macro_AnonStatus
		| IImportMode -> key_haxe_macro_ImportMode
		| IQuoteStatus -> key_haxe_macro_QuoteStatus
		| IDisplayKind -> key_haxe_macro_DisplayKind
		| IDisplayMode -> key_haxe_macro_DisplayMode
		| ICapturePolicy -> key_haxe_macro_CapturePolicy
		| IVarScope -> key_haxe_macro_VarScope
		| IVarScopingFlags -> key_haxe_macro_VarScopingFlags
		| IPackageRule -> key_haxe_macro_PackageRule
		| IMessage -> key_haxe_macro_Message
		| IFunctionKind -> key_haxe_macro_FunctionKind
		| IStringLiteralKind -> key_haxe_macro_StringLiteralKind
	in
	encode_enum_value key index (values_of_list pl) pos

(* Instances *)

let create_instance_direct proto kind =
	vinstance {
		ifields = if Array.length proto.pinstance_fields = 0 then proto.pinstance_fields else Array.copy proto.pinstance_fields;
		iproto = proto;
		ikind = kind;
	}

let create_instance ?(kind=INormal) path =
	let proto = get_instance_prototype (get_ctx()) path null_pos in
	{
		ifields = if Array.length proto.pinstance_fields = 0 then proto.pinstance_fields else Array.copy proto.pinstance_fields;
		iproto = proto;
		ikind = kind;
	}

let encode_instance ?(kind=INormal) path =
	vinstance (create_instance ~kind path)

let encode_array_instance a =
	VArray a

let encode_vector_instance v =
	VVector v

let encode_array l =
	encode_array_instance (EvalArray.create (values_of_list l))

let encode_array_a a =
	encode_array_instance (EvalArray.create a)

let encode_string s =
	create_unknown s

(* The macro API encodes the same strings of the compiler's data again and again (class
   documentation every time a type is dereferenced, above all), and computing their UTF-8 length
   each time dominated macro-heavy compilations. Long strings remember their length, keyed by the
   string itself, compared physically: the value is exactly what encode_string returns, a fresh one
   on every call. Only for the compiler's own strings, which are never mutated. A direct-mapped
   table of pairs: one write replaces an entry whole. *)
let length_cache = Array.make 4096 ("",0)

let encode_string_cached s =
	let n = String.length s in
	if n < 64 then
		create_unknown s
	else begin
		let h = (n + 31 * Char.code (String.unsafe_get s (n lsr 1)) + 961 * Char.code (String.unsafe_get s (n - 1))) land 4095 in
		let (s',l) = Array.unsafe_get length_cache h in
		if s' == s then
			vstring (create_with_length s l)
		else begin
			let vs = create_unknown_vstring s in
			Array.unsafe_set length_cache h (s,vs.slength);
			vstring vs
		end
	end

(* Should only be used for std types that aren't expected to change while the compilation server is running *)
let create_cached_instance path fkind =
	let proto = lazy (get_instance_prototype (get_ctx()) path null_pos) in
	(fun v ->
		create_instance_direct (Lazy.force proto) (fkind v)
	)

let encode_bytes =
	create_cached_instance key_haxe_io_Bytes (fun s -> IBytes s)

let encode_int_map_direct =
	create_cached_instance key_haxe_ds_IntMap (fun s -> IIntMap s)

let encode_string_map_direct =
	create_cached_instance key_haxe_ds_StringMap (fun s -> IStringMap s)

let encode_object_map_direct =
	create_cached_instance key_haxe_ds_ObjectMap (fun (s : value ValueHashtbl.t) -> IObjectMap (Obj.magic s))

let encode_string_map convert m =
	let h = StringHashtbl.create () in
	PMap.iter (fun key value -> StringHashtbl.add h (create_ascii key) (convert value)) m;
	encode_string_map_direct h

let fake_proto path =
	let proto = {
		ppath = path;
		pfields = [||];
		pnames = IntMap.empty;
		pinstance_names = IntMap.empty;
		pinstance_fields = [||];
		pparent = None;
		pkind = PInstance;
		pvalue = vnull;
	} in
	proto.pvalue <- vprototype proto;
	proto

(* One prototype per kind of opaque macro value, where each value used to get a fresh one.
   Nothing tells them apart: an instance's prototype is only ever read for its content (names,
   path, kind, parent), and Type.getClass and Type.typeof look classes up by path. Created
   eagerly, so that eval threads never race on forcing them. *)
let position_proto = fake_proto key_haxe_macro_Position
let lazytype_proto = fake_proto key_haxe_macro_LazyType
let typedecl_proto = fake_proto key_haxe_macro_TypeDecl
let unsafe_proto = fake_proto key_haxe_macro_Unsafe

let encode_unsafe o =
	vinstance {
		ifields = [||];
		iproto = unsafe_proto;
		ikind = IRef (Obj.repr o);
	}

let encode_pos p =
	vinstance {
		ifields = [||];
		iproto = position_proto;
		ikind = IPos p;
	}

let encode_lazytype t f =
	vinstance {
		ifields = [||];
		iproto = lazytype_proto;
		ikind = ILazyType(t,f);
	}

let encode_tdecl t =
	vinstance {
		ifields = [||];
		iproto = typedecl_proto;
		ikind = ITypeDecl t;
	}

let ref_proto =
	let proto = {
		ppath = key_haxe_macro_Ref;
		pfields = [||];
		pnames = IntMap.empty;
		pinstance_names = IntMap.add key_get 0 (IntMap.singleton key_toString 1);
		pinstance_fields = [|vnull;vnull|];
		pparent = None;
		pkind = PInstance;
		pvalue = vnull;
	} in
	proto.pvalue <- vprototype proto;
	proto

(* The two methods are vifun0 of a function ignoring its argument, written as one closure each. *)
let encode_ref v convert tostr =
	vinstance {
		ifields = [|
			vfunction (fun vl -> match vl with
				| [] | [_] -> convert v
				| _ -> invalid_call_arg_number 1 (List.length vl));
			vfunction (fun vl -> match vl with
				| [] | [_] -> encode_string (tostr())
				| _ -> invalid_call_arg_number 1 (List.length vl));
		|];
		iproto = ref_proto;
		ikind = IRef (Obj.repr v);
	}

let encode_lazy f =
	let rec r = ref (fun () ->
		let v = f() in
		r := (fun () -> v);
		v
	) in
	VLazy r

let encode_option encode_value o =
	match o with
	| Some v -> encode_enum_value key_haxe_ds_Option 0 [|encode_value v|] None
	| None -> encode_enum_value key_haxe_ds_Option 1 [||] None

let encode_nullable encode_value o =
	match o with
	| Some v -> encode_value v
	| None -> VNull
